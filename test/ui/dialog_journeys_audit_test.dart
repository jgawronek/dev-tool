import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dev_tool/ui/documentation.dart';
import 'package:dev_tool/ui/widgets.dart';
import 'package:dev_tool/ui/tools/common/shared.dart';
import 'package:dev_tool/data/tool_documentation.dart';
import 'package:dev_tool/registry/tool_registry.dart';

import 'functionality_audit_test.dart' as audit;
import 'generation_regression_audit_test.dart' as harness;

Future<void> inline(WidgetTester tester, String hint, String value) async {
  final field = tester.widget<InlineTextField>(
    find.byWidgetPredicate((w) => w is InlineTextField && w.hintText == hint),
  );
  field.controller!.text = value;
  field.onChanged?.call(value);
  await audit.settle(tester);
}

void main() {
  test('every registered tool has documentation', () {
    for (final tool in ToolRegistry.tools) {
      expect(toolDocumentation[tool.id], isNotEmpty, reason: tool.id);
    }
  });
  testWidgets('TOTP add, edit, codes and persisted fixture', (tester) async {
    await harness.open(tester, 'auth_totp');
    final baseline = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => RegExp(r'^\d{6}$').hasMatch(t.data ?? ''))
        .length;
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_TotpAddCard',
        ),
        matching: find.byType(InkWell),
      ),
    );
    await audit.settle(tester);
    await inline(tester, 'Paste or enter secret', 'JBSWY3DPEHPK3PXP');
    await inline(tester, 'Optional label', 'Audit fixture');
    await tester.tap(find.text('Add'));
    await audit.settle(tester);
    expect(find.text('Audit fixture'), findsOneWidget);
    final codes = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => RegExp(r'^\d{6}$').hasMatch(t.data ?? ''))
        .length;
    expect(codes, baseline + 2);
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString('totp_entries')!).last['name'],
      'Audit fixture',
    );
    await tester.tap(find.byTooltip('Edit entry').last);
    await audit.settle(tester);
    await inline(tester, 'Optional label', 'Edited fixture');
    await tester.tap(find.text('Save'));
    await audit.settle(tester);
    expect(find.text('Edited fixture'), findsOneWidget);
    expect(find.text('Audit fixture'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search, favorites and tab navigation', (tester) async {
    final state = await harness.open(tester, 'base64_string_encode_decode');
    await tester.tap(find.byTooltip('Add to favorites'));
    await audit.settle(tester);
    expect(state.favorites.value, contains('base64_string_encode_decode'));
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove from favorites'));
    await audit.settle(tester);
    expect(
      state.favorites.value,
      isNot(contains('base64_string_encode_decode')),
    );
    final search = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Find a tool',
    );
    await tester.enterText(search, 'CSV Inspector');
    await audit.settle(tester);
    final item = find.byWidgetPredicate(
      (w) => w is Text && w.data == 'CSV Inspector',
    );
    expect(item, findsOneWidget);
    await tester.tap(item);
    await audit.settle(tester);
    expect(state.workspace.focusedPanel!.toolId, 'csv_inspector');
    expect(tester.takeException(), isNull);
  });
  testWidgets('documentation search and every guide is present', (
    tester,
  ) async {
    await harness.open(tester, 'base64_string_encode_decode');
    final context = tester.element(find.byType(Scaffold).first);
    showDialog<void>(
      context: context,
      builder: (_) => const DocumentationView(),
    );
    await audit.settle(tester);
    final search = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search all guides',
    );
    await tester.enterText(search, 'CSV Inspector');
    await audit.settle(tester);
    expect(find.text('CSV Inspector'), findsWidgets);
    expect(find.textContaining('does not have a guide'), findsNothing);
    await tester.tap(find.byTooltip('Close documentation'));
    await audit.settle(tester);
    expect(find.byType(DocumentationView), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'random string Words field produces content when character counts are zero',
    (tester) async {
      await harness.open(tester, 'random_string_generator');
      for (final label in [
        'Uppercased Characters',
        'Lowercased Characters',
        'Symbols',
        'Digits',
      ]) {
        final field = tester.widget<LabeledField>(
          find.byWidgetPredicate((w) => w is LabeledField && w.label == label),
        );
        field.controller!.text = '0';
      }
      final words = tester.widget<LabeledField>(
        find.byWidgetPredicate((w) => w is LabeledField && w.label == 'Words'),
      );
      words.controller!.text = '3';
      await tester.tap(find.widgetWithText(OutlinedButton, 'Load sample'));
      await audit.settle(tester);
      final pane = tester.widget<EditorPane>(find.byType(EditorPane));
      expect(
        pane.controller!.text.trim(),
        isNotEmpty,
        reason: 'Three words per item should not produce blank lines.',
      );
    },
  );
}
