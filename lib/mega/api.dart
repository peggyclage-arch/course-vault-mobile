import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

/// Thrown when the Mega API answers with an error code or bad data.
class MegaApiException implements Exception {
  final String message;
  const MegaApiException(this.message);
  @override
  String toString() => 'MegaApiException: $message';
}

/// Minimal client for the public Mega JSON API (`g.api.mega.co.nz/cs`),
/// ported from the megajs reference implementation (qgustavor/mega,
/// lib/api.mjs, MIT). Only the calls a public folder link needs:
/// `f` (list a folder tree) and `g` (get a file download URL).
class MegaApi {
  static const _gateway = 'https://g.api.mega.co.nz/';

  final http.Client _client;
  int _counter;

  MegaApi({http.Client? client})
      : _client = client ?? http.Client(),
        _counter = 100000000 + Random().nextInt(900000000);

  /// POST one command object. Returns the first element of the response.
  /// Retries transient errors and answers hashcash challenges.
  Future<dynamic> request(
    Map<String, dynamic> command, {
    Map<String, String>? query,
  }) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      _counter++;
      final uri = Uri.parse(_gateway).replace(
        path: 'cs',
        queryParameters: {'id': _counter.toString(), ...?query},
      );
      final resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode([command]),
      );

      final hashcash = resp.headers['x-hashcash'];
      if (hashcash != null) {
        // Mega wants proof-of-work before answering; compute and retry.
        final token = _generateHashcashToken(hashcash);
        _counter++;
        final retryUri = Uri.parse(_gateway).replace(
          path: 'cs',
          queryParameters: {'id': _counter.toString(), ...?query},
        );
        final retryResp = await _client.post(
          retryUri,
          headers: {
            'Content-Type': 'application/json',
            'X-Hashcash': token,
          },
          body: jsonEncode([command]),
        );
        return _handleResponse(retryResp);
      }
      final result = _handleResponse(resp);
      if (result is int && result == -3 && attempt < 3) {
        // EAGAIN — temporary congestion; back off and retry.
        await Future.delayed(Duration(seconds: 1 << (attempt + 1)));
        continue;
      }
      return result;
    }
    throw const MegaApiException('Mega API kept returning EAGAIN (-3).');
  }

  dynamic _handleResponse(http.Response resp) {
    if (!resp.isOk) {
      throw MegaApiException('Mega server returned HTTP ${resp.statusCode}.');
    }
    final body = jsonDecode(resp.body);
    final first = body is List ? body[0] : body;
    if (first is num && first < 0) {
      if (first == -3) return -3; // EAGAIN, handled by the retry loop
      throw MegaApiException('Mega API error $first.');
    }
    return first;
  }

  /// List a public folder tree. Returns the raw `f` node array.
  Future<List<dynamic>> listFolder(String rootHandle) async {
    final resp = await request(
      {'a': 'f', 'c': 1, 'ca': 1, 'r': 1},
      query: {'n': rootHandle},
    );
    final nodes = resp['f'];
    if (nodes is! List) {
      throw const MegaApiException('Unexpected folder listing response.');
    }
    return nodes;
  }

  /// Get a download URL + size for one file inside a public folder.
  /// Returns `{'url': ..., 'size': ...}`.
  Future<({String url, int size})> downloadUrl(
    String rootHandle,
    String nodeHandle,
  ) async {
    final resp = await request(
      {'a': 'g', 'g': 1, 'ssl': 2, 'n': nodeHandle},
      query: {'n': rootHandle},
    );
    final url = resp['g'];
    final size = resp['s'];
    if (url is! String || !url.startsWith('http') || size is! int) {
      throw const MegaApiException(
        'Mega returned an invalid download URL (maybe rate-limited).',
      );
    }
    return (url: url, size: size);
  }

  /// Fetch an arbitrary byte range of a file's ciphertext from its
  /// download URL. Mega storage servers accept `url/start-end`.
  Future<Uint8List> fetchRange(String url, int start, int end) async {
    final resp = await _client.get(Uri.parse('$url/$start-$end'));
    if (resp.statusCode == 509) {
      throw const MegaApiException(
        'Mega bandwidth limit reached — try again later.',
      );
    }
    if (resp.statusCode != 200) {
      throw MegaApiException(
        'Mega download failed with HTTP ${resp.statusCode}.',
      );
    }
    return resp.bodyBytes;
  }

  void close() => _client.close();
}

extension on http.Response {
  bool get isOk => statusCode >= 200 && statusCode < 300;
}

/// Hashcash token generation, ported from megajs (lib/crypto/index.mjs).
/// The challenge is `1:<easiness>:<token-b64>`; the token is 48 bytes.
String _generateHashcashToken(String challenge) {
  final parts = challenge.split(':');
  final version = int.parse(parts[0]);
  if (version != 1) {
    throw const MegaApiException('Unsupported hashcash version.');
  }
  final easiness = int.parse(parts[1]);
  final tokenStr = parts[3];
  final base = ((easiness & 63) << 1) + 1;
  final shifts = (easiness >> 6) * 7 + 3;
  final threshold = base << shifts;
  final token = _b64Decode(tokenStr);

  // 4-byte counter + the 48-byte token repeated 262144 times.
  final buffer = Uint8List(4 + 262144 * 48);
  for (var i = 0; i < 262144; i++) {
    buffer.setRange(4 + i * 48, 4 + (i + 1) * 48, token);
  }

  while (true) {
    final digest = crypto.sha256.convert(buffer).bytes;
    final firstWord = (digest[0] << 24) |
        (digest[1] << 16) |
        (digest[2] << 8) |
        digest[3];
    if (firstWord <= threshold) {
      final counterB64 =
          base64Url.encode(buffer.sublist(0, 4)).replaceAll('=', '');
      return '1:$tokenStr:$counterB64';
    }
    // Little-endian increment of the 4-byte counter.
    var j = 0;
    while (true) {
      buffer[j]++;
      if (buffer[j++] != 0) break;
    }
  }
}

Uint8List _b64Decode(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return base64.decode(t);
}
