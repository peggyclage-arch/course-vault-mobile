import 'package:course_vault/mega/link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMegaLink', () {
    test('parses a folder link with a subfolder', () {
      final link = parseMegaLink(
        'https://mega.nz/folder/ytZkzaSC#l_VpZ-zplh5xYEm8RN7c2g/folder/qsoFTCBb',
      );
      expect(link.rootHandle, 'ytZkzaSC');
      expect(link.key, 'l_VpZ-zplh5xYEm8RN7c2g');
      expect(link.subfolderHandle, 'qsoFTCBb');
      expect(
        link.cleanUrl,
        'https://mega.nz/folder/ytZkzaSC#l_VpZ-zplh5xYEm8RN7c2g',
      );
    });

    test('parses a folder link without a subfolder', () {
      final link = parseMegaLink(
        'https://mega.nz/folder/abcDEF123#kEy_ABC-1234567890',
      );
      expect(link.rootHandle, 'abcDEF123');
      expect(link.subfolderHandle, isNull);
    });

    test('rejects non-Mega URLs', () {
      expect(
        () => parseMegaLink('https://example.com/folder/abc#key'),
        throwsFormatException,
      );
      expect(() => parseMegaLink('not a link'), throwsFormatException);
      expect(
        () => parseMegaLink('https://mega.nz/file/abc#key'),
        throwsFormatException,
      );
    });
  });
}
