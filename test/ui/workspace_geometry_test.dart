import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/app.dart';
import 'package:dev_tool/registry/tool_registry.dart';
import 'package:dev_tool/state/tool_state.dart';
import 'package:dev_tool/state/workspace_state.dart';
import 'package:dev_tool/ui/sidebar.dart';
import 'package:dev_tool/ui/widgets.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder panelFor(String id) => find.byWidgetPredicate(
  (widget) =>
      widget.runtimeType.toString() == '_ToolPanel' &&
      widget.key == ValueKey(id),
);

Finder titleBarIn(String id) => find.descendant(
  of: panelFor(id),
  matching: find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_PanelTitleBar',
  ),
);

void expectOnCanvas(WidgetTester tester, ToolState state, String id) {
  final rect = tester.getRect(panelFor(id));
  final sidebar = tester.getRect(find.byType(Sidebar));
  final window = tester.view.physicalSize / tester.view.devicePixelRatio;
  final minSize = WorkspaceState.minSizeFor(
    state.workspace.panelById(id)?.toolId ?? '',
  );
  expect(
    rect.left,
    greaterThanOrEqualTo(sidebar.right),
    reason: '$id left: $rect',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(window.width + 0.1),
    reason: '$id right: $rect',
  );
  expect(rect.top, greaterThanOrEqualTo(0), reason: '$id top: $rect');
  expect(
    rect.bottom,
    lessThanOrEqualTo(window.height + 0.1),
    reason: '$id bottom: $rect',
  );
  expect(rect.width, greaterThanOrEqualTo(minSize.width - 0.1));
  expect(rect.height, greaterThanOrEqualTo(minSize.height - 0.1));
}

