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
import 'dart:typed_data';
import 'package:base32/base32.dart';

import '../natslite/error.dart';
import '../natslite/constants.dart';
import './crc16.dart' show crc16;

/*
*  *********** PUBLIC FUNCTIONS ***********
*/
Map<String, String> encodeSeed(seed, nonce) {
  final sd = _decodeSeed(seed);
  final kp = _signKeyPairFromSeed(sd);
  final challenge = Uint8List.fromList(utf8.encode(nonce ?? ''));
  final signedMsg = Int32List(SignLength.Signature + challenge.length);
  _sign(signedMsg, challenge, challenge.length, kp['secretKey']);
  final b = Uint8List(SignLength.Signature);
  for (int i1 = 0; i1 < b.length; i1++) {
    b[i1] = signedMsg[i1];
  }
  final sig = base64.encode(b);
  final nkey = _encode(false, sd['prefix'], kp['publicKey']);
  return {'nkey': nkey, 'sig': sig};
}

/*
*  *********** PRIVATE FUNCTIONS ***********
*/

Map _decodeSeed(String src) {
  final raw = _decode(src);
  final prefix = _decodePrefix(raw);
  if (prefix[0] != Prefix.Seed) {
    throw NatsError.errorForCode(ErrorCode.InvalidSeed);
  }
  if (!_isValidPublicPrefix(prefix[1])) {
    throw NatsError.errorForCode(ErrorCode.InvalidPrefixByte);
  }
  return {'buf': raw.sublist(2), 'prefix': prefix[1]};
}

Map _signKeyPairFromSeed(Map sd) {
  Uint8List buf = sd['buf'];
  if (buf.length != SignLength.Seed) {
    throw NatsError('bad seed size', ErrorCode.InvalidSeed);
  }
  Int32List d = Int32List(64);
  Int32List pk = Int32List(buf.length);
  Int32List sk = Int32List.fromList([...buf, ...pk]);
  final p = [Int32List(16), Int32List(16), Int32List(16), Int32List(16)];
  _hash(d, sk, 32);
  d[0] &= 248;
  d[31] &= 127;
  d[31] |= 64;
  _scalarbase(p, d);
  _pack(pk, p);
  for (int i1 = 0; i1 < 32; i1++) {
    sk[i1 + 32] = pk[i1];
  }
  return {'publicKey': pk, 'secretKey': sk};
}

String _encode(bool seed, int role, Int32List payload) {
  final payloadOffset = seed ? 2 : 1;
  final payloadLen = payload.length;
  final cap = payloadOffset + payloadLen + 2;
  final checkOffset = payloadOffset + payloadLen;
  final raw = Uint8List(cap);
  if (seed) {
    final encodedPrefix = _encodePrefix(Prefix.Seed, role);
    raw.setAll(0, encodedPrefix);
  } else {
    raw[0] = role;
  }
  raw.setAll(payloadOffset, payload);
  final checksum = crc16.checksum(raw.sublist(0, checkOffset));
  final dv = ByteData.sublistView(raw);
  dv.setUint16(checkOffset, checksum, Endian.little);
  return base32.encode(raw);
}

Int32List _sign(Int32List sm, Uint8List m, int n, Int32List sk) {
  final d = Int32List(64), h = Int32List(64), r = Int32List(64);
  final x = Int32List(64);
  final p = [Int32List(16), Int32List(16), Int32List(16), Int32List(16)];
  int i1, j;
  _hash(d, sk, 32);
  d[0] &= 248;
  d[31] &= 127;
  d[31] |= 64;
  for (i1 = 0; i1 < n; i1++) {
    sm[64 + i1] = m[i1];
  }
  for (i1 = 0; i1 < 32; i1++) {
    sm[32 + i1] = d[32 + i1];
  }
  _hash(r, sm.sublist(32), n + 32);
  _reduce(r);
  _scalarbase(p, r);
  _pack(sm, p);
  for (i1 = 32; i1 < 64; i1++) {
    sm[i1] = sk[i1];
  }
  _hash(h, sm, n + 64);
  _reduce(h);
  for (i1 = 0; i1 < 64; i1++) {
    x[i1] = 0;
  }
  for (i1 = 0; i1 < 32; i1++) {
    x[i1] = r[i1];
  }
  for (i1 = 0; i1 < 32; i1++) {
    for (j = 0; j < 32; j++) {
      x[i1 + j] += h[i1] * d[j];
    }
  }
  Int32List mod = _modL(sm.sublist(32), x);
  sm.setRange(32, sm.length, mod);
  return mod;
}

int _rightTripleShift(int left, int right) {
  return (left >> right) & ~(-1 << (32 - right)); //JavaScript 32 bits
}

void _reduce(Int32List r) {
  final x = Int32List(64);
  int i1;
  for (i1 = 0; i1 < 64; i1++) {
    x[i1] = r[i1].floor();
  }
  for (i1 = 0; i1 < 64; i1++) {
    r[i1] = 0;
  }
  _modL(r, x);
}

Int32List _modL(Int32List r, Int32List x) {
  int carry, i1, j, k;
  for (i1 = 63; i1 >= 32; --i1) {
    carry = 0;
    j = i1 - 32;
    k = i1 - 12;
    for (; j < k; ++j) {
      x[j] += carry - 16 * x[i1] * _l[j - (i1 - 32)];
      carry = x[j] + 128 >> 8;
      x[j] -= carry * 256;
    }
    x[j] += carry;
    x[i1] = 0;
  }
  carry = 0;
  for (j = 0; j < 32; j++) {
    x[j] += carry - (x[31] >> 4) * _l[j];
    carry = x[j] >> 8;
    x[j] &= 255;
  }
  for (j = 0; j < 32; j++) {
    x[j] -= carry * _l[j];
  }
  for (i1 = 0; i1 < 32; i1++) {
    x[i1 + 1] += x[i1] >> 8;
    r[i1] = x[i1] & 255;
  }
  return r;
}

