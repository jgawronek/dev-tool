import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/ui/tool_views.dart';
import 'package:dev_tool/ui/widgets.dart';

void main() {
  testWidgets('class node boxes can be dragged', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildUmlClassDiagram())),
    );
    await tester.pumpAndSettle();

    final box = find.text('User');
    expect(box, findsWidgets);
    final before = tester.getTopLeft(box.first);
    await tester.drag(box.first, const Offset(140, 80));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(box.first), isNot(before));
  });

  testWidgets('selected box shows 8 grabbable handles and resizes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildUmlClassDiagram())),
    );
    await tester.pumpAndSettle();

    const src = '@startuml\nclass Box {\n  +field: Type\n}\n@enduml';
    final pane = tester.widget<EditorPane>(find.byType(EditorPane));
    pane.controller!.text = src;
    pane.onChanged!(src);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Box').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Selected (not editing) → 8 resize handles, each within the surface.
    final handles = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_UmlResizeHandle',
    );
    expect(handles, findsNWidgets(8));
    for (var i = 0; i < 8; i++) {
      final r = tester.getRect(handles.at(i));
      expect(
        r.left >= 0 && r.top >= 0 && r.right <= 1400 && r.bottom <= 900,
        isTrue,
        reason: 'handle $i should be on-screen/hit-testable: $r',
      );
    }

    // Dragging a handle resizes the box (writes a @size comment to the source).
    await tester.drag(handles.first, const Offset(40, 30));
    await tester.pumpAndSettle();
    final resized = tester
        .widget<EditorPane>(find.byType(EditorPane))
        .controller!
        .text;
    expect(resized, contains("'@size Box"));
  });

  testWidgets('a bottom node stays selectable at a small window (extent fix)', (
    tester,
  ) async {
    // Regression: content taller than the viewport must stay hit-testable.
    // A node below the fold (here at y≈420) was painted but not selectable
    // because the content SizedBox was clamped to the viewport height.
    await tester.binding.setSurfaceSize(const Size(1500, 460));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildUmlClassDiagram())),
    );
    await tester.pumpAndSettle();

    const src =
        '@startuml\n'
        'rectangle "Top" as t1\n'
        "'@pos t1 60 60\n"
        'rectangle "Bottom" as b1\n'
        "'@pos b1 60 800\n"
        '@enduml';
    final pane = tester.widget<EditorPane>(find.byType(EditorPane));
    pane.controller!.text = src;
    pane.onChanged!(src);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    tester.takeException();

    // Fit brings the whole diagram (incl. the bottom node) into view — this is
    // the real path; before the fix the bottom node was visible but not
    // hit-testable because the content box was clamped to the viewport.
    await tester.tap(find.text('Fit'), warnIfMissed: false);
    await tester.pumpAndSettle();
    tester.takeException();

    final handles = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_UmlResizeHandle',
    );
    await tester.tap(find.text('Bottom').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    tester.takeException();
    expect(
      handles.evaluate().length,
      8,
      reason: 'a node far below the viewport must still be selectable',
    );
  });

  testWidgets('a node selects instantly on tap (no double-tap delay)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildUmlClassDiagram())),
    );
    await tester.pumpAndSettle();

    const src =
        '@startuml\nnote "test" as n1\nrectangle "Other" as o1\n@enduml';
    final pane = tester.widget<EditorPane>(find.byType(EditorPane));
    pane.controller!.text = src;
    pane.onChanged!(src);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    tester.takeException();

    int handleCount() => find
        .byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_UmlResizeHandle',
        )
        .evaluate()
        .length;

    // A single tap + settle must select (8 handles), every time.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('test').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      tester.takeException();
      expect(handleCount(), 8, reason: 'tap $i should keep the note selected');
    }
  });

  testWidgets('grouped «external» architecture node can be dragged', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildUmlClassDiagram())),
    );
    await tester.pumpAndSettle();

    // Load an architecture diagram with an external node inside a package.
    const arch = '''
@startuml
package "Tech" {
  rectangle "Database" as db <<technology>>
  rectangle "Platform APIs" as papi <<external>>
}
db --> papi
@enduml''';
    final pane = tester.widget<EditorPane>(find.byType(EditorPane));
    pane.controller!.text = arch;
    pane.onChanged!(arch);
    await tester.pump(const Duration(milliseconds: 400)); // debounce
    await tester.pumpAndSettle();

    final ext = find.text('Platform APIs');
    expect(ext, findsWidgets, reason: 'external node should render');
    final before = tester.getTopLeft(ext.first);
    await tester.drag(ext.first, const Offset(120, 90));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(ext.first),
      isNot(before),
      reason: 'grouped external node should move when dragged',
    );
  });

  testWidgets('architecture group body can be dragged', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildUmlClassDiagram())),
    );
    await tester.pumpAndSettle();

    const arch = '''
@startuml
rectangle "SaaS Platform Boundary\\nowned and operated by platform" as saas {
  rectangle "Client API" as api <<clientapi>>
  rectangle "Platform data stores" as data <<serverdata>>
}
api --> data
@enduml''';
    final pane = tester.widget<EditorPane>(find.byType(EditorPane));
    pane.controller!.text = arch;
    pane.onChanged!(arch);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final before = pane.controller!.text;
    final client = tester.getRect(find.text('Client API').first);
    final data = tester.getRect(find.text('Platform data stores').first);
    final groupBodyGap = Offset(
      (client.right + data.left) / 2,
      client.center.dy,
    );
    final groupBox = find
        .byWidgetPredicate((w) => w.runtimeType.toString() == '_UmlGroupBox')
        .first;

    expect(tester.getRect(groupBox).contains(groupBodyGap), isTrue);
    await tester.dragFrom(groupBodyGap, const Offset(90, 60));
    await tester.pumpAndSettle();

    expect(
      pane.controller!.text,
      isNot(before),
      reason: 'dragging the group body should move its children, not pan only',
    );
  });

  testWidgets('group context menu can move contents out', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildUmlClassDiagram())),
    );
    await tester.pumpAndSettle();

    const arch = '''
@startuml
rectangle "SaaS Platform Boundary" as saas {
  rectangle "Client API" as api <<clientapi>>
}
@enduml''';
    final pane = tester.widget<EditorPane>(find.byType(EditorPane));
    pane.controller!.text = arch;
    pane.onChanged!(arch);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final groupBox = find
        .byWidgetPredicate((w) => w.runtimeType.toString() == '_UmlGroupBox')
        .first;
    final rect = tester.getRect(groupBox);

    await tester.tapAt(
      rect.topLeft + const Offset(12, 10),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move contents out'));
    await tester.pumpAndSettle();

    final source = pane.controller!.text;
    expect(source, isNot(contains('as saas {')));
    expect(source, contains('rectangle "Client API" as api'));
  });
}
