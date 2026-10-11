import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_tool/ui/widgets.dart';
import '../helpers/tool_harness.dart';

class _RealHttp extends HttpOverrides {}

Future<void> runButton(WidgetTester tester, ToolHarness h, String label) async {
  final button = tester.widget<ToolButton>(
    find.byWidgetPredicate((w) => w is ToolButton && w.label == label),
  );
  await tester.runAsync(() async {
    button.onPressed!();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await h.settle();
}

void main() {
  testWidgets(
    'Local Server chooses a folder, serves actual bytes, logs a request and stops',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('local-server-ui-audit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(
        '${dir.path}/index.html',
      ).writeAsStringSync('<h1>Local fixture</h1>');
      const channel = MethodChannel('devutils/file_dialogs');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'openDirectory');
        return dir.path;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      late int port;
      await tester.runAsync(() async {
        final reservation = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        port = reservation.port;
        await reservation.close();
      });
      final h = ToolHarness(tester);
      await h.open('local_server');
      await runButton(tester, h, 'Start');
      expect(find.text('Choose a folder to serve first.'), findsOneWidget);
      await h.tap('Choose Folder');
      final field = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((w) => w.keyboardType == TextInputType.number);
      field.controller!.text = 'invalid';
      await runButton(tester, h, 'Start');
      expect(find.text('Enter a valid port (1–65535).'), findsOneWidget);
      field.controller!.text = '$port';
      await runButton(tester, h, 'Start');
      expect(find.text('Stop'), findsOneWidget);
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final client = HttpClient();
          try {
            final response = await (await client.getUrl(
              Uri.parse('http://127.0.0.1:$port/'),
            )).close();
            expect(response.statusCode, 200);
            expect(
              await utf8.decoder.bind(response).join(),
              '<h1>Local fixture</h1>',
            );
          } finally {
            client.close(force: true);
          }
        }, _RealHttp()),
      );
      await h.settle();
      expect(find.textContaining('GET'), findsWidgets);
      await runButton(tester, h, 'Stop');
      expect(find.text('Start'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Payload Embed, Check and Decode buttons preserve payload bytes',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('payload-ui-audit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final carrier = File('${dir.path}/carrier.pdf')
        ..writeAsStringSync(
          '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF\n',
        );
      final secret = File('${dir.path}/secret.txt')
        ..writeAsStringSync('  é漢字🙂 payload\n');
      final output = File('${dir.path}/embedded.pdf');
      final decoded = File('${dir.path}/decoded.txt');
      final h = ToolHarness(tester);
      await h.open('payload_embedder');
      void field(String hint, String value) {
        tester
                .widget<TextField>(
                  find.byWidgetPredicate(
                    (w) => w is TextField && w.decoration?.hintText == hint,
                  ),
                )
                .controller!
                .text =
            value;
      }

      field('/path/to/image.png, image.jpg, or document.pdf', carrier.path);
      field('/path/to/secret.txt', secret.path);
      field('Leave empty to create *.embedded.*', output.path);
      field('Required for encryption/decode', 'audit passphrase');
      await runButton(tester, h, 'Embed encrypted');
      for (
        var i = 0;
        i < 40 &&
            !h.text(null, label: 'Result').contains('Embedded encrypted file.');
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await h.settle();
      }
      expect(
        h.text(null, label: 'Result'),
        contains('Embedded encrypted file.'),
      );
      expect(output.existsSync(), isTrue);
      await runButton(tester, h, 'Check output');
      expect(
        h.text(null, label: 'Result'),
        contains('Encrypted payload found.'),
      );
      await h.tap('Decode');
      field('/path/to/image.png, image.jpg, or document.pdf', output.path);
      field('Leave empty to use embedded filename', decoded.path);
      await runButton(tester, h, 'Decode');
      for (
        var i = 0;
        i < 40 &&
            !h.text(null, label: 'Result').contains('Decoded embedded file.');
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await h.settle();
      }
      expect(h.text(null, label: 'Result'), contains('Decoded embedded file.'));
      expect(
        decoded.readAsBytesSync(),
        orderedEquals(secret.readAsBytesSync()),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
