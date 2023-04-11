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
 *
 *  Source:
 *  https://github.com/nats-io/nats.ws
 * ./node_modules/nats.ws/nats.mjs
 *
 * Example:

import './nats.dart';
import './authenticator.dart' show auth;

main(List<String> args) async {
  String token = '-----BEGIN NATS USER JWT-----\n...';
  final conn = await Nats.connect(
        opts: {'servers': 'wss://{HOST}:{PORT}'},
        authenticator: auth.credsAuthenticator(token),
        debug: true,
        statusCallback: (status, error) {
          if (error != null) {
            addMessage('$status (${error.toString()})');
          } else {
            addMessage('Received status update: $status');
          }
        });
    conn.subscribe('chat', (res) {
      var js = json.decode(utf8.decode(res.data));
      if (js['id'] == me) {
        addMessage("(me): ${js['m']}");
      } else {
        addMessage("(${js['id']}): ${js['m']}");
      }
    });
    conn.subscribe('enter', (res) {
      addMessage("${json.decode(utf8.decode(res.data))['id']} entered.");
    });
    conn.subscribe('exit', (res) {
      addMessage("${json.decode(utf8.decode(res.data))['id']} exited.");
    });
    conn.publish('enter', utf8.encode(json.encode({'id': me})));
  }
}
*/

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'constants.dart';
import './subscription.dart';
import './transport.dart';
import 'error.dart';

class Nats {
  static const Empty = [0];

  static const _DEFAULT_HOST = '127.0.0.1';
  static const _DEFAULT_PORT = 4222;
  static const _DEFAULT_PING_INTERVAL = 2 * 60 * 1000;
  static const _DEFAULT_RECONNECT_TIME_WAIT = 2 * 1000;

  final Map<String, dynamic> opts;

  late WsTransport _transport;

  Nats({this.opts = const {},
    Function(Status status, dynamic error) ? statusCallback,  BaseAuthenticator? authenticator, bool debug = false}) {
    opts.putIfAbsent('debug', () => debug);
    opts.putIfAbsent('maxPingOut', () => 2);
    opts.putIfAbsent('maxReconnectAttempts', () => 10);
    opts.putIfAbsent('noEcho', () => false);
    opts.putIfAbsent('noResponders', () => true);
    opts.putIfAbsent('noRandomize', () => false);
    opts.putIfAbsent('pedantic', () => false);
    opts.putIfAbsent('pingInterval', () => _DEFAULT_PING_INTERVAL);
    opts.putIfAbsent('reconnect', () => true);
    opts.putIfAbsent('reconnectTimeWait', () => _DEFAULT_RECONNECT_TIME_WAIT);
    opts.putIfAbsent('tls', () => null);
    opts.putIfAbsent('verbose', () => false);
    opts.putIfAbsent('waitOnFirstConnect', () => false);
    statusCallback ??= (data, isError) {};
    authenticator ??= BaseAuthenticator();

    _transport = WsTransport(opts, authenticator, statusCallback);
  }

  BaseAuthenticator get authenticator {
    return _transport.authenticator;
  }

  Subscription subscribe(String subject, [SubCallback? callback, String? queue, bool delay=true]) {
    if (subject.isEmpty) {
      throw NatsError.errorForCode(ErrorCode.BAD_SUBJECT);
    }
    return _transport.subscribe(subject, callback, queue, delay);
  }

  Nats unsubscribe(Subscription s, [bool delay=true]) {
    _transport.unsubscribe(s, delay);
    return this;
  }

  Nats publish(String subject, [List<int> data = Empty, Map<String, dynamic> options = const {'delay': true}]) {
    if (subject.isEmpty) {
      throw NatsError.errorForCode(ErrorCode.BAD_SUBJECT);
    }
    if (data == Empty && data is! Int32List) {
      throw NatsError.errorForCode(ErrorCode.BAD_PAYLOAD);
    }
    _transport.publish(subject, data, options);
    return this;
  }

  Future<dynamic> request(String subject, [List<int> data = Empty, Map<String, dynamic> opts = const {}]) async {
    if (subject.isEmpty) {
      throw NatsError.errorForCode(ErrorCode.BAD_SUBJECT);
    }
    final timeout = opts['timeout'] ?? this.opts['timeout'] ?? 1000;
    if (timeout < 1) {
      throw NatsError('timeout', ErrorCode.INVALID_OPTION);
    }
    final unsub = opts['unsub'] ?? true; // auto subscribe
    var time = 0, result = Empty;
    const tick = 100;
    final baseInbox = createInbox();
    final sub = subscribe('$baseInbox*', (res) {
      result = res.data;
    });
    publish(subject, data, {
      'reply': '$baseInbox${uuid()}',
      'headers': opts['headers']
    });
    while (result == Empty && (time += tick) < timeout) {
      await Future.delayed(const Duration(milliseconds: tick));
    }
    if (unsub) {
      unsubscribe(sub);
    }
    if (result == Empty) {
      throw NatsError.errorForCode(ErrorCode.TIMEOUT);
    }
    return result;
  }

  String uuid() {
    final random = Random();
    final buf = StringBuffer(random.nextInt(10));
    for (int i = 0; i < 7; i++) {
      buf.write(random.nextInt(1 << 16).toRadixString(16).padLeft(3, '0').substring(0, 3));
    }
    return buf.toString();
  }

  String createInbox() {
    return '_INBOX.${uuid()}.';
  }

  void close() {
    _transport.close();
  }

  bool isClosed() {
    return _transport.isClosed();
  }

  Future<void> reconnect() async {
    return await _transport.reconnect();
  }

  static Future<Nats> connect({Map<String, dynamic> opts = const {},
    Function(Status status, dynamic error)? statusCallback,
    BaseAuthenticator? authenticator,
    bool debug = false}) async {
    Nats nats = Nats(opts: opts, statusCallback: statusCallback, authenticator: authenticator, debug: debug);
    return await nats.init();
  }

  Future<Nats> init([dynamic server]) async {
    server ??= opts['servers'];
    List<String> servers = [];
    if (server == null) {
      servers.add('$_DEFAULT_HOST:$_DEFAULT_PORT');
    } else {
      if (server is List<String?>) {
        for (String? server in server) {
          servers.add(server.toString());
        }
      } else {
        servers.add(server.toString());
      }
    }
    await _transport.connect(servers);
    return Future.value(this);
  }
}