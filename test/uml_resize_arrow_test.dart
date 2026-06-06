import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/ui/tool_views.dart';
import 'package:dev_tool/ui/widgets.dart';

void main() {
  // The painter anchors relation arrows to a box via _umlBoxSize. Class boxes
  // render at content height regardless of any stored height, so _umlBoxSize
  // must report that same content height — otherwise a vertical resize moves
  // the anchor off the visible box and "breaks" the arrow. This asserts the
  // rendered box height is unchanged by a vertical drag.
  testWidgets('vertical resize leaves a class box height unchanged', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildUmlClassDiagram())),
    );
    await tester.pumpAndSettle();

    const src = '@startuml\nclass Box {\n  +a: int\n}\nclass Other\n'
        'Box --> Other\n@enduml';
    final pane = tester.widget<EditorPane>(find.byType(EditorPane));
    pane.controller!.text = src;
    pane.onChanged!(src);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Box').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    final handles = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_UmlResizeHandle',
    );
    // all = [nw, n, ne, e, se, s, sw, w]; n=1, s=5.
    double boxHeight() {
      final n = tester.getRect(handles.at(1)).center.dy;
      final s = tester.getRect(handles.at(5)).center.dy;
      return s - n;
    }

    final before = boxHeight();
    // Drag the south handle far down — for a class box this must NOT stretch it.
    await tester.drag(handles.at(5), const Offset(0, 200));
    await tester.pumpAndSettle();
    final after = boxHeight();

    expect(
      (after - before).abs(),
      lessThan(1.0),
      reason: 'class box height should be content-driven (was $before, now $after)',
    );
  });
}