void main() {
  testWidgets('all tools render at the minimum floating panel size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = ToolState.inMemory();
    await tester.pumpWidget(DevToolApp(state: state));
    await settle(tester);
    final failures = <String>[];

    for (final tool in ToolRegistry.tools) {
      final instance = state.workspace.openTool(tool.id);
      await settle(tester);
      final handles = find.descendant(
        of: panelFor(instance.instanceId),
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_PanelResizeHandle',
        ),
      );
      expect(handles, findsNWidgets(4), reason: tool.name);

      // Resize the panel to exactly the tool's declared minimum. The gesture
      // path is covered by the dedicated drag tests below; here the question is
      // whether the tool's content renders cleanly at that floor.
      final minSize = WorkspaceState.minSizeFor(tool.id);
      state.workspace.updateBounds(
        instance.instanceId,
        const Offset(24, 24) & minSize,
      );
      await settle(tester);
      final after = tester.getRect(panelFor(instance.instanceId));
      if ((after.width - minSize.width).abs() > 1 ||
          (after.height - minSize.height).abs() > 1) {
        failures.add('${tool.name}: did not reach minimum ($after)');
      }
      final error = tester.takeException();
      if (error != null) failures.add('${tool.name}: $error');

      state.workspace.closePanel(instance.instanceId);
      await settle(tester);
      final closeError = tester.takeException();
      if (closeError != null) {
        failures.add('${tool.name} on close: $closeError');
      }
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets(
    'drag title bar, resize panel, resize sidebar, then scale window',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = ToolState.inMemory();
      await tester.pumpWidget(DevToolApp(state: state));
      await settle(tester);
      final panel = state.workspace.openTool('json_format_validate');
      await settle(tester);
      final id = panel.instanceId;
      final before = tester.getRect(panelFor(id));

      await tester.drag(titleBarIn(id), const Offset(100, 60));
      await settle(tester);
      final moved = tester.getRect(panelFor(id));
      expect(moved.left, greaterThan(before.left));
      expect(moved.top, greaterThan(before.top));
      expectOnCanvas(tester, state, id);

      final handles = find.descendant(
        of: panelFor(id),
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_PanelResizeHandle',
        ),
      );
      expect(handles, findsNWidgets(4));
      await tester.drag(handles.last, const Offset(80, 50));
      await settle(tester);
      final resized = tester.getRect(panelFor(id));
      expect(resized.width, greaterThan(moved.width));
      expect(resized.height, greaterThan(moved.height));
      expectOnCanvas(tester, state, id);

      await tester.drag(
        find.byKey(const ValueKey('sidebar-resize-handle')),
        const Offset(65, 0),
      );
      await settle(tester);
      expect(state.sidebarWidth.value, greaterThan(250));
      expectOnCanvas(tester, state, id);

      for (final size in [
        const Size(1200, 780),
        const Size(900, 650),
        const Size(1550, 980),
      ]) {
        tester.view.physicalSize = size;
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'layout at $size');
        expectOnCanvas(tester, state, id);
        expect(find.byType(EditorPane), findsWidgets);
      }
    },
  );

  testWidgets(
    'two tools remain usable while moving, resizing and changing window size',
    (tester) async {
      tester.view.physicalSize = const Size(1550, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = ToolState.inMemory();
      await tester.pumpWidget(DevToolApp(state: state));
      await settle(tester);
      final json = state.workspace.openTool('json_format_validate');
      final hash = state.workspace.openTool('hash_verifier');
      await settle(tester);
      await tester.drag(titleBarIn(hash.instanceId), const Offset(120, 40));
      await settle(tester);
      expectOnCanvas(tester, state, json.instanceId);
      expectOnCanvas(tester, state, hash.instanceId);
      final hashPane = tester.widget<EditorPane>(
        find.descendant(
          of: panelFor(hash.instanceId),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is EditorPane &&
                widget.placeholder == 'Text to verify (UTF-8)',
          ),
        ),
      );
      hashPane.controller!.text = 'abc';
      hashPane.onChanged?.call('abc');
      await settle(tester);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1050, 720);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expectOnCanvas(tester, state, json.instanceId);
      expectOnCanvas(tester, state, hash.instanceId);
    },
  );

  testWidgets('new tool controls do not overflow when the app is narrowed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = ToolState.inMemory();
    await tester.pumpWidget(DevToolApp(state: state));
    await settle(tester);

    for (final id in [
      'hash_verifier',
      'query_editor',
      'csv_inspector',
      'date_difference',
      'json_format_validate',
    ]) {
      final panel = state.workspace.openTool(id);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'opening $id');
      expectOnCanvas(tester, state, panel.instanceId);
      tester.view.physicalSize = const Size(850, 650);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'narrow $id');
      expectOnCanvas(tester, state, panel.instanceId);
      tester.view.physicalSize = const Size(1000, 700);
      state.workspace.closePanel(panel.instanceId);
      await settle(tester);
    }
  });

  testWidgets('repeated edge drags and resizes keep the panel usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = ToolState.inMemory();
    await tester.pumpWidget(DevToolApp(state: state));
    await settle(tester);
    final panel = state.workspace.openTool('csv_inspector');
    await settle(tester);

    for (final delta in [
      const Offset(280, 140),
      const Offset(-500, -300),
      const Offset(220, 160),
    ]) {
      await tester.drag(titleBarIn(panel.instanceId), delta);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expectOnCanvas(tester, state, panel.instanceId);

      final corners = find.descendant(
        of: panelFor(panel.instanceId),
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_PanelResizeHandle',
        ),
      );
      await tester.drag(corners.last, const Offset(40, 30));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expectOnCanvas(tester, state, panel.instanceId);
    }

    for (final size in [
      const Size(1000, 700),
      const Size(850, 650),
      const Size(1400, 900),
    ]) {
      tester.view.physicalSize = size;
      await settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: 'after edge drags at $size',
      );
      expectOnCanvas(tester, state, panel.instanceId);
    }
    expect(
      find.descendant(
        of: panelFor(panel.instanceId),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is EditorPane &&
              widget.placeholder == 'CSV with header row',
        ),
      ),
      findsOneWidget,
    );
  });
}
