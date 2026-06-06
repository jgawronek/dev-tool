import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_tool/ui/tool_views.dart';
import 'package:dev_tool/ui/app_colors.dart';

// The PlantUML canvas pans via a single shared transform, so every element must
// move in lockstep. A macOS trackpad two-finger pan reports small incidental
// scale jitter; if that's treated as zoom it re-anchors around the cursor and
// shifts far elements more than near ones — the reported "items pan at
// different speeds / z-offset" bug. These tests pin both halves: jitter pans
// uniformly, but a real pinch still zooms.

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.dark]),
      home: const Scaffold(
        body: SizedBox(width: 1200, height: 900, child: _Host()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _panZoom(
  WidgetTester tester, {
  required Offset pan,
  required double scale,
}) async {
  const focal = Offset(600, 450);
  await tester.sendEventToBinding(
    const PointerPanZoomStartEvent(pointer: 7, position: focal),
  );
  await tester.pump();
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      pointer: 7,
      position: focal,
      pan: pan,
      panDelta: pan,
      scale: scale,
    ),
  );
  await tester.pump();
  await tester.sendEventToBinding(
    const PointerPanZoomEndEvent(pointer: 7, position: focal),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('two-finger pan with scale jitter moves boxes uniformly', (
    tester,
  ) async {
    await _pump(tester);
    Offset center(String l) => tester.getCenter(find.text(l).first);
    const labels = ['User', 'Order', 'Role'];
    final before = {for (final l in labels) l: center(l)};

    // ~2% scale jitter accompanying a pan — the user intends pure panning.
    await _panZoom(tester, pan: const Offset(60, 0), scale: 1.02);

    final deltas = {for (final l in labels) l: center(l) - before[l]!};
    final ref = deltas.values.first;
    for (final entry in deltas.entries) {
      expect(
        (entry.value - ref).distance,
        lessThan(1.0),
        reason: '${entry.key} moved ${entry.value} vs $ref (not lockstep)',
      );
    }
  });

  testWidgets('dragging an unselected box pans the canvas, not the box', (
    tester,
  ) async {
    await _pump(tester);
    Offset center(String l) => tester.getCenter(find.text(l).first);
    final user0 = center('User');
    final order0 = center('Order');

    // Drag starting ON the (unselected) 'User' box. It should pan the whole
    // canvas — User and Order move together — instead of moving just User.
    await tester.dragFrom(user0, const Offset(50, 35));
    await tester.pumpAndSettle();

    final dUser = center('User') - user0;
    final dOrder = center('Order') - order0;
    expect(
      (dUser - dOrder).distance,
      lessThan(1.0),
      reason: 'box under the cursor must pan with everything, not move alone',
    );
    expect(dUser.dx, greaterThan(5)); // the canvas actually panned
  });

  testWidgets('snap-to-grid toggles and renders the grid without errors', (
    tester,
  ) async {
    await _pump(tester);
    // Starts off (grid_off icon shown).
    expect(find.byIcon(Icons.grid_off), findsOneWidget);
    expect(find.byIcon(Icons.grid_on), findsNothing);

    await tester.tap(find.byIcon(Icons.grid_off));
    await tester.pumpAndSettle();

    // Now on — the grid overlay paints without throwing.
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.grid_on), findsOneWidget);
  });

  testWidgets('a deliberate pinch still zooms', (tester) async {
    await _pump(tester);
    double spread() =>
        (tester.getCenter(find.text('User').first) -
                tester.getCenter(find.text('Role').first))
            .distance;
    final before = spread();

    // A real pinch (well past the jitter deadzone) must still zoom: zooming in
    // spreads the boxes apart on screen.
    await _panZoom(tester, pan: Offset.zero, scale: 1.6);

    expect(
      spread(),
      greaterThan(before * 1.2),
      reason: 'pinch-zoom should still scale the diagram',
    );
  });
}

class _Host extends StatelessWidget {
  const _Host();
  @override
  Widget build(BuildContext context) => buildUmlClassDiagram();
}
