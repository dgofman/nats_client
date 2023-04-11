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

import 'dart:io';

const VERSION = '2.0';
const LANG = 'dg-nats-client';

enum Status {
  OK_MSG,
  RECONNECTING,
  PING_TIMER,
  PONG_TIMER,
  STALE_CONNECTION,
  SOCKET_CLOSED,
  CONNECT,
  ERROR
}

class Prefix {
  static const Seed = 144;
  static const Server = 104;
  static const Operator = 112;
  static const Cluster = 16;
  static const User = 160;
  static const Account = 0;
//static const Private = 120;
}

class SignLength {
  static const Seed = 32;
  static const Signature = 64;
}

class BaseTLS extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);
  }
}

class BaseAuthenticator {

  final Map<String, dynamic> additionalOptions = {};
  Map<String, dynamic> Function(String? nonce)? auth;

  BaseAuthenticator() {
    auth = (String? nonce) => additionalOptions;
  }

  BaseAuthenticator buildAuthenticator() => this;

  Map getConnect(String? nonce, Uri serverURI, Map<String, dynamic> opts) {
    final conn = auth!(nonce);
    conn.addAll({
      'protocol': 1,
      'version': VERSION,
      'lang': '$LANG.${serverURI.scheme}',
      'verbose': opts['verbose'] ?? false,
      'pedantic': opts['pedantic'] ?? false,
      'no_responders': opts['noResponders'] ?? true,
      'headers': opts['headers'] ?? true
    });
    if (!opts['noEcho']) conn['echo'] =  !opts['noEcho'];
    if (opts['name'] != null) conn['name'] =  opts['name'];
    if (opts['tls'] != null) conn['tls_required'] =  true;
    return conn;
  }
}