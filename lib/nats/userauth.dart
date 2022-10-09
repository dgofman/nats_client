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

import '../natslite/constants.dart';

class UserAuthenticator extends BaseAuthenticator {

  UserAuthenticator(String user, [String? password]): super() {
    if (password == null) {
      additionalOptions['auth_token'] = user;
    } else {
      additionalOptions.addAll({
        'user': user,
        'pass': password
      });
    }
  }
}