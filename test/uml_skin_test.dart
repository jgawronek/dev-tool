import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/ui/tool_views.dart';

void main() {
  // Background color of the first class box ('User') in the default sample.
  Color? firstClassBoxColor(WidgetTester tester) {
    final box = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_UmlTypeBox',
    );
    final containers = find.descendant(
      of: box.first,
      matching: find.byType(Container),
    );
    for (final el in containers.evaluate()) {
      final dec = (el.widget as Container).decoration;
      if (dec is BoxDecoration && dec.color != null) return dec.color;
    }
    return null;
  }

  testWidgets('selecting a palette skin recolors class boxes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildUmlClassDiagram())),
    );
    await tester.pumpAndSettle();

    final autoColor = firstClassBoxColor(tester);
    expect(autoColor, isNotNull, reason: 'class box should have a fill color');

    // Open the node-skin dropdown (shows "Auto" by default) and pick "Pastel".
    await tester.tap(find.text('Auto').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pastel').last);
    await tester.pumpAndSettle();

    final pastelColor = firstClassBoxColor(tester);
    expect(pastelColor, isNotNull);
    expect(
      pastelColor,
      isNot(autoColor),
      reason: 'switching to the Pastel skin should change the box fill',
    );
  });
}
