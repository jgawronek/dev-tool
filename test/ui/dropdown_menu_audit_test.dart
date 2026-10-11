import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_tool/registry/tool_registry.dart';
import 'package:dev_tool/ui/widgets.dart';
import 'generation_regression_audit_test.dart' as harness;
import 'functionality_audit_test.dart' as audit;

void main() {
  for (final tool in ToolRegistry.tools) {
    testWidgets('dropdown menu paths: ${tool.id}', (tester) async {
      await harness.open(tester, tool.id);
      final sample = find.widgetWithText(OutlinedButton, 'Load sample');
      if (sample.evaluate().isNotEmpty) {
        await tester.tap(sample);
        await audit.settle(tester);
      }
      final checked = <Map<String, Object?>>[];
      final seen = <String>{};
      for (var round = 0; round < 30; round++) {
        final counts = <String, int>{};
        SmallDropdown? next;
        var ordinal = 0;
        var key = '';
        for (final dropdown in tester.widgetList<SmallDropdown>(find.byType(SmallDropdown))) {
          final signature = dropdown.items.join('|');
          final n = counts.update(signature, (n) => n + 1, ifAbsent: () => 0);
          final candidate = '$signature#$n';
          if (dropdown.onChanged != null && !seen.contains(candidate)) {
            next = dropdown;
            ordinal = n;
            key = candidate;
            break;
          }
        }
        if (next == null) break;
        seen.add(key);
        final items = List<String>.of(next.items);
        final selected = <String>[];
        for (final item in items) {
          final parent = find.byWidgetPredicate((w) => w is SmallDropdown && w.items.join('|') == items.join('|')).at(ordinal);
          if (parent.evaluate().isEmpty) break;
          final button = find.descendant(of: parent, matching: find.byType(DropdownButton<String>));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await audit.settle(tester);
          if (find.text(item).evaluate().isEmpty) {
            await tester.scrollUntilVisible(find.text(item),
              items.indexOf(item) < items.indexOf(next.initialValue) ? -200 : 200,
              scrollable: find.byType(Scrollable).last, maxScrolls: 30);
          }
          expect(find.text(item), findsWidgets, reason: '${tool.id}: $key menu did not expose $item');
          final choice = find.text(item).last;
          await tester.ensureVisible(choice);
          await tester.tap(choice);
          await audit.settle(tester);
          if (parent.evaluate().isNotEmpty) {
            expect(tester.widget<DropdownButton<String>>(button).value, item, reason: '${tool.id}: $item');
          }
          selected.add(item);
          expect(tester.takeException(), isNull, reason: '${tool.id}: $item');
        }
        checked.add({'menu': key, 'selected': selected});
      }
      // ignore: avoid_print
      print('DROPDOWN_MENU_AUDIT ${jsonEncode({'tool': tool.id, 'menus': checked})}');
    });
  }
}
