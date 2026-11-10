@Timeout(Duration(minutes: 5))
library;

import 'package:course_vault/mega/api.dart';
import 'package:course_vault/mega/catalogue.dart';
import 'package:course_vault/mega/crypto.dart';
import 'package:course_vault/mega/link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration test against the REAL Mega folder link.
/// Needs network. Run with: flutter test test/mega_integration_test.dart
void main() {
  const url =
      'https://mega.nz/folder/ytZkzaSC#l_VpZ-zplh5xYEm8RN7c2g/folder/qsoFTCBb';

  test('real Mega link lists the course catalogue', () async {
    final api = MegaApi();
    try {
      final courses = await loadCatalogueFromLink(api, url);
      expect(courses.length, 1);
      final course = courses.first;
      expect(course.name, 'Creative Strategy Program');
      expect(course.modules.length, 9);
      final videos =
          course.lessons.where((l) => l.hasVideo).length;
      expect(videos, 80);
    } finally {
      api.close();
    }
  });

  test('real Mega video decrypts to a valid MP4 header', () async {
    final api = MegaApi();
    try {
      final courses = await loadCatalogueFromLink(api, url);
      final lesson = courses.first.lessons
          .firstWhere((l) => l.hasVideo);
      final video = lesson.video!;
      final link = parseMegaLink(url);
      final dl = await api.downloadUrl(link.rootHandle, video.handle);
      // First 64 KB of ciphertext, decrypted from byte 0.
      final cipher = await api.fetchRange(dl.url, 0, 65535);
      final plain = aesCtrDecrypt(video.key!, cipher, 0);
      // MP4 files start with a 4-byte size then 'ftyp'.
      final ftyp = String.fromCharCodes(plain.sublist(4, 8));
      expect(ftyp, 'ftyp');
    } finally {
      api.close();
    }
  });
}
