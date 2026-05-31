import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A single served request, surfaced to the UI as an access-log line.
class ServerLogEntry {
  ServerLogEntry({
    required this.time,
    required this.method,
    required this.path,
    required this.status,
    required this.client,
    required this.bytes,
  });

  final DateTime time;
  final String method;
  final String path;
  final int status;
  final String client;
  final int bytes;
}

/// Serves a folder's static files over HTTP. Binds to loopback by default so
/// it isn't exposed to the network unless the caller opts in.
class LocalServerService {
  HttpServer? _server;
  String? _rootPath;

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String? get rootPath => _rootPath;

  Future<void> start({
    required String root,
    required int port,
    required bool localOnly,
    required void Function(ServerLogEntry entry) onLog,
  }) async {
    if (_server != null) {
      throw StateError('Server is already running.');
    }
    if (!Directory(root).existsSync()) {
      throw const FileSystemException('Selected folder does not exist.');
    }
    final address = localOnly
        ? InternetAddress.loopbackIPv4
        : InternetAddress.anyIPv4;
    final server = await HttpServer.bind(address, port);
    _server = server;
    _rootPath = root;
    server.listen(
      (request) => _handle(request, root, onLog),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _rootPath = null;
    await server?.close(force: true);
  }

  Future<void> _handle(
    HttpRequest request,
    String root,
    void Function(ServerLogEntry entry) onLog,
  ) async {
    final response = request.response;
    final client = request.connectionInfo?.remoteAddress.address ?? '—';
    var status = HttpStatus.ok;
    var bytes = 0;

    Future<void> writeText(int code, String body) async {
      status = code;
      bytes = utf8.encode(body).length;
      response.statusCode = code;
      response.headers.contentType = ContentType.html;
      response.write(body);
    }

    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        await writeText(HttpStatus.methodNotAllowed, _errorPage('405', 'Method not allowed'));
        return;
      }

      final rootDir = Directory(root).absolute;
      final rootCanonical = p.normalize(rootDir.path);
      final requested = Uri.decodeComponent(request.uri.path);
      final relative = requested.replaceFirst(RegExp(r'^/+'), '');
      final candidate = p.normalize(p.join(rootCanonical, relative));

      // Directory-traversal guard: stay inside the served root.
      if (candidate != rootCanonical && !p.isWithin(rootCanonical, candidate)) {
        await writeText(HttpStatus.forbidden, _errorPage('403', 'Forbidden'));
        return;
      }

      final type = FileSystemEntity.typeSync(candidate);
      File? file;
      if (type == FileSystemEntityType.directory) {
        final indexFile = File(p.join(candidate, 'index.html'));
        if (indexFile.existsSync()) {
          file = indexFile;
        } else {
          final listing = _directoryListing(rootCanonical, candidate, requested);
          await writeText(HttpStatus.ok, listing);
          return;
        }
      } else if (type == FileSystemEntityType.file) {
        file = File(candidate);
      }

      if (file == null) {
        await writeText(HttpStatus.notFound, _errorPage('404', 'Not found'));
        return;
      }

      final data = await file.readAsBytes();
      bytes = data.length;
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = _contentTypeFor(file.path);
      response.headers.set(HttpHeaders.contentLengthHeader, data.length);
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      if (request.method != 'HEAD') {
        response.add(data);
      }
    } catch (_) {
      status = HttpStatus.internalServerError;
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.write(_errorPage('500', 'Server error'));
      } catch (_) {
        // response may already be committed.
      }
    } finally {
      try {
        await response.close();
      } catch (_) {
        // ignore
      }
      onLog(
        ServerLogEntry(
          time: DateTime.now(),
          method: request.method,
          path: request.uri.path,
          status: status,
          client: client,
          bytes: bytes,
        ),
      );
    }
  }

  String _directoryListing(String root, String dirPath, String requestPath) {
    final dir = Directory(dirPath);
    final entries = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
    final buffer = StringBuffer()
      ..writeln('<!doctype html><html><head><meta charset="utf-8">')
      ..writeln('<title>Index of $requestPath</title>')
      ..writeln('<style>body{font-family:system-ui,sans-serif;margin:2rem;}'
          'h1{font-size:1.1rem;}a{display:block;padding:2px 0;}</style>')
      ..writeln('</head><body>')
      ..writeln('<h1>Index of $requestPath</h1>');
    final base = requestPath.endsWith('/') ? requestPath : '$requestPath/';
    if (p.normalize(dirPath) != root) {
      buffer.writeln('<a href="$base..">../</a>');
    }
    for (final entry in entries) {
      final name = p.basename(entry.path);
      final isDir = FileSystemEntity.isDirectorySync(entry.path);
      final href = Uri.encodeComponent(name);
      buffer.writeln('<a href="$base$href${isDir ? '/' : ''}">$name${isDir ? '/' : ''}</a>');
    }
    buffer.writeln('</body></html>');
    return buffer.toString();
  }

  String _errorPage(String code, String message) {
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<title>$code $message</title></head>'
        '<body style="font-family:system-ui,sans-serif;margin:2rem;">'
        '<h1>$code</h1><p>$message</p></body></html>';
  }

  static ContentType _contentTypeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.html':
      case '.htm':
        return ContentType.html;
      case '.css':
        return ContentType('text', 'css', charset: 'utf-8');
      case '.js':
      case '.mjs':
        return ContentType('text', 'javascript', charset: 'utf-8');
      case '.json':
        return ContentType('application', 'json', charset: 'utf-8');
      case '.xml':
        return ContentType('application', 'xml', charset: 'utf-8');
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.png':
        return ContentType('image', 'png');
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.gif':
        return ContentType('image', 'gif');
      case '.webp':
        return ContentType('image', 'webp');
      case '.ico':
        return ContentType('image', 'x-icon');
      case '.txt':
      case '.md':
        return ContentType('text', 'plain', charset: 'utf-8');
      case '.wasm':
        return ContentType('application', 'wasm');
      case '.woff2':
        return ContentType('font', 'woff2');
      case '.woff':
        return ContentType('font', 'woff');
      case '.ttf':
        return ContentType('font', 'ttf');
      case '.pdf':
        return ContentType('application', 'pdf');
      case '.mp4':
        return ContentType('video', 'mp4');
      case '.mp3':
        return ContentType('audio', 'mpeg');
      default:
        return ContentType.binary;
    }
  }
}
