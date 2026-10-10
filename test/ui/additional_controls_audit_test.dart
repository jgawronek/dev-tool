import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/registry/tool_registry.dart';
import 'package:dev_tool/ui/widgets.dart';

import 'control_audit_test.dart' as controls;
import 'functionality_audit_test.dart' as audit;
import 'generation_regression_audit_test.dart' as harness;

void main() {
  for (final tool in ToolRegistry.tools) {
    testWidgets('custom controls: ${tool.id}', (tester) async {
      final state = await harness.open(tester, tool.id);
      final scope = find
          .byKey(ValueKey(state.workspace.focusedPanel!.instanceId))
          .last;
      final errors = <String>[];
      final actions = <String>[];
      void drain(String action) {
        Object? error;
        while ((error = tester.takeException()) != null) {
          errors.add('$action: $error');
        }
      }

      drain('open');
      final sample = find.widgetWithText(OutlinedButton, 'Load sample');
      if (sample.evaluate().isNotEmpty) {
        await tester.tap(sample.first);
        await audit.settle(tester);
        drain('sample');
      }
      final seen = <String>{};
      for (var round = 0; round < 100; round++) {
        Element? next;
        var key = '';
        final counts = <String, int>{};
        for (final e
            in find
                .descendant(
                  of: scope,
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is InkWell ||
                        w is GestureDetector ||
                        w is Slider ||
                        w is DropdownButton<String> ||
                        w is PopupMenuButton<String>,
                  ),
                )
                .evaluate()) {
          var insideButton = false;
          var insideTool = false;
          e.visitAncestorElements((a) {
            if (a.widget is ButtonStyleButton ||
                a.widget is IconButton ||
                a.widget is SmallDropdown ||
                a.widget is DropdownButton<String>) {
              insideButton = true;
            }
            if (a.widget.runtimeType.toString().endsWith('View')) {
              insideTool = true;
            }
            return true;
          });
          if (!insideTool || insideButton) continue;
          final w = e.widget;
          final base = w.runtimeType.toString();
          final n = counts.update(base, (v) => v + 1, ifAbsent: () => 0);
          final candidate = '$base#$n';
          if (!seen.contains(candidate)) {
            next = e;
            key = candidate;
            break;
          }
        }
        if (next == null) break;
        seen.add(key);
        final w = next.widget;
        try {
          if (controls.externalTools.contains(tool.id)) {
            actions.add('$key deferred: external dependency');
            continue;
          }
          if (w is Slider && w.onChanged != null) {
            for (final v in [w.min, (w.min + w.max) / 2, w.max]) {
              w.onChanged!(v);
              await audit.settle(tester);
              drain('$key $v');
            }
            actions.add('$key min/mid/max');
          } else if (w is DropdownButton<String> && w.onChanged != null) {
            for (final item in w.items ?? <DropdownMenuItem<String>>[]) {
              w.onChanged!(item.value);
              await audit.settle(tester);
              drain('$key ${item.value}');
              actions.add('$key ${item.value}');
            }
          } else if (w is PopupMenuButton<String>) {
            for (final item in w.itemBuilder(next)) {
              if (item is! PopupMenuItem<String> || !item.enabled) continue;
              if (item.value == 'print') {
                actions.add('$key print deferred: native print dialog');
                continue;
              }
              w.onSelected?.call(item.value!);
              await audit.settle(tester);
              drain('$key ${item.value}');
              actions.add('$key ${item.value}');
            }
          } else {
            final callback = w is InkWell
                ? w.onTap
                : w is GestureDetector
                ? w.onTap
                : null;
            if (callback == null) continue;
            callback();
            await audit.settle(tester);
            drain(key);
            actions.add('$key callback');
          }
          tester
              .state<NavigatorState>(find.byType(Navigator).first)
              .popUntil((r) => r.isFirst);
          await audit.settle(tester);
          drain('$key dialog close');
        } catch (e) {
          errors.add('$key: $e');
        }
      }
      // ignore: avoid_print
      print(
        'CUSTOM_AUDIT ${jsonEncode({'tool': tool.id, 'actions': actions, 'errors': errors})}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await audit.settle(tester);
      drain('dispose');
      expect(errors, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
