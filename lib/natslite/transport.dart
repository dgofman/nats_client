// ignore_for_file: constant_identifier_names

/*
 * Copyright 2021 Developed by David Gofman
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:developer';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import './subscription.dart';
import './constants.dart';
import './error.dart';

enum _Command { PONG, PING, OK, MSG, HMSG, ERROR }

class WsTransport {
  static const NULL = null;
  static const int _CR = 13;
  static const int _LF = 10;
  static const String _CR_LF = '\r\n';
  static const List<int> _CRLF = [_CR, _LF];
  static final info = RegExp(r'^INFO\s+([^\r\n]+)\r\n', caseSensitive: false);

  static final cmdMap = {
    _Command.PING: utf8.encode('PING\r\n'),
    _Command.PONG: utf8.encode('PONG\r\n'),
    _Command.OK: utf8.encode('+OK\n'),
    _Command.MSG: utf8.encode('MSG '),
    _Command.HMSG: utf8.encode('HMSG '),
    _Command.ERROR: utf8.encode('-ERR ')
  };

  final subs = <int, Subscription>{};
  final BaseAuthenticator auth;
  final Map<String, dynamic> _opts;
  final Function(Status, dynamic error) _statusCallback;
  late Completer _pongCompleter;
  late Duration _pingInterval;
  late int _maxReconnectAttempts;
  late int _reconnectTimeWait;
  late int _reconnectAttempts;
  late List<String> _servers;
  Timer? _outboundTimer;
  WebSocketChannel? _socket;
  int _sidCounter = 0;
  bool _peeked = false;
  bool _closed = true;
  final List<int> _outbound = [];
  OpenSubscription? _openSubscription;
  // ignore: cancel_subscriptions
  StreamSubscription? _subscription;

  WsTransport(this._opts, this.auth, this._statusCallback) {
    _pongCompleter = Completer.sync();
    _pingInterval = Duration(milliseconds: _opts['pingInterval']);
    _maxReconnectAttempts = _opts['maxReconnectAttempts'];
    _reconnectTimeWait = _opts['reconnectTimeWait'];
    _reconnectAttempts = 0;
  }

  Subscription subscribe(String subject, SubCallback? callback, String? queue, bool delay) {
    if (subject.isEmpty) {
      throw NatsError.errorForCode(ErrorCode.BAD_SUBJECT);
    }
    final s = Subscription(this, ++_sidCounter, subject, callback);
    subs[s.sid] = s;
    String proto = 'SUB $subject ';
    if (queue != null) {
      proto += '$queue ${s.sid}\r\n';
    } else {
      proto += '${s.sid}\r\n';
    }
    _delayCommand(utf8.encode(proto), delay);
    debug('Nats::subscribe($delay) - $proto');
    return s;
  }

  void unsubscribe(Subscription s, bool delay) {
    if (subs[s.sid] != null) {
      String proto = 'UNSUB ${s.sid}\r\n';
      _delayCommand(utf8.encode(proto), delay);
      debug('Nats::unsubscribe($delay) - $proto');
    }
  }

  void publish(String subject, List<int> data, Map<String, dynamic> options) {
    bool delay = options['delay'] ?? true;
    List<int> proto = [];
    List<int>? headers;
    if (options['headers'] is Map) {
      List<String> build = ['NATS/1.0'];
      options['headers'].forEach((key, value)  {
        build.add('$key: $value');
      });
      build.add('\r\n');
      headers = utf8.encode(build.join('\r\n'));
      final hlen = headers.length;
      final len = data.length + hlen;
      if (options['reply'] is String) {
        proto.addAll(utf8.encode('HPUB $subject ${options['reply']} $hlen $len\r\n'));
      } else {
        proto.addAll(utf8.encode('HPUB $subject $hlen $len\r\n'));
      }
    } else {
      if (options['reply'] is String) {
        proto.addAll(utf8.encode('PUB $subject ${options['reply']} ${data.length}\r\n'));
      } else {
        proto.addAll(utf8.encode('PUB $subject ${data.length}\r\n'));
      }
    }
    if (headers != null) {
      proto.addAll(headers);
    }
    proto.addAll(data);
    proto.addAll(_CRLF);
    _delayCommand(proto, delay, headers);
    debug('Nats::publish($delay) - $subject');
  }

  void _delayCommand(List<int> data, bool delay, [List<int>? headers]) {
    if (data.isEmpty) return;
    if (!delay) {
      _noDelayCommand(data);
    } else {
      _outbound.addAll(data);
      if (_outboundTimer != null) {
        _outboundTimer?.cancel();
      }
      _outboundTimer = Timer(Duration.zero, () {
        _outboundTimer!.cancel();
        final utf8 = Uint8List.fromList(_outbound);
        _noDelayCommand(utf8);
        _outbound.clear();
      });
    }
  }

  void _noDelayCommand(List<int> data) {
    if (_pongCompleter.isCompleted) {
      send(data);
    } else {
      _pongCompleter.future.then((_) {
        send(data);
      });
    }
  }

  Future<void> connect(List<String> servers) async {
    String currentServer = servers[0];
    if (servers.isNotEmpty) {
      servers.removeRange(0, 1);
      servers.add(currentServer);
    }
    _servers = servers;
    if (_subscription != null) {
      _subscription!.cancel();
    }
    if (kIsWeb) {
      _socket = WebSocketChannel.connect(Uri.parse(currentServer));
    } else {
      _socket = IOWebSocketChannel.connect(currentServer, pingInterval: _pingInterval);
    }
    _outbound.clear();
    _subscription = _socket!.stream.listen((data) async {
      _closed = false;
      if (_openSubscription != null) {
        final o = _openSubscription!;
        o.buffer.addAll(data);
        if (o.buffer.length >= o.totalBytes + 2) { // end message [_CR, _LF]
          o.subscription.callback!(Result(o.buffer.sublist(0, o.totalBytes), o.subscription, o.subject));
          _openSubscription = null;
        }
        return;
      }
      if (_peeked) {
        await parse(data);
        return;
      }
      final len = protoLen(data);
      if (len > 0) {
        Uint8List out = data.sublist(0, len);
        final pm = utf8.decode(out);
        debug(pm, '>>>');
        if (pm.isNotEmpty) {
          final m = info.allMatches(pm);
          if (m.length != 1 || m.elementAt(0).groupCount != 1) {
            throw NatsError.errorForCode(ErrorCode.BAD_PAYLOAD);
          }
          String jsonString = m.elementAt(0).group(1).toString();
          try {
            Map info = jsonDecode(jsonString);
            checkOptions(info, _opts);
            _peeked = true;

            final conn = auth.getConnect(info['nonce'], _opts);
            final cs = json.encode(conn);
            send(utf8.encode('CONNECT $cs$_CR_LF'));
            send(cmdMap[_Command.PING]);
            _statusCallback(Status.CONNECT, null);
          } catch (err) {
            debug(err, 'Socket connection error: ');
            _pongCompleter.completeError(err);
          }
        }
      }
      //
    }, onError: (Object error, StackTrace stackTrace) {
      debug(error, '<<< socketOnError: ');
      _statusCallback(Status.STALE_CONNECTION, error);
    }, onDone: () {
      debug('<<< socketOnDone, reconnectAttempts=$_reconnectAttempts, maxReconnectAttempts=$_maxReconnectAttempts');
      if (_maxReconnectAttempts == 0 || _reconnectAttempts < _maxReconnectAttempts) {
        _reconnectAttempts++;
        if (!_closed && _socket!.closeCode != null) {
          _closed = true;
          _socket!.sink.close(status.goingAway);
        }
        reconnect();
      } else {
        close();
      }
    });
  }

  void close() {
    _closed = true;
    if (_subscription != null) {
      _subscription!.cancel();
    }
    if (_socket != null) {
      _socket!.sink.close();
    }
    _statusCallback(Status.SOCKET_CLOSED, null);
  }

  bool isClosed() {
    return _closed || !_peeked;
  }

  Future<void> reconnect() {
    return Future.delayed(Duration(milliseconds: _reconnectTimeWait), () {
      _statusCallback(Status.RECONNECTING, null);
      _peeked = false;
      _pongCompleter = Completer.sync()
        ..future.then((_) {
          final proto = StringBuffer();
          for (Subscription s in subs.values) {
            proto.write('SUB ${s.subject} ${s.sid}\r\n');
          }
          send(utf8.encode(proto.toString()));
          _reconnectAttempts = 0;
        });
      connect(_servers);
    });
  }

  void checkOptions(Map info, Map opts) {
    var proto = info['proto'],
        headers = info['headers'],
        tlsRequired = info['tls_required'];
    if ((proto == null || proto < 1) && opts['noEcho']) {
      throw NatsError('noEcho', ErrorCode.SERVER_OPTION_NA);
    }
    if ((proto == null || proto < 1) && opts['headers'] != null) {
      throw NatsError('headers', ErrorCode.SERVER_OPTION_NA);
    }
    if (headers != true) {
      throw NatsError('headers', ErrorCode.SERVER_OPTION_NA);
    }
    if ((proto == null || proto < 1) && opts['noResponders']) {
      throw NatsError('noResponders', ErrorCode.SERVER_OPTION_NA);
    }
    if (!headers && opts['noResponders']) {
      throw NatsError(
          'noResponders - requires headers', ErrorCode.SERVER_OPTION_NA);
    }
    if (opts['tls'] != null && !tlsRequired) {
      throw NatsError('tls', ErrorCode.SERVER_OPTION_NA);
    }
  }

  Future<void> parse(Uint8List data) async {
    _Command? command;
    for (_Command cmd in cmdMap.keys) {
      Uint8List buf = Uint8List.fromList(cmdMap[cmd]!);
      outer:
      if (data.length >= buf.length) {
        for (int i = 0; i < buf.length; i++) {
          if (buf[i] != data[i]) {
            continue outer;
          }
        }
        command = cmd;
        break;
      }
    }
    switch (command ?? '') {
      case _Command.PING:
        _statusCallback(Status.PING_TIMER, null);
        send(cmdMap[_Command.PONG]);
        break;
      case _Command.PONG:
        _statusCallback(Status.PONG_TIMER, null);
        if (!_pongCompleter.isCompleted) {
          _pongCompleter.complete();
        }
        break;
      case _Command.OK:
        _statusCallback(Status.OK_MSG, null);
        send(cmdMap[_Command.OK]);
        break;
      case _Command.ERROR:
        final error = utf8.decode(data.sublist(cmdMap[_Command.ERROR]!.length, data.length - 2));
        _statusCallback(Status.ERROR, error);
        break;
      case _Command.MSG:
      case _Command.HMSG:
        String? subject;
        int? sid;
        int totalBytes = 0;
        int i, start = cmdMap[command]!.length;
        for (i = start; i < data.length; i++) {
          if (data[i] == 32) {
            subject = utf8.decode(data.sublist(start, i));
            break;
          }
        }
        start = i + 1;
        for (i = start; i < data.length; i++) {
          if (data[i] == 32) {
            sid = protoParseInt(data.sublist(start, i));
            break;
          }
        }
        start = i + 1;
        for (i = start; i < data.length; i++) {
          if (data[i] == 13 && data[i + 1] == 10) {
            totalBytes = protoParseInt(data.sublist(start, i));
            break;
          }
        }
        start = i + 2;
        if (subs != null && subs[sid] != null) {
          Subscription s = subs[sid]!;
          if (totalBytes > 0 && s.callback is SubCallback) {
            if (start + totalBytes < data.length) {
              s.callback!(
                  Result(data.sublist(start, start + totalBytes), s, subject));
            } else {
              _openSubscription = OpenSubscription(s, subject, totalBytes);
              if (data.length > start) {
                _openSubscription!.buffer.addAll(data.sublist(start));
              }
            }
          }
        }
        break;
    }
  }

  void send(List<int>? data) {
    if (data == null || data.isEmpty || isClosed()) {
      return;
    }
    try {
      _socket!.sink.add(data);
    } catch (err) {
      debug(data, '!!! $err');
    }
  }

  int protoLen(Uint8List ba) {
    for (int i = 0; i < ba.length; i++) {
      int n = i + 1;
      if (ba.length > n && ba[i] == _CR && ba[n] == _LF) {
        return n + 1;
      }
    }
    return -1;
  }

  int protoParseInt(a) {
    if (a.length == 0) {
      return -1;
    }
    int n = 0;
    for(int i = 0; i < a.length; i++){
      if (a[i] < 48 || a[i] > 57) {
        return -1;
      }
      int val = (a[i] - 48);
      n = n * 10 + val;
    }
    return n;
  }

  void debug(dynamic msg, [String prefix = '']) {
    if (_opts['debug'] == true) {
      if (msg is Exception) {
        msg = msg.toString();
      } else if (msg is! String) {
        try {
          msg = utf8.decode(msg);
        } catch (e) {
          return;
        }
      } else if (msg != NULL) {
        msg.toString();
      } else {
        log('NATS::$prefix IS NULL');
        return;
      }
      return log('NATS::$prefix $msg'
          .replaceAll(RegExp('\n'), '␍')
          .replaceAll(RegExp('\r'), '␊'));
    }
  }
}