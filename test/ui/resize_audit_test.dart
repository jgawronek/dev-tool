import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_tool/registry/tool_registry.dart';
import '../helpers/tool_harness.dart';

void main() {
  for (final tool in ToolRegistry.tools) {
    testWidgets('compact layout: ${tool.id}', (tester) async {
      final h = ToolHarness(tester);
      await h.open(tool.id, surface: const Size(1040, 700));
      expect(tester.takeException(), isNull, reason: '${tool.id} empty');
      final sample = find.widgetWithText(OutlinedButton, 'Load sample');
      if (sample.evaluate().isNotEmpty) {
        await tester.tap(sample);
        await h.settle();
      }
      expect(tester.takeException(), isNull, reason: '${tool.id} sample');
    });
  }
}
