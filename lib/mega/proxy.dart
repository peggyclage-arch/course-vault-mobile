import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'api.dart';
import 'catalogue.dart';
import 'crypto.dart';

/// A tiny local HTTP server that streams decrypted Mega video to the
/// platform video player.
///
/// Mega stores files AES-CTR encrypted and serves ciphertext byte ranges.
/// The player (ExoPlayer / AVPlayer) asks this server for ranges, the
/// server fetches the matching ciphertext range from Mega, decrypts it,
/// and answers with `206 Partial Content`. The video file itself is never
/// written to disk in full — only the bytes the player asks for.
class VideoProxy {
  final MegaApi _api;
  final String _rootHandle;

  HttpServer? _server;
  final Map<String, _Source> _sources = {};

  VideoProxy(this._api, this._rootHandle);

  int get port => _server?.port ?? 0;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    _server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sources.clear();
  }

  /// Register a video file and get its local streaming URL for the player.
  String urlFor(MegaNode file) {
    final token = _randomToken();
    _sources[token] = _Source(file: file);
    return 'http://127.0.0.1:$port/video/$token';
  }

  String _randomToken() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final segments = req.uri.pathSegments;
      if (req.method != 'GET' || segments.length != 2 || segments[0] != 'video') {
        req.response
          ..statusCode = HttpStatus.notFound
          ..write('not found');
        await req.response.close();
        return;
      }
      final source = _sources[segments[1]];
      if (source == null) {
        req.response
          ..statusCode = HttpStatus.notFound
          ..write('unknown video');
        await req.response.close();
        return;
      }
      await _serve(req, source);
    } catch (e) {
      try {
        req.response
          ..statusCode = HttpStatus.internalServerError
          ..write('proxy error: $e');
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serve(HttpRequest req, _Source source) async {
    final file = source.file;
    final key = file.key;
    if (key == null || key.length != 32) {
      req.response
        ..statusCode = HttpStatus.internalServerError
        ..write('video has no decryption key');
      await req.response.close();
      return;
    }
    final size = file.size;
    if (size <= 0) {
      req.response
        ..statusCode = HttpStatus.noContent
        ..headers.set('Accept-Ranges', 'bytes');
      await req.response.close();
      return;
    }

    // Parse `Range: bytes=start-end`.
    var start = 0;
    var end = size - 1;
    var partial = false;
    final range = req.headers.value('range');
    if (range != null) {
      final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m != null) {
        if (m.group(1)!.isNotEmpty) start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
        if (start >= size) {
          req.response
            ..statusCode = HttpStatus.requestedRangeNotSatisfiable
            ..headers.set('Content-Range', 'bytes */$size');
          await req.response.close();
          return;
        }
        end = end.clamp(0, size - 1);
        partial = true;
      }
    }

    final resp = req.response;
    resp.headers.set('Accept-Ranges', 'bytes');
    resp.headers.set('Content-Type', _contentType(file.name));
    if (partial) {
      resp.statusCode = HttpStatus.partialContent;
      resp.headers.set('Content-Range', 'bytes $start-$end/$size');
    } else {
      resp.statusCode = HttpStatus.ok;
    }
    resp.headers.set('Content-Length', (end - start + 1).toString());

    const chunk = 1024 * 1024; // fetch 1 MB ciphertext at a time
    var cursor = start;
    while (cursor <= end) {
      final fetchEnd = (cursor + chunk - 1).clamp(0, end);
      // Align the fetch down to a 16-byte boundary for the CTR counter;
      // aesCtrDecrypt skips the (cursor - aligned) prefix bytes.
      final aligned = cursor - (cursor % 16);
      final cipher = await _fetchCipher(source, aligned, fetchEnd);
      var plain = aesCtrDecrypt(key, cipher, cursor);
      // Trim to exactly the bytes still owed.
      final remaining = end - cursor + 1;
      if (plain.length > remaining) {
        plain = plain.sublist(0, remaining);
      }
      resp.add(plain);
      await resp.flush();
      cursor += plain.length;
      if (plain.isEmpty) break;
    }
    await resp.close();
  }

  /// Fetch ciphertext bytes [start]-[end] (inclusive) for a source,
  /// refreshing the download URL once if it has expired.
  Future<Uint8List> _fetchCipher(_Source source, int start, int end) async {
    source.url ??= await _api
        .downloadUrl(_rootHandle, source.file.handle)
        .then((v) => v.url);
    try {
      return await _api.fetchRange(source.url!, start, end);
    } catch (_) {
      // Download URL may have expired; get a fresh one and retry once.
      source.url = await _api
          .downloadUrl(_rootHandle, source.file.handle)
          .then((v) => v.url);
      return _api.fetchRange(source.url!, start, end);
    }
  }

  static String _contentType(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    return switch (ext) {
      'mp4' => 'video/mp4',
      'webm' => 'video/webm',
      'mov' => 'video/quicktime',
      'mkv' => 'video/x-matroska',
      _ => 'video/mp4',
    };
  }
}

class _Source {
  final MegaNode file;
  String? url;
  _Source({required this.file});
}