bool _isValidPublicPrefix(int prefix) {
  return (prefix == Prefix.Server ||
      prefix == Prefix.Operator ||
      prefix == Prefix.Cluster ||
      prefix == Prefix.Account ||
      prefix == Prefix.User);
}

Uint8List _decode(String src) {
  Uint8List raw;
  try {
    raw = base32.decode(src);
  } catch (ex) {
    throw NatsError.errorForCode(
        ErrorCode.InvalidEncoding, ArgumentError(ex.toString()));
  }
  final checkOffset = raw.length - 2;
  final dv = ByteData.sublistView(raw);
  final checksum = dv.getUint16(checkOffset, Endian.little);
  final payload = raw.sublist(0, checkOffset);
  if (!crc16.validate(payload, checksum)) {
    throw NatsError.errorForCode(ErrorCode.InvalidChecksum);
  }
  return payload;
}

List<int> _decodePrefix(Uint8List raw) {
  return [raw[0] & 248, (raw[0] & 7) << 5 | (raw[1] & 248) >> 3];
}

List<int> _encodePrefix(int kind, int role) {
  return [kind | role >> 5, (role & 31) << 3];
}

void _scalarbase(List<Int32List> p, Int32List s) {
  final q = [Int32List(16), Int32List(16), Int32List(16), Int32List(16)];
  _set25519(q[0], _x);
  _set25519(q[1], _y);
  _set25519(q[2], [1, ...Int32List(15)]);
  _m(q[3], _x, _y);
  _scalarmult(p, q, s);
}

void _set25519(Int32List r, List<int> a) {
  for (int i1 = 0; i1 < 16; i1++) {
    r[i1] = a[i1] | 0;
  }
}

void _sel25519(Int32List p, Int32List q, int b) {
  int t, c = ~(b - 1);
  for (int i1 = 0; i1 < 16; i1++) {
    t = c & (p[i1] ^ q[i1]);
    p[i1] ^= t;
    q[i1] ^= t;
  }
}

int _hash(final Int32List out, Int32List m, int n) {
  final hh = Int32List(8), hl = Int32List(8), x = Int32List(256);
  int i1, b = n;
  hh[0] = 1779033703;
  hh[1] = 3144134277;
  hh[2] = 1013904242;
  hh[3] = 2773480762;
  hh[4] = 1359893119;
  hh[5] = 2600822924;
  hh[6] = 528734635;
  hh[7] = 1541459225;
  hl[0] = 4089235720;
  hl[1] = 2227873595;
  hl[2] = 4271175723;
  hl[3] = 1595750129;
  hl[4] = 2917565137;
  hl[5] = 725511199;
  hl[6] = 4215389547;
  hl[7] = 327033209;
  _hashblocks(hh, hl, m, n);
  n %= 128;
  for (i1 = 0; i1 < n; i1++) {
    x[i1] = m[b - n + i1];
  }
  x[n] = 128;
  n = 256 - 128 * (n < 112 ? 1 : 0);
  x[n - 9] = 0;
  _ts64(x, n - 8, (b / 536870912).floor(), b << 3);
  _hashblocks(hh, hl, x, n);
  for (i1 = 0; i1 < 8; i1++) {
    _ts64(out, 8 * i1, hh[i1], hl[i1]);
  }
  return 0;
}

void _ts64(x, i1, h, l1) {
  x[i1] = h >> 24 & 255;
  x[i1 + 1] = h >> 16 & 255;
  x[i1 + 2] = h >> 8 & 255;
  x[i1 + 3] = h & 255;
  x[i1 + 4] = l1 >> 24 & 255;
  x[i1 + 5] = l1 >> 16 & 255;
  x[i1 + 6] = l1 >> 8 & 255;
  x[i1 + 7] = l1 & 255;
}

