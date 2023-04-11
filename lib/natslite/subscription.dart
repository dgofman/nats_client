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

import 'dart:convert';

import './transport.dart';

class SubscriptionResult {
  final List<int> data;
  final Subscription sub;
  final String? subject;
  SubscriptionResult(this.data, this.sub, this.subject);

  dynamic get decode => utf8.decode(data);
  dynamic get jsonData => json.decode(decode);
}

typedef SubCallback = Null Function(SubscriptionResult result);

class Subscription {
  final WsTransport transport;
  final int sid;
  final String subject;
  final SubCallback? callback;

  Subscription(this.transport, this.sid, this.subject, this.callback);

  void unsubscribe() {
    transport.send(utf8.encode('UNSUB $sid $subject\r\n'));
    transport.subs.remove(sid);
  }
}

class OpenSubscription {
  final Subscription subscription;
  final String? subject;
  final int totalBytes;
  final List<int> buffer = [];

  OpenSubscription(this.subscription, this.subject, this.totalBytes);
}