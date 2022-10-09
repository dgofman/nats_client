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

import './sign.dart';
import '../natslite/error.dart';
import '../natslite/constants.dart';

class CredsAuthenticator extends BaseAuthenticator {

  CredsAuthenticator(String creds) {
      RegExp re = RegExp(
        r'\s*(?:(?:[-]{3,}[^\n]*[-]{3,}\n)(.+)(?:\n\s*[-]{3,}[^\n]*[-]{3,}\n))',
        caseSensitive: false,
        multiLine: true,
      );
      var m = re.allMatches(creds);
      if (m.length != 2 ||
          m.elementAt(0).groupCount != 1 ||
          m.elementAt(1).groupCount != 1) {
        throw NatsError.errorForCode(ErrorCode.BAD_CREDS);
      }
      String jwt = m.elementAt(0).group(1).toString().trim();
      String seed = m.elementAt(1).group(1).toString().trim();
      additionalOptions['jwt'] = jwt;
      auth = (String? nonce) {
        additionalOptions.addAll(encodeSeed(seed, nonce));
        return additionalOptions;
      };
  }
}