int _hashblocks(Int32List hh, Int32List hl, Int32List m, int n) {
  final wh = Int32List(16), wl = Int32List(16);
  int bh0,
      bh1,
      bh2,
      bh3,
      bh4,
      bh5,
      bh6,
      bh7,
      bl0,
      bl1,
      bl2,
      bl3,
      bl4,
      bl5,
      bl6,
      bl7,
      th,
      tl,
      i1,
      j,
      h,
      l1,
      a,
      b,
      c,
      d;
  int ah0 = hh[0],
      ah1 = hh[1],
      ah2 = hh[2],
      ah3 = hh[3],
      ah4 = hh[4],
      ah5 = hh[5],
      ah6 = hh[6],
      ah7 = hh[7],
      al0 = hl[0],
      al1 = hl[1],
      al2 = hl[2],
      al3 = hl[3],
      al4 = hl[4],
      al5 = hl[5],
      al6 = hl[6],
      al7 = hl[7];
  int pos = 0;
  while (n >= 128) {
    for (i1 = 0; i1 < 16; i1++) {
      j = 8 * i1 + pos;
      wh[i1] = m[j + 0] << 24 | m[j + 1] << 16 | m[j + 2] << 8 | m[j + 3];
      wl[i1] = m[j + 4] << 24 | m[j + 5] << 16 | m[j + 6] << 8 | m[j + 7];
    }
    for (i1 = 0; i1 < 80; i1++) {
      bh0 = ah0;
      bh1 = ah1;
      bh2 = ah2;
      bh3 = ah3;
      bh4 = ah4;
      bh5 = ah5;
      bh6 = ah6;
      bh7 = ah7;
      bl0 = al0;
      bl1 = al1;
      bl2 = al2;
      bl3 = al3;
      bl4 = al4;
      bl5 = al5;
      bl6 = al6;
      bl7 = al7;
      h = ah7;
      l1 = al7;
      a = l1 & 65535;
      b = _rightTripleShift(l1, 16);
      c = h & 65535;
      d = _rightTripleShift(h, 16);
      h = (_rightTripleShift(ah4, 14) | al4 << 32 - 14) ^
          (_rightTripleShift(ah4, 18) | al4 << 32 - 18) ^
          (_rightTripleShift(al4, 41 - 32) | ah4 << 32 - (41 - 32));
      l1 = (_rightTripleShift(al4, 14) | ah4 << 32 - 14) ^
          (_rightTripleShift(al4, 18) | ah4 << 32 - 18) ^
          (_rightTripleShift(ah4, 41 - 32) | al4 << 32 - (41 - 32));
      a += l1 & 65535;
      b += _rightTripleShift(l1, 16);
      c += h & 65535;
      d += _rightTripleShift(h, 16);
      h = ah4 & ah5 ^ ~ah4 & ah6;
      l1 = al4 & al5 ^ ~al4 & al6;
      a += l1 & 65535;
      b += _rightTripleShift(l1, 16);
      c += h & 65535;
      d += _rightTripleShift(h, 16);
      h = _k[i1 * 2];
      l1 = _k[i1 * 2 + 1];
      a += l1 & 65535;
      b += _rightTripleShift(l1, 16);
      c += h & 65535;
      d += _rightTripleShift(h, 16);
      h = wh[i1 % 16];
      l1 = wl[i1 % 16];
      a += l1 & 65535;
      b += _rightTripleShift(l1, 16);
      c += h & 65535;
      d += _rightTripleShift(h, 16);
      b += _rightTripleShift(a, 16);
      c += _rightTripleShift(b, 16);
      d += _rightTripleShift(c, 16);
      th = c & 65535 | d << 16;
      tl = a & 65535 | b << 16;
      h = th;
      l1 = tl;
      a = l1 & 65535;
      b = _rightTripleShift(l1, 16);
      c = h & 65535;
      d = _rightTripleShift(h, 16);
      h = (_rightTripleShift(ah0, 28) | al0 << 32 - 28) ^
          (_rightTripleShift(al0, 34 - 32) | ah0 << 32 - (34 - 32)) ^
          (_rightTripleShift(al0, 39 - 32) | ah0 << 32 - (39 - 32));
      l1 = (_rightTripleShift(al0, 28) | ah0 << 32 - 28) ^
          (_rightTripleShift(ah0, 34 - 32) | al0 << 32 - (34 - 32)) ^
          (_rightTripleShift(ah0, 39 - 32) | al0 << 32 - (39 - 32));
      a += l1 & 65535;
      b += _rightTripleShift(l1, 16);
      c += h & 65535;
      d += _rightTripleShift(h, 16);
      h = ah0 & ah1 ^ ah0 & ah2 ^ ah1 & ah2;
      l1 = al0 & al1 ^ al0 & al2 ^ al1 & al2;
      a += l1 & 65535;
      b += _rightTripleShift(l1, 16);
      c += h & 65535;
      d += _rightTripleShift(h, 16);
      b += _rightTripleShift(a, 16);
      c += _rightTripleShift(b, 16);
      d += _rightTripleShift(c, 16);
      bh7 = c & 65535 | d << 16;
      bl7 = a & 65535 | b << 16;
      h = bh3;
      l1 = bl3;
      a = l1 & 65535;
      b = _rightTripleShift(l1, 16);
      c = h & 65535;
      d = _rightTripleShift(h, 16);
      h = th;
      l1 = tl;
      a += l1 & 65535;
      b += _rightTripleShift(l1, 16);
      c += h & 65535;
      d += _rightTripleShift(h, 16);
      b += _rightTripleShift(a, 16);
      c += _rightTripleShift(b, 16);
      d += _rightTripleShift(c, 16);
      bh3 = c & 65535 | d << 16;
      bl3 = a & 65535 | b << 16;
      ah1 = bh0;
      ah2 = bh1;
      ah3 = bh2;
      ah4 = bh3;
      ah5 = bh4;
      ah6 = bh5;
      ah7 = bh6;
      ah0 = bh7;
      al1 = bl0;
      al2 = bl1;
      al3 = bl2;
      al4 = bl3;
      al5 = bl4;
      al6 = bl5;
      al7 = bl6;
      al0 = bl7;
      if (i1 % 16 == 15) {
        for (j = 0; j < 16; j++) {
          h = wh[j];
          l1 = wl[j];
          a = l1 & 65535;
          b = _rightTripleShift(l1, 16);
          c = h & 65535;
          d = _rightTripleShift(h, 16);
          h = wh[(j + 9) % 16];
          l1 = wl[(j + 9) % 16];
          a += l1 & 65535;
          b += _rightTripleShift(l1, 16);
          c += h & 65535;
          d += _rightTripleShift(h, 16);
          th = wh[(j + 1) % 16];
          tl = wl[(j + 1) % 16];
          h = (_rightTripleShift(th, 1) | tl << 32 - 1) ^
              (_rightTripleShift(th, 8) | tl << 32 - 8) ^
              _rightTripleShift(th, 7);
          l1 = (_rightTripleShift(tl, 1) | th << 32 - 1) ^
              (_rightTripleShift(tl, 8) | th << 32 - 8) ^
              (_rightTripleShift(tl, 7) | th << 32 - 7);
          a += l1 & 65535;
          b += _rightTripleShift(l1, 16);
          c += h & 65535;
          d += _rightTripleShift(h, 16);
          th = wh[(j + 14) % 16];
          tl = wl[(j + 14) % 16];
          h = (_rightTripleShift(th, 19) | tl << 32 - 19) ^
              (_rightTripleShift(tl, 61 - 32) | th << 32 - (61 - 32)) ^
              _rightTripleShift(th, 6);
          l1 = (_rightTripleShift(tl, 19) | th << 32 - 19) ^
              (_rightTripleShift(th, 61 - 32) | tl << 32 - (61 - 32)) ^
              (_rightTripleShift(tl, 6) | th << 32 - 6);
          a += l1 & 65535;
          b += _rightTripleShift(l1, 16);
          c += h & 65535;
          d += _rightTripleShift(h, 16);
          b += _rightTripleShift(a, 16);
          c += _rightTripleShift(b, 16);
          d += _rightTripleShift(c, 16);
          wh[j] = c & 65535 | d << 16;
          wl[j] = a & 65535 | b << 16;
        }
      }
    }
    h = ah0;
    l1 = al0;
    a = l1 & 65535;
    b = _rightTripleShift(l1, 16);
    c = h & 65535;
    d = _rightTripleShift(h, 16);
    h = hh[0];
    l1 = hl[0];
    a += l1 & 65535;
    b += _rightTripleShift(l1, 16);
    c += h & 65535;
    d += _rightTripleShift(h, 16);
    b += _rightTripleShift(a, 16);
    c += _rightTripleShift(b, 16);
    d += _rightTripleShift(c, 16);
    hh[0] = ah0 = c & 65535 | d << 16;
    hl[0] = al0 = a & 65535 | b << 16;
    h = ah1;
    l1 = al1;
    a = l1 & 65535;
    b = _rightTripleShift(l1, 16);
    c = h & 65535;
    d = _rightTripleShift(h, 16);
    h = hh[1];
    l1 = hl[1];
    a += l1 & 65535;
    b += _rightTripleShift(l1, 16);
    c += h & 65535;
    d += _rightTripleShift(h, 16);
    b += _rightTripleShift(a, 16);
    c += _rightTripleShift(b, 16);
    d += _rightTripleShift(c, 16);
    hh[1] = ah1 = c & 65535 | d << 16;
    hl[1] = al1 = a & 65535 | b << 16;
    h = ah2;
    l1 = al2;
    a = l1 & 65535;
    b = _rightTripleShift(l1, 16);
    c = h & 65535;
    d = _rightTripleShift(h, 16);
    h = hh[2];
    l1 = hl[2];
    a += l1 & 65535;
    b += _rightTripleShift(l1, 16);
    c += h & 65535;
    d += _rightTripleShift(h, 16);
    b += _rightTripleShift(a, 16);
    c += _rightTripleShift(b, 16);
    d += _rightTripleShift(c, 16);
    hh[2] = ah2 = c & 65535 | d << 16;
    hl[2] = al2 = a & 65535 | b << 16;
    h = ah3;
    l1 = al3;
    a = l1 & 65535;
    b = _rightTripleShift(l1, 16);
    c = h & 65535;
    d = _rightTripleShift(h, 16);
    h = hh[3];
    l1 = hl[3];
    a += l1 & 65535;
    b += _rightTripleShift(l1, 16);
    c += h & 65535;
    d += _rightTripleShift(h, 16);
    b += _rightTripleShift(a, 16);
    c += _rightTripleShift(b, 16);
    d += _rightTripleShift(c, 16);
    hh[3] = ah3 = c & 65535 | d << 16;
    hl[3] = al3 = a & 65535 | b << 16;
    h = ah4;
    l1 = al4;
    a = l1 & 65535;
    b = _rightTripleShift(l1, 16);
    c = h & 65535;
    d = _rightTripleShift(h, 16);
    h = hh[4];
    l1 = hl[4];
    a += l1 & 65535;
    b += _rightTripleShift(l1, 16);
    c += h & 65535;
    d += _rightTripleShift(h, 16);
    b += _rightTripleShift(a, 16);
    c += _rightTripleShift(b, 16);
    d += _rightTripleShift(c, 16);
    hh[4] = ah4 = c & 65535 | d << 16;
    hl[4] = al4 = a & 65535 | b << 16;
    h = ah5;
    l1 = al5;
    a = l1 & 65535;
    b = _rightTripleShift(l1, 16);
    c = h & 65535;
    d = _rightTripleShift(h, 16);
    h = hh[5];
    l1 = hl[5];
    a += l1 & 65535;
    b += _rightTripleShift(l1, 16);
    c += h & 65535;
    d += _rightTripleShift(h, 16);
    b += _rightTripleShift(a, 16);
    c += _rightTripleShift(b, 16);
    d += _rightTripleShift(c, 16);
    hh[5] = ah5 = c & 65535 | d << 16;
    hl[5] = al5 = a & 65535 | b << 16;
    h = ah6;
    l1 = al6;
    a = l1 & 65535;
    b = _rightTripleShift(l1, 16);
    c = h & 65535;
    d = _rightTripleShift(h, 16);
    h = hh[6];
    l1 = hl[6];
    a += l1 & 65535;
    b += _rightTripleShift(l1, 16);
    c += h & 65535;
    d += _rightTripleShift(h, 16);
    b += _rightTripleShift(a, 16);
    c += _rightTripleShift(b, 16);
    d += _rightTripleShift(c, 16);
    hh[6] = ah6 = c & 65535 | d << 16;
    hl[6] = al6 = a & 65535 | b << 16;
    h = ah7;
    l1 = al7;
    a = l1 & 65535;
    b = _rightTripleShift(l1, 16);
    c = h & 65535;
    d = _rightTripleShift(h, 16);
    h = hh[7];
    l1 = hl[7];
    a += l1 & 65535;
    b += _rightTripleShift(l1, 16);
    c += h & 65535;
    d += _rightTripleShift(h, 16);
    b += _rightTripleShift(a, 16);
    c += _rightTripleShift(b, 16);
    d += _rightTripleShift(c, 16);
    hh[7] = ah7 = c & 65535 | d << 16;
    hl[7] = al7 = a & 65535 | b << 16;
    pos += 128;
    n -= 128;
  }
  return n;
}

