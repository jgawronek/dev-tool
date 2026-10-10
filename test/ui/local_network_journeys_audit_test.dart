import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/ui/widgets.dart';

import 'functionality_audit_test.dart' as audit;
import 'generation_regression_audit_test.dart' as harness;

class _RealHttp extends HttpOverrides {}

Future<void> invokeNetwork(
  WidgetTester tester,
  void Function() callback,
) async {
  await tester.runAsync(
    () => HttpOverrides.runWithHttpOverrides(() async {
      callback();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }, _RealHttp()),
  );
  await audit.settle(tester);
}

void main() {
  testWidgets(
    'URL Parser Send button submits every method and displays responses',
    (tester) async {
      late HttpServer server;
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.headers.set('x-audit', 'fixture');
          request.response.write(jsonEncode({'method': request.method}));
          await request.response.close();
        });
      });
      addTearDown(() => server.close(force: true));
      await harness.open(tester, 'url_parser');
      final input = tester
          .widgetList<EditorPane>(find.byType(EditorPane))
          .firstWhere((p) => p.label == 'URL');
      input.controller!.text =
          'http://127.0.0.1:${server.port}/fixture?key=value';
      input.onChanged!(input.controller!.text);
      await audit.settle(tester);
      final methods = tester
          .widgetList<SmallDropdown>(find.byType(SmallDropdown))
          .first;
      for (final method in methods.items) {
        tester
            .widgetList<SmallDropdown>(find.byType(SmallDropdown))
            .first
            .onChanged!(method);
        await audit.settle(tester);
        final send = tester
            .widgetList<ToolButton>(find.byType(ToolButton))
            .firstWhere((b) => b.label == 'Send');
        expect(send.onPressed, isNotNull);
        await invokeNetwork(tester, send.onPressed!);
        final response = tester
            .widgetList<EditorPane>(find.byType(EditorPane))
            .firstWhere((p) => p.label == 'Response');
        if (method == 'HEAD') {
          expect(response.controller!.text, isEmpty);
        } else {
          expect(jsonDecode(response.controller!.text)['method'], method);
        }
        expect(find.textContaining('200 OK'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'AntiBot Run reads a loopback fixture and produces a detection report',
    (tester) async {
      late HttpServer server;
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          request.response.headers.set('server', 'cloudflare');
          request.response.headers.set('cf-ray', 'audit-fixture');
          request.response.write(
            '<html><title>Fixture</title><script>window._cf_chl_opt={};</script></html>',
          );
          await request.response.close();
        });
      });
      addTearDown(() => server.close(force: true));
      await harness.open(tester, 'antibot_detection');
      final input = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.decoration?.hintText == 'https://example.com',
        ),
      );
      input.controller!.text = 'http://127.0.0.1:${server.port}/fixture';
      final run = tester
          .widgetList<ToolButton>(find.byType(ToolButton))
          .firstWhere((b) => b.label == 'Go');
      await invokeNetwork(tester, run.onPressed!);
      final report = tester.widget<EditorPane>(find.byType(EditorPane));
      expect(report.controller!.text.toLowerCase(), contains('cloudflare'));
      expect(report.controller!.text, isNot(contains('Fetching...')));
      expect(tester.takeException(), isNull);
    },
  );
}
