import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/compression_service.dart';
import 'package:dev_tool/ui/widgets.dart';

import 'functionality_audit_test.dart' as audit;
import 'generation_regression_audit_test.dart' as harness;

Future<void> enter(WidgetTester tester, String value) async {
  final pane = tester
      .widgetList<EditorPane>(find.byType(EditorPane))
      .firstWhere((p) => !p.readOnly);
  pane.controller!.text = value;
  pane.onChanged?.call(value);
  await audit.settle(tester);
}

String output(WidgetTester tester) => tester
    .widgetList<EditorPane>(find.byType(EditorPane))
    .firstWhere((p) => p.readOnly)
    .controller!
    .text;
Future<void> segment(WidgetTester tester, String label) async {
  final toggle = tester
      .widgetList<SegmentedToggle>(find.byType(SegmentedToggle))
      .firstWhere((w) => w.options.contains(label));
  toggle.onChanged!(toggle.options.indexOf(label));
  await audit.settle(tester);
}

void main() {
  for (final codec in CompressionCodec.values) {
    testWidgets('compression UI roundtrip and malformed input: ${codec.name}', (
      tester,
    ) async {
      await harness.open(tester, 'compression_codecs');
      final dropdown = tester.widget<SmallDropdown>(find.byType(SmallDropdown));
      dropdown.onChanged!(codec.label);
      await audit.settle(tester);
      await segment(tester, 'Compress');
      const original = 'hello ✓\nhello ✓\nhello ✓';
      await enter(tester, original);
      final payload = output(tester);
      expect(payload, isNotEmpty);
      expect(decompressPayload(payload, codec).output, contains(original));
      await segment(tester, 'Decompress');
      await enter(tester, payload);
      expect(output(tester), contains(original));
      await enter(tester, 'not-a-valid-payload!');
      expect(output(tester), isEmpty);
      await enter(tester, payload);
      expect(output(tester), contains(original));
      await enter(tester, '');
      expect(output(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  for (final spec in [
    ('HS256', sha256),
    ('HS384', sha384),
    ('HS512', sha512),
  ]) {
    testWidgets('JWT ${spec.$1} valid signature, mismatch and recovery', (
      tester,
    ) async {
      await harness.open(tester, 'jwt_debugger');
      expect(tester.takeException(), isNull);
      String part(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final header = part({'alg': spec.$1, 'typ': 'JWT'});
      final payload = part({'sub': 'audit-fixture', 'name': 'Example'});
      final signature = base64Url
          .encode(
            Hmac(
              spec.$2,
              utf8.encode('audit-secret'),
            ).convert(utf8.encode('$header.$payload')).bytes,
          )
          .replaceAll('=', '');
      await enter(tester, '$header.$payload.$signature');
      final panes = tester.widgetList<EditorPane>(find.byType(EditorPane));
      expect(
        jsonDecode(
          panes.firstWhere((p) => p.label == 'Header').controller!.text,
        )['alg'],
        spec.$1,
      );
      expect(
        jsonDecode(
          panes.firstWhere((p) => p.label == 'Payload').controller!.text,
        )['sub'],
        'audit-fixture',
      );
      final secret = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Enter secret key…',
      );
      await tester.enterText(secret, 'audit-secret');
      await audit.settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Verify signature'));
      await audit.settle(tester);
      expect(find.text('Signature Verified'), findsOneWidget);
      await tester.enterText(secret, 'wrong-secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify signature'));
      await audit.settle(tester);
      expect(find.text('Signature Mismatch'), findsOneWidget);
      await tester.enterText(secret, 'audit-secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify signature'));
      await audit.settle(tester);
      expect(find.text('Signature Verified'), findsOneWidget);
    });
  }
  testWidgets('line sort all direction and duplicate options', (tester) async {
    await harness.open(tester, 'line_sort_dedupe');
    await enter(tester, 'b\na\nb\nc');
    expect(output(tester), 'a\nb\nb\nc');
    final dropdowns = tester
        .widgetList<SmallDropdown>(find.byType(SmallDropdown))
        .toList();
    dropdowns[1].onChanged!('Without Duplicates');
    await audit.settle(tester);
    expect(output(tester), 'a\nb\nc');
    tester
        .widgetList<SmallDropdown>(find.byType(SmallDropdown))
        .first
        .onChanged!('Z -> A (Text)');
    await audit.settle(tester);
    expect(output(tester), 'c\nb\na');
    await enter(tester, '');
    expect(output(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
