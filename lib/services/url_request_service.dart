import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class UrlRequestResult {
  const UrlRequestResult({
    required this.status,
    required this.headers,
    required this.body,
    required this.elapsed,
    required this.bytes,
  });

  final String status;
  final String headers;
  final String body;
  final Duration elapsed;
  final int bytes;
}

/// One explicitly submitted request. Closing the client cancels pending I/O.
class UrlRequestService {
  final http.Client _client = http.Client();

  void close() => _client.close();

  Future<UrlRequestResult> send({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required String body,
  }) async {
    final watch = Stopwatch()..start();
    try {
      return await (() async {
        final request = http.Request(method, uri)
          ..followRedirects = false
          ..headers.addAll(headers);
        if (body.isNotEmpty) request.body = body;
        final response = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const FormatException(
              'Response exceeds the 2 MB display limit.',
            );
          }
          bytes.addAll(chunk);
        }
        final decoded = utf8.decode(bytes, allowMalformed: true);
        String formatted = decoded;
        try {
          formatted = const JsonEncoder.withIndent(
            '  ',
          ).convert(jsonDecode(decoded));
        } on FormatException {
          // Preserve non-JSON response text.
        }
        return UrlRequestResult(
          status: '${response.statusCode} ${response.reasonPhrase ?? ''}'
              .trim(),
          headers: response.headers.entries
              .map((e) => '${e.key}: ${e.value}')
              .join('\n'),
          body: formatted,
          elapsed: watch.elapsed,
          bytes: bytes.length,
        );
      })().timeout(const Duration(seconds: 30));
    } finally {
      close();
    }
  }
}