void _z(Int32List o, Int32List a, Int32List b) {
  for (int i = 0; i < 16; i++) {
    o[i] = a[i] - b[i];
  }
}

void _a(Int32List o, Int32List a, Int32List b) {
  for (int i = 0; i < 16; i++) {
    o[i] = a[i] + b[i];
  }
}

void _m(Int32List o, List<int> a, List<int> b) {
  int v,
      c,
      t0 = 0,
      t1 = 0,
      t2 = 0,
      t3 = 0,
      t4 = 0,
      t5 = 0,
      t6 = 0,
      t7 = 0,
      t8 = 0,
      t9 = 0,
      t10 = 0,
      t11 = 0,
      t12 = 0,
      t13 = 0,
      t14 = 0,
      t15 = 0,
      t16 = 0,
      t17 = 0,
      t18 = 0,
      t19 = 0,
      t20 = 0,
      t21 = 0,
      t22 = 0,
      t23 = 0,
      t24 = 0,
      t25 = 0,
      t26 = 0,
      t27 = 0,
      t28 = 0,
      t29 = 0,
      t30 = 0;
  int b0 = b[0],
      b1 = b[1],
      b2 = b[2],
      b3 = b[3],
      b4 = b[4],
      b5 = b[5],
      b6 = b[6],
      b7 = b[7],
      b8 = b[8],
      b9 = b[9],
      b10 = b[10],
      b11 = b[11],
      b12 = b[12],
      b13 = b[13],
      b14 = b[14],
      b15 = b[15];
  v = a[0];
  t0 += v * b0;
  t1 += v * b1;
  t2 += v * b2;
  t3 += v * b3;
  t4 += v * b4;
  t5 += v * b5;
  t6 += v * b6;
  t7 += v * b7;
  t8 += v * b8;
  t9 += v * b9;
  t10 += v * b10;
  t11 += v * b11;
  t12 += v * b12;
  t13 += v * b13;
  t14 += v * b14;
  t15 += v * b15;
  v = a[1];
  t1 += v * b0;
  t2 += v * b1;
  t3 += v * b2;
  t4 += v * b3;
  t5 += v * b4;
  t6 += v * b5;
  t7 += v * b6;
  t8 += v * b7;
  t9 += v * b8;
  t10 += v * b9;
  t11 += v * b10;
  t12 += v * b11;
  t13 += v * b12;
  t14 += v * b13;
  t15 += v * b14;
  t16 += v * b15;
  v = a[2];
  t2 += v * b0;
  t3 += v * b1;
  t4 += v * b2;
  t5 += v * b3;
  t6 += v * b4;
  t7 += v * b5;
  t8 += v * b6;
  t9 += v * b7;
  t10 += v * b8;
  t11 += v * b9;
  t12 += v * b10;
  t13 += v * b11;
  t14 += v * b12;
  t15 += v * b13;
  t16 += v * b14;
  t17 += v * b15;
  v = a[3];
  t3 += v * b0;
  t4 += v * b1;
  t5 += v * b2;
  t6 += v * b3;
  t7 += v * b4;
  t8 += v * b5;
  t9 += v * b6;
  t10 += v * b7;
  t11 += v * b8;
  t12 += v * b9;
  t13 += v * b10;
  t14 += v * b11;
  t15 += v * b12;
  t16 += v * b13;
  t17 += v * b14;
  t18 += v * b15;
  v = a[4];
  t4 += v * b0;
  t5 += v * b1;
  t6 += v * b2;
  t7 += v * b3;
  t8 += v * b4;
  t9 += v * b5;
  t10 += v * b6;
  t11 += v * b7;
  t12 += v * b8;
  t13 += v * b9;
  t14 += v * b10;
  t15 += v * b11;
  t16 += v * b12;
  t17 += v * b13;
  t18 += v * b14;
  t19 += v * b15;
  v = a[5];
  t5 += v * b0;
  t6 += v * b1;
  t7 += v * b2;
  t8 += v * b3;
  t9 += v * b4;
  t10 += v * b5;
  t11 += v * b6;
  t12 += v * b7;
  t13 += v * b8;
  t14 += v * b9;
  t15 += v * b10;
  t16 += v * b11;
  t17 += v * b12;
  t18 += v * b13;
  t19 += v * b14;
  t20 += v * b15;
  v = a[6];
  t6 += v * b0;
  t7 += v * b1;
  t8 += v * b2;
  t9 += v * b3;
  t10 += v * b4;
  t11 += v * b5;
  t12 += v * b6;
  t13 += v * b7;
  t14 += v * b8;
  t15 += v * b9;
  t16 += v * b10;
  t17 += v * b11;
  t18 += v * b12;
  t19 += v * b13;
  t20 += v * b14;
  t21 += v * b15;
  v = a[7];
  t7 += v * b0;
  t8 += v * b1;
  t9 += v * b2;
  t10 += v * b3;
  t11 += v * b4;
  t12 += v * b5;
  t13 += v * b6;
  t14 += v * b7;
  t15 += v * b8;
  t16 += v * b9;
  t17 += v * b10;
  t18 += v * b11;
  t19 += v * b12;
  t20 += v * b13;
  t21 += v * b14;
  t22 += v * b15;
  v = a[8];
  t8 += v * b0;
  t9 += v * b1;
  t10 += v * b2;
  t11 += v * b3;
  t12 += v * b4;
  t13 += v * b5;
  t14 += v * b6;
  t15 += v * b7;
  t16 += v * b8;
  t17 += v * b9;
  t18 += v * b10;
  t19 += v * b11;
  t20 += v * b12;
  t21 += v * b13;
  t22 += v * b14;
  t23 += v * b15;
  v = a[9];
  t9 += v * b0;
  t10 += v * b1;
  t11 += v * b2;
  t12 += v * b3;
  t13 += v * b4;
  t14 += v * b5;
  t15 += v * b6;
  t16 += v * b7;
  t17 += v * b8;
  t18 += v * b9;
  t19 += v * b10;
  t20 += v * b11;
  t21 += v * b12;
  t22 += v * b13;
  t23 += v * b14;
  t24 += v * b15;
  v = a[10];
  t10 += v * b0;
  t11 += v * b1;
  t12 += v * b2;
  t13 += v * b3;
  t14 += v * b4;
  t15 += v * b5;
  t16 += v * b6;
  t17 += v * b7;
  t18 += v * b8;
  t19 += v * b9;
  t20 += v * b10;
  t21 += v * b11;
  t22 += v * b12;
  t23 += v * b13;
  t24 += v * b14;
  t25 += v * b15;
  v = a[11];
  t11 += v * b0;
  t12 += v * b1;
  t13 += v * b2;
  t14 += v * b3;
  t15 += v * b4;
  t16 += v * b5;
  t17 += v * b6;
  t18 += v * b7;
  t19 += v * b8;
  t20 += v * b9;
  t21 += v * b10;
  t22 += v * b11;
  t23 += v * b12;
  t24 += v * b13;
  t25 += v * b14;
  t26 += v * b15;
  v = a[12];
  t12 += v * b0;
  t13 += v * b1;
  t14 += v * b2;
  t15 += v * b3;
  t16 += v * b4;
  t17 += v * b5;
  t18 += v * b6;
  t19 += v * b7;
  t20 += v * b8;
  t21 += v * b9;
  t22 += v * b10;
  t23 += v * b11;
  t24 += v * b12;
  t25 += v * b13;
  t26 += v * b14;
  t27 += v * b15;
  v = a[13];
  t13 += v * b0;
  t14 += v * b1;
  t15 += v * b2;
  t16 += v * b3;
  t17 += v * b4;
  t18 += v * b5;
  t19 += v * b6;
  t20 += v * b7;
  t21 += v * b8;
  t22 += v * b9;
  t23 += v * b10;
  t24 += v * b11;
  t25 += v * b12;
  t26 += v * b13;
  t27 += v * b14;
  t28 += v * b15;
  v = a[14];
  t14 += v * b0;
  t15 += v * b1;
  t16 += v * b2;
  t17 += v * b3;
  t18 += v * b4;
  t19 += v * b5;
  t20 += v * b6;
  t21 += v * b7;
  t22 += v * b8;
  t23 += v * b9;
  t24 += v * b10;
  t25 += v * b11;
  t26 += v * b12;
  t27 += v * b13;
  t28 += v * b14;
  t29 += v * b15;
  v = a[15];
  t15 += v * b0;
  t16 += v * b1;
  t17 += v * b2;
  t18 += v * b3;
  t19 += v * b4;
  t20 += v * b5;
  t21 += v * b6;
  t22 += v * b7;
  t23 += v * b8;
  t24 += v * b9;
  t25 += v * b10;
  t26 += v * b11;
  t27 += v * b12;
  t28 += v * b13;
  t29 += v * b14;
  t30 += v * b15;
  t0 += 38 * t16;
  t1 += 38 * t17;
  t2 += 38 * t18;
  t3 += 38 * t19;
  t4 += 38 * t20;
  t5 += 38 * t21;
  t6 += 38 * t22;
  t7 += 38 * t23;
  t8 += 38 * t24;
  t9 += 38 * t25;
  t10 += 38 * t26;
  t11 += 38 * t27;
  t12 += 38 * t28;
  t13 += 38 * t29;
  t14 += 38 * t30;
  c = 1;
  v = t0 + c + 65535;
  c = (v / 65536).floor();
  t0 = v - c * 65536;
  v = t1 + c + 65535;
  c = (v / 65536).floor();
  t1 = v - c * 65536;
  v = t2 + c + 65535;
  c = (v / 65536).floor();
  t2 = v - c * 65536;
  v = t3 + c + 65535;
  c = (v / 65536).floor();
  t3 = v - c * 65536;
  v = t4 + c + 65535;
  c = (v / 65536).floor();
  t4 = v - c * 65536;
  v = t5 + c + 65535;
  c = (v / 65536).floor();
  t5 = v - c * 65536;
  v = t6 + c + 65535;
  c = (v / 65536).floor();
  t6 = v - c * 65536;
  v = t7 + c + 65535;
  c = (v / 65536).floor();
  t7 = v - c * 65536;
  v = t8 + c + 65535;
  c = (v / 65536).floor();
  t8 = v - c * 65536;
  v = t9 + c + 65535;
  c = (v / 65536).floor();
  t9 = v - c * 65536;
  v = t10 + c + 65535;
  c = (v / 65536).floor();
  t10 = v - c * 65536;
  v = t11 + c + 65535;
  c = (v / 65536).floor();
  t11 = v - c * 65536;
  v = t12 + c + 65535;
  c = (v / 65536).floor();
  t12 = v - c * 65536;
  v = t13 + c + 65535;
  c = (v / 65536).floor();
  t13 = v - c * 65536;
  v = t14 + c + 65535;
  c = (v / 65536).floor();
  t14 = v - c * 65536;
  v = t15 + c + 65535;
  c = (v / 65536).floor();
  t15 = v - c * 65536;
  t0 += c - 1 + 37 * (c - 1);
  c = 1;
  v = t0 + c + 65535;
  c = (v / 65536).floor();
  t0 = v - c * 65536;
  v = t1 + c + 65535;
  c = (v / 65536).floor();
  t1 = v - c * 65536;
  v = t2 + c + 65535;
  c = (v / 65536).floor();
  t2 = v - c * 65536;
  v = t3 + c + 65535;
  c = (v / 65536).floor();
  t3 = v - c * 65536;
  v = t4 + c + 65535;
  c = (v / 65536).floor();
  t4 = v - c * 65536;
  v = t5 + c + 65535;
  c = (v / 65536).floor();
  t5 = v - c * 65536;
  v = t6 + c + 65535;
  c = (v / 65536).floor();
  t6 = v - c * 65536;
  v = t7 + c + 65535;
  c = (v / 65536).floor();
  t7 = v - c * 65536;
  v = t8 + c + 65535;
  c = (v / 65536).floor();
  t8 = v - c * 65536;
  v = t9 + c + 65535;
  c = (v / 65536).floor();
  t9 = v - c * 65536;
  v = t10 + c + 65535;
  c = (v / 65536).floor();
  t10 = v - c * 65536;
  v = t11 + c + 65535;
  c = (v / 65536).floor();
  t11 = v - c * 65536;
  v = t12 + c + 65535;
  c = (v / 65536).floor();
  t12 = v - c * 65536;
  v = t13 + c + 65535;
  c = (v / 65536).floor();
  t13 = v - c * 65536;
  v = t14 + c + 65535;
  c = (v / 65536).floor();
  t14 = v - c * 65536;
  v = t15 + c + 65535;
  c = (v / 65536).floor();
  t15 = v - c * 65536;
  t0 += c - 1 + 37 * (c - 1);
  o[0] = t0;
  o[1] = t1;
  o[2] = t2;
  o[3] = t3;
  o[4] = t4;
  o[5] = t5;
  o[6] = t6;
  o[7] = t7;
  o[8] = t8;
  o[9] = t9;
  o[10] = t10;
  o[11] = t11;
  o[12] = t12;
  o[13] = t13;
  o[14] = t14;
  o[15] = t15;
}

