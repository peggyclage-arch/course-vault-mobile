import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'catalogue.dart';
import 'crypto.dart';

/// Download a whole file from Mega, decrypt it, and return the plaintext.
/// For small files only (notes, subtitles, resources) — videos stream
/// through [VideoProxy] instead.
Future<Uint8List> downloadFile(
  MegaApi api,
  String rootHandle,
  MegaNode file,
) async {
  final key = file.key;
  if (key == null || key.length != 32) {
    throw const MegaApiException('File has no decryption key.');
  }
  if (file.size == 0) return Uint8List(0);
  final url = await api.downloadUrl(rootHandle, file.handle);
  final cipher = await api.fetchRange(url.url, 0, file.size - 1);
  return aesCtrDecrypt(key, cipher, 0);
}

/// Download a file's text content (notes, subtitles) as a UTF-8 string.
Future<String> downloadText(
  MegaApi api,
  String rootHandle,
  MegaNode file,
) async {
  final bytes = await downloadFile(api, rootHandle, file);
  return String.fromCharCodes(bytes);
}

/// Download a resource file into the app cache and return the local file.
Future<File> downloadToCache(
  MegaApi api,
  String rootHandle,
  MegaNode file,
) async {
  final dir = await getTemporaryDirectory();
  final safeName = file.name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
  final target = File('${dir.path}/mega_${file.handle}_$safeName');
  if (await target.exists()) return target;
  final bytes = await downloadFile(api, rootHandle, file);
  return target.writeAsBytes(bytes, flush: true);
}
