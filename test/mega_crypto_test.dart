import 'dart:typed_data';

import 'package:course_vault/mega/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hexOf(Uint8List b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

/// The 32-byte MERGED Mega file key for the CTR vectors: unmerging it
/// yields AES key 00112233445566778899aabbccddeeff and nonce
/// 0102030405060708. (Mega stores file keys merged: stored[i] =
/// realKey[i] ^ stored[16 + i].)
const _mergedKeyHex =
    '011321374153617f8899aabbccddeeff01020304050607080000000000000000';

void main() {
  group('Mega crypto (vectors generated with Node crypto, same scheme)', () {
    test('AES-CTR decrypt matches Node output', () {
      const plainHex =
          '436f757273655661756c74204d65676120435452207465737420766563746f722030313233343536373839414243444546';
      const cipherHex =
          'e214f34f73a35b35105b8d737b5e24ba3027f882f9e9003e0e814c03d608a20fb78ffae36ce7d1e9174faeff6b0262f765';
      final out = aesCtrDecrypt(hex(_mergedKeyHex), hex(cipherHex), 0);
      expect(hexOf(out), plainHex);
    });

    test('AES-CTR decrypt with a 32-byte start offset', () {
      // The 49-byte plaintext has a space at byte 32, so bytes 32..48 are
      // " 0123456789ABCDEF" (17 bytes) — the Node vector encrypts
      // plain.subarray(32), all 17 bytes.
      const plainTailHex = '2030313233343536373839414243444546';
      const cipherHex = 'b78ffae36ce7d1e9174faeff6b0262f765';
      final out = aesCtrDecrypt(hex(_mergedKeyHex), hex(cipherHex), 32);
      expect(hexOf(out), plainTailHex);
    });

    test('AES-CTR decrypt with a non-block-aligned start', () {
      const cipherHex =
          'e214f34f73a35b35105b8d737b5e24ba3027f882f9e9003e0e814c03d608a20fb78ffae36ce7d1e9174faeff6b0262f765';
      const plainHex =
          '436f757273655661756c74204d65676120435452207465737420766563746f722030313233343536373839414243444546';
      // Start at byte 5: the result must equal plaintext[5:].
      final out = aesCtrDecrypt(hex(_mergedKeyHex), hex(cipherHex), 5);
      expect(hexOf(out), plainHex.substring(10));
    });

    test('AES-ECB decrypt matches Node output', () {
      const folderKeyHex = '0f1e2d3c4b5a69788796a5b4c3d2e1f0';
      const plainHex =
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
      const cipherHex =
          'afcc40c970e93652520f0157597fb49eafcc40c970e93652520f0157597fb49e';
      final out = aesEcbDecrypt(hex(folderKeyHex), hex(cipherHex));
      expect(hexOf(out), plainHex);
    });

    test('AES-CBC decrypt of attributes matches Node output', () {
      const keyHex = '00112233445566778899aabbccddeeff';
      const plainHex =
          '4d4547417b226e223a2254657374204c6573736f6e227d000000000000000000';
      const cipherHex =
          '25e049d60ab260093f2a1b6b42fc2de77e29fbb7060243ffba047b13e3c9da5d';
      final out = aesCbcDecrypt(hex(keyHex), hex(cipherHex));
      expect(hexOf(out), plainHex);
    });

    test('decryptAttributes parses a MEGA attribute block', () {
      const keyHex = '00112233445566778899aabbccddeeff';
      // CBC ciphertext of 'MEGA{"n":"Test Lesson"}' padded with NULs.
      const cipherB64 = 'JeBJ1gqyYAk/KhtrQvwt534p+7cGAkP/ugR7E+PJ2l0=';
      final attrs = decryptAttributes(hex(keyHex), cipherB64);
      expect(attrs, isNotNull);
      expect(attrs!['n'], 'Test Lesson');
    });

    test('base64url helpers round-trip without padding', () {
      final bytes = Uint8List.fromList(List.generate(16, (i) => i * 17));
      final encoded = b64UrlEncode(bytes);
      expect(encoded.contains('='), isFalse);
      expect(b64UrlDecode(encoded), bytes);
      // Mega keys use - and _ instead of + and /.
      expect(b64UrlDecode('l_VpZ-zplh5xYEm8RN7c2g').length, 16);
    });
  });
}