void _scalarmult(List<Int32List> p, List<Int32List> q, Int32List s) {
  int i1;
  _set25519(p[0], [0, ...Int32List(15)]);
  _set25519(p[1], [1, ...Int32List(15)]);
  _set25519(p[2], [1, ...Int32List(15)]);
  _set25519(p[3], [0, ...Int32List(15)]);
  for (i1 = 255; i1 >= 0; --i1) {
    int b = s[(i1 / 8).floor()] >> (i1 & 7) & 1;
    _cswap(p, q, b);
    _add(q, p);
    _add(p, p);
    _cswap(p, q, b);
  }
}

void _cswap(List<Int32List> p, List<Int32List> q, int b) {
  for (int i1 = 0; i1 < 4; i1++) {
    _sel25519(p[i1], q[i1], b);
  }
}

void _add(List<Int32List> p, List<Int32List> q) {
  final a = Int32List(16),
      b = Int32List(16),
      c = Int32List(16),
      d = Int32List(16),
      e = Int32List(16),
      f = Int32List(16),
      g = Int32List(16),
      h = Int32List(16),
      t = Int32List(16);
  _z(a, p[1], p[0]);
  _z(t, q[1], q[0]);
  _m(a, a, t);
  _a(b, p[0], p[1]);
  _a(t, q[0], q[1]);
  _m(b, b, t);
  _m(c, p[3], q[3]);
  _m(c, c, _d);
  _m(d, p[2], q[2]);
  _a(d, d, d);
  _z(e, b, a);
  _z(f, d, c);
  _a(g, d, c);
  _a(h, b, a);
  _m(p[0], e, f);
  _m(p[1], h, g);
  _m(p[2], g, f);
  _m(p[3], e, h);
}

