import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Mega crypto, ported from the megajs reference implementation
/// (qgustavor/mega, lib/crypto/*, MIT).
///
/// Mega public-folder files are encrypted client-side:
/// - every node key is AES-ECB encrypted with the folder (link) key
///   (verified against the raw `f` response and the megajs source)
/// - node attributes are AES-CBC encrypted (zero IV) with the node's key
/// - file content is AES-CTR encrypted; the 32-byte file key holds
///   [aes key (16) | nonce (8) | meta MAC (8)] after "unmerging".

/// Base64url decode (Mega omits padding).
Uint8List b64UrlDecode(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return base64.decode(t);
}

/// Base64url encode without padding.
String b64UrlEncode(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _processBlocks(BlockCipher cipher, Uint8List data) {
  assert(data.length % 16 == 0, 'ECB/CBC input must be a multiple of 16');
  final out = Uint8List(data.length);
  for (var off = 0; off < data.length; off += 16) {
    cipher.processBlock(data, off, out, off);
  }
  return out;
}

/// AES-128-ECB decrypt, no padding. Used for node keys.
Uint8List aesEcbDecrypt(Uint8List key, Uint8List data) {
  final cipher = ECBBlockCipher(AESEngine())
    ..init(false, KeyParameter(key));
  return _processBlocks(cipher, data);
}

/// AES-128-CBC decrypt with a zero IV, no padding. Used for attributes.
Uint8List aesCbcDecrypt(Uint8List key, Uint8List data) {
  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      false,
      ParametersWithIV(KeyParameter(key), Uint8List(16)),
    );
  return _processBlocks(cipher, data);
}

/// Undo Mega's key/MAC merge: storedKey[i] = realKey[i] ^ storedKey[16 + i]
/// for i in 0..15. Returns a 32-byte buffer; bytes 0-15 are the AES key.
Uint8List unmergeKeyMac(Uint8List key) {
  final out = Uint8List(32);
  out.setAll(0, key);
  for (var i = 0; i < 16; i++) {
    out[i] ^= out[16 + i];
  }
  return out;
}

/// AES key (first 16 bytes) of a file node key (32 bytes, merged) or a
/// folder node key (16 bytes, used as-is).
Uint8List nodeAesKey(Uint8List key) {
  if (key.length == 16) return key;
  return unmergeKeyMac(key).sublist(0, 16);
}

/// Decrypt a node's attributes. Returns the attribute JSON map, or null if
/// the data does not decrypt to a `MEGA{...}` attribute block.
Map<String, dynamic>? decryptAttributes(Uint8List key, String attrB64) {
  try {
    final raw = b64UrlDecode(attrB64);
    final plain = aesCbcDecrypt(nodeAesKey(key), raw);
    var end = 0;
    while (end < plain.length && plain[end] != 0) {
      end++;
    }
    final text = utf8.decode(plain.sublist(0, end));
    if (!text.startsWith('MEGA{"')) return null;
    return jsonDecode(text.substring(4)) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Uint8List _incrementIv(Uint8List iv, int blocks) {
  final out = Uint8List.fromList(iv);
  var carry = blocks;
  var i = 15;
  while (carry > 0 && i >= 0) {
    final sum = out[i] + carry;
    out[i] = sum & 0xff;
    carry = sum >> 8;
    i--;
  }
  return out;
}

/// AES-128-CTR decrypt of Mega file content.
///
/// [key] is the 32-byte merged file key; bytes 16-23 are the nonce.
/// [startByte] is the plaintext offset the ciphertext starts at; it is
/// rounded down to a 16-byte boundary for the counter, and the leading
/// [startByte - aligned] bytes are skipped. The counter is the 16-byte IV
/// (nonce + 8 zero bytes) incremented by aligned/16 as a big-endian integer.
Uint8List aesCtrDecrypt(
  Uint8List key,
  Uint8List ciphertext,
  int startByte,
) {
  final aesKey = nodeAesKey(key);
  final nonce = key.sublist(16, 24);
  final aligned = startByte - (startByte % 16);
  final iv = Uint8List(16);
  iv.setRange(0, 8, nonce);
  final iv2 = _incrementIv(iv, aligned ~/ 16);
  final cipher = CTRStreamCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(aesKey), iv2));
  final out = cipher.process(ciphertext);
  final skip = startByte - aligned;
  return skip == 0 ? out : out.sublist(skip);
}
