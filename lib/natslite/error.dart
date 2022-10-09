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

class NatsError implements Exception {
  final String name;
  final String message;
  final ErrorCode error;
  final Error? chainedError;

  NatsError(this.message, this.error, [this.chainedError, this.name = 'NatsError']);

  static errorForCode(ErrorCode error, [Error? chainedError]) {
    return NatsError(error.message, error, chainedError);
  }

  @override
  String toString() {
    return '$name[${error.code}] ${error.message}';
  }
}

class ErrorCode {
  static const InvalidPrefixByte = ErrorCode('InvalidPrefixByte', 'nkeys: invalid prefix byte');
  static const InvalidSeed = ErrorCode('InvalidSeed', 'nkeys: invalid seed');
  static const InvalidEncoding = ErrorCode('InvalidEncoding', 'nkeys: invalid encoded key');
  static const InvalidChecksum = ErrorCode('InvalidChecksum', 'nkeys: invalid checksum');
  static const BAD_AUTHENTICATION = ErrorCode('BAD_AUTHENTICATION', 'Invalid authentication payload');
  static const BAD_CREDS = ErrorCode('BAD_CREDS', 'Invalid credentials');
  static const BAD_PAYLOAD = ErrorCode('BAD_PAYLOAD', 'Invalid payload');
  static const BAD_SUBJECT = ErrorCode('BAD_SUBJECT', 'Invalid subject');
  static const INVALID_PAYLOAD_TYPE = ErrorCode('INVALID_PAYLOAD_TYPE', 'Invalid payload type - payloads can be \'binary\', \'string\', or \'json\'');
  static const SERVER_OPTION_NA = ErrorCode('SERVER_OPTION_NA', 'Invalid server parameters');
  static const INVALID_OPTION = ErrorCode('INVALID_OPTION', 'Invalid options');
  static const TIMEOUT = ErrorCode('TIMEOUT', 'Request Timeout');

  final String code;
  final String message;

  const ErrorCode(this.code, this.message);
}