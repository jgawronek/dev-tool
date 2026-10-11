import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dev_tool/app.dart';
import 'package:dev_tool/state/tool_state.dart';
import 'package:dev_tool/ui/widgets.dart';

import 'functionality_audit_test.dart' as audit;
import '../helpers/formatter_engine.dart';
import 'package:dev_tool/services/javascript_code_service.dart';

Future<ToolState> open(WidgetTester tester, String id) async {
  tester.view.physicalSize = const Size(2560, 1640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  if ({'html_beautify_minify', 'css_beautify_minify', 'js_beautify_minify'}.contains(id)) {
    installFormatterChannel();
    await tester.runAsync(() => JavascriptCodeService.process('const warm = 1;', 'Verify'));
  }
  final state = ToolState.inMemory();
  state.workspace.openTool(id);
  await tester.pumpWidget(DevToolApp(state: state));
  await audit.settle(tester);
  return state;
}

void main() {
  for (final style in [
    'Random characters',
    'Wordlist passphrase',
    'Numeric PIN',
    'UUID / token',
  ]) {
    testWidgets('password 500 batch and copy: $style', (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      await open(tester, 'password_generator');
      final dropdown = tester.widget<SmallDropdown>(
        find.byType(SmallDropdown).first,
      );
      dropdown.onChanged!(style);
      await audit.settle(tester);
      final count = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Count (1–500)',
      );
      await tester.enterText(count, '500');
      await audit.settle(tester);
      final value = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .first
          .data!;
      final lines = value.split('\n');
      expect(lines.length, 500);
      expect(lines.every((s) => s.isNotEmpty), isTrue);
      if (style == 'Numeric PIN') {
        expect(lines.every((s) => RegExp(r'^\d+$').hasMatch(s)), isTrue);
      }
      if (style == 'UUID / token') {
        expect(
          lines.every((s) => RegExp(r'^[0-9a-f-]{36}$').hasMatch(s)),
          isTrue,
        );
      }
      await tester.tap(find.widgetWithText(OutlinedButton, 'Copy all'));
      await audit.settle(tester);
      expect(copied, value);
      for (final bad in ['0', '501', '-1', 'abc', '1.5', '']) {
        await tester.enterText(count, bad);
        await audit.settle(tester);
        expect(find.text('Enter a number from 1 to 500.'), findsOneWidget);
        expect(
          tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .first
              .data,
          value,
        );
      }
      await tester.enterText(count, '1');
      await audit.settle(tester);
      expect(find.text('Enter a number from 1 to 500.'), findsNothing);
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .first
            .data!
            .split('\n')
            .length,
        1,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'UUID sample generates and each generation type produces the requested count',
    (tester) async {
      await open(tester, 'uuid_ulid_generate_decode');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Load sample'));
      await audit.settle(tester);
      EditorPane output() => tester
          .widgetList<EditorPane>(find.byType(EditorPane))
          .firstWhere((p) => p.readOnly);
      expect(output().controller!.text.trim(), isNotEmpty);
      final dropdown = tester.widget<SmallDropdown>(find.byType(SmallDropdown));
      for (final type in dropdown.items) {
        tester.widget<SmallDropdown>(find.byType(SmallDropdown)).onChanged!(
          type,
        );
        await audit.settle(tester);
        final count = find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == '1' && !w.readOnly,
        );
        await tester.enterText(count.last, '10');
        await tester.tap(find.widgetWithText(OutlinedButton, 'Generate'));
        await audit.settle(tester);
        final lines = output().controller!.text.trim().split('\n');
        expect(lines.length, 10, reason: type);
        expect(lines.toSet().length, 10, reason: '$type uniqueness');
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == '10' && !w.readOnly,
        );
        await tester.enterText(field.last, '1');
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('line sort sample immediately calculates numeric output', (
    tester,
  ) async {
    await open(tester, 'line_sort_dedupe');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Load sample'));
    await audit.settle(tester);
    final panes = tester.widgetList<EditorPane>(find.byType(EditorPane));
    final input = panes.firstWhere((p) => !p.readOnly).controller!.text;
    final output = panes.firstWhere((p) => p.readOnly).controller!.text;
    expect(input, isNotEmpty);
    expect(output, isNotEmpty);
    expect(output.split('\n').toSet(), input.split('\n').toSet());
    expect(tester.takeException(), isNull);
  });
}
