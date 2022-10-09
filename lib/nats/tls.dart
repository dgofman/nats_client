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
import 'package:flutter/services.dart';

import '../natslite/constants.dart';

class TlsTrustedClient extends BaseTLS {
  final String? password;
  final String p12CertAssetPath;
  TlsTrustedClient(this.p12CertAssetPath, [this.password = '']);

  ByteData? clientCert;

  @override
  Future<void> init() async {
    super.init();
    clientCert = await rootBundle.load(p12CertAssetPath);
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    if (context == null) {
      context = SecurityContext.defaultContext;
      context.setTrustedCertificatesBytes(clientCert!.buffer.asUint8List(), password: password);
    }
    return super.createHttpClient(context);
  }
}