void _pack(Int32List r, List<Int32List> p) {
  final tx = Int32List(16), ty = Int32List(16), zi = Int32List(16);
  _inv25519(zi, p[2]);
  _m(tx, p[0], zi);
  _m(ty, p[1], zi);
  _pack25519(r, ty);
  r[31] ^= _par25519(tx) << 7;
}

int _par25519(a) {
  final d = Int32List(32);
  _pack25519(d, a);
  return d[0] & 1;
}

void _inv25519(Int32List o, Int32List i1) {
  final c = Int32List(16);
  int a;
  for (a = 0; a < 16; a++) {
    c[a] = i1[a];
  }
  for (a = 253; a >= 0; a--) {
    _m(c, c, c);
    if (a != 2 && a != 4) _m(c, c, i1);
  }
  for (a = 0; a < 16; a++) {
    o[a] = c[a];
  }
}

void _pack25519(Int32List o, Int32List n) {
  final m = Int32List(16), t = Int32List(16);
  int i1, j, b;
  for (i1 = 0; i1 < 16; i1++) {
    t[i1] = n[i1];
  }
  _car25519(t);
  _car25519(t);
  _car25519(t);
  for (j = 0; j < 2; j++) {
    m[0] = t[0] - 65517;
    for (i1 = 1; i1 < 15; i1++) {
      m[i1] = t[i1] - 65535 - (m[i1 - 1] >> 16 & 1);
      m[i1 - 1] &= 65535;
    }
    m[15] = t[15] - 32767 - (m[14] >> 16 & 1);
    b = m[15] >> 16 & 1;
    m[14] &= 65535;
    _sel25519(t, m, 1 - b);
  }
  for (i1 = 0; i1 < 16; i1++) {
    o[2 * i1] = t[i1] & 255;
    o[2 * i1 + 1] = t[i1] >> 8;
  }
}

