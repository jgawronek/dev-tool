import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/local_server_service.dart';
import 'package:dev_tool/services/url_request_service.dart';

void main() {
  for (final method in [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  ]) {
    test('URL request sends $method, headers and body to loopback', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('x-fixture', 'yes');
        request.response.write(
          jsonEncode({
            'method': request.method,
            'body': body,
            'header': request.headers.value('x-audit'),
          }),
        );
        await request.response.close();
      });
      final result = await UrlRequestService().send(
        uri: Uri.parse('http://127.0.0.1:${server.port}/fixture'),
        method: method,
        headers: {'x-audit': 'value'},
        body: method == 'HEAD' ? '' : 'sample body',
      );
      expect(result.status, '200 OK');
      expect(result.headers, contains('x-fixture: yes'));
      if (method == 'HEAD') {
        expect(result.body, isEmpty);
      } else {
        final decoded = jsonDecode(result.body) as Map;
        expect(decoded['method'], method);
        expect(decoded['body'], 'sample body');
        expect(decoded['header'], 'value');
        expect(result.bytes, greaterThan(0));
      }
    });
  }

  test(
    'URL request preserves non-JSON error response and does not follow redirect',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var hits = 0;
      server.listen((request) async {
        hits++;
        request.response.statusCode = request.uri.path == '/redirect'
            ? 302
            : 422;
        request.response.headers.set('location', '/other');
        request.response.write('plain response');
        await request.response.close();
      });
      for (final path in ['/error', '/redirect']) {
        final result = await UrlRequestService().send(
          uri: Uri.parse('http://127.0.0.1:${server.port}$path'),
          method: 'GET',
          headers: {},
          body: '',
        );
        expect(result.status, startsWith(path == '/error' ? '422' : '302'));
        expect(result.body, 'plain response');
      }
      expect(hits, 2);
    },
  );

  test('URL request rejects response larger than display limit', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write('x' * (2 * 1024 * 1024 + 1));
      await request.response.close();
    });
    await expectLater(
      UrlRequestService().send(
        uri: Uri.parse('http://127.0.0.1:${server.port}'),
        method: 'GET',
        headers: {},
        body: '',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'Local server start, GET, HEAD, missing file, unsupported method and stop',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'devutils-http-audit-',
      );
      addTearDown(() => folder.delete(recursive: true));
      await File('${folder.path}/index.html').writeAsString('<h1>Fixture</h1>');
      await File('${folder.path}/hello.txt').writeAsString('hello fixture');
      final logs = <ServerLogEntry>[];
      final service = LocalServerService();
      addTearDown(service.stop);
      await service.start(
        root: folder.path,
        port: 0,
        localOnly: true,
        onLog: logs.add,
      );
      expect(service.isRunning, isTrue);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      for (final spec in [
        ('GET', '/', 200, '<h1>Fixture</h1>'),
        ('GET', '/hello.txt', 200, 'hello fixture'),
        ('HEAD', '/hello.txt', 200, ''),
        ('GET', '/absent', 404, null),
        ('POST', '/hello.txt', 405, null),
      ]) {
        final request = await client.openUrl(
          spec.$1,
          Uri.parse('http://127.0.0.1:${service.port}${spec.$2}'),
        );
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        expect(response.statusCode, spec.$3);
        if (spec.$4 != null) expect(body, spec.$4);
      }
      expect(logs.length, 5);
      await service.stop();
      expect(service.isRunning, isFalse);
      expect(service.port, isNull);
      expect(service.rootPath, isNull);
    },
  );
}