void _car25519(Int32List o) {
  int i1, v, c = 1;
  for (i1 = 0; i1 < 16; i1++) {
    v = o[i1] + c + 65535;
    c = (v / 65536).floor();
    o[i1] = v - c * 65536;
  }
  o[0] += c - 1 + 37 * (c - 1);
}

const _k = [
  1116352408,
  3609767458,
  1899447441,
  602891725,
  3049323471,
  3964484399,
  3921009573,
  2173295548,
  961987163,
  4081628472,
  1508970993,
  3053834265,
  2453635748,
  2937671579,
  2870763221,
  3664609560,
  3624381080,
  2734883394,
  310598401,
  1164996542,
  607225278,
  1323610764,
  1426881987,
  3590304994,
  1925078388,
  4068182383,
  2162078206,
  991336113,
  2614888103,
  633803317,
  3248222580,
  3479774868,
  3835390401,
  2666613458,
  4022224774,
  944711139,
  264347078,
  2341262773,
  604807628,
  2007800933,
  770255983,
  1495990901,
  1249150122,
  1856431235,
  1555081692,
  3175218132,
  1996064986,
  2198950837,
  2554220882,
  3999719339,
  2821834349,
  766784016,
  2952996808,
  2566594879,
  3210313671,
  3203337956,
  3336571891,
  1034457026,
  3584528711,
  2466948901,
  113926993,
  3758326383,
  338241895,
  168717936,
  666307205,
  1188179964,
  773529912,
  1546045734,
  1294757372,
  1522805485,
  1396182291,
  2643833823,
  1695183700,
  2343527390,
  1986661051,
  1014477480,
  2177026350,
  1206759142,
  2456956037,
  344077627,
  2730485921,
  1290863460,
  2820302411,
  3158454273,
  3259730800,
  3505952657,
  3345764771,
  106217008,
  3516065817,
  3606008344,
  3600352804,
  1432725776,
  4094571909,
  1467031594,
  275423344,
  851169720,
  430227734,
  3100823752,
  506948616,
  1363258195,
  659060556,
  3750685593,
  883997877,
  3785050280,
  958139571,
  3318307427,
  1322822218,
  3812723403,
  1537002063,
  2003034995,
  1747873779,
  3602036899,
  1955562222,
  1575990012,
  2024104815,
  1125592928,
  2227730452,
  2716904306,
  2361852424,
  442776044,
  2428436474,
  593698344,
  2756734187,
  3733110249,
  3204031479,
  2999351573,
  3329325298,
  3815920427,
  3391569614,
  3928383900,
  3515267271,
  566280711,
  3940187606,
  3454069534,
  4118630271,
  4000239992,
  116418474,
  1914138554,
  174292421,
  2731055270,
  289380356,
  3203993006,
  460393269,
  320620315,
  685471733,
  587496836,
  852142971,
  1086792851,
  1017036298,
  365543100,
  1126000580,
  2618297676,
  1288033470,
  3409855158,
  1501505948,
  4234509866,
  1607167915,
  987167468,
  1816402316,
  1246189591
];

const _x = [
  54554,
  36645,
  11616,
  51542,
  42930,
  38181,
  51040,
  26924,
  56412,
  64982,
  57905,
  49316,
  21502,
  52590,
  14035,
  8553
];

const _y = [
  26200,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214,
  26214
];

const _d = [
  61785,
  9906,
  39828,
  60374,
  45398,
  33411,
  5274,
  224,
  53552,
  61171,
  33010,
  6542,
  64743,
  22239,
  55772,
  9222
];

const _l = [
  237,
  211,
  245,
  92,
  26,
  99,
  18,
  88,
  214,
  156,
  247,
  162,
  222,
  249,
  222,
  20,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  16
];
