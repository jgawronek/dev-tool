import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/app.dart';
import 'package:dev_tool/state/tool_state.dart';
import 'package:dev_tool/ui/widgets.dart';

/// Drives a tool panel through its public UI: opening, typing into editors,
/// tapping buttons, and reading editor contents.
///
/// All waits are bounded pumps: several editors animate a blinking cursor
/// forever, so `pumpAndSettle` would time out.
class ToolHarness {
  ToolHarness(this.tester);

  final WidgetTester tester;
  late ToolState state;

  Future<void> open(String toolId, {Size? surface}) async {
    if (surface != null) {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    state = ToolState.inMemory();
    state.workspace.openTool(toolId);
    await tester.pumpWidget(DevToolApp(state: state));
    await settle();
  }

  /// Pumps ~[ms] of fake time in small steps so animations and debounces run
  /// without waiting on endless cursor blinking.
  Future<void> settle([int ms = 400]) async {
    var remaining = ms;
    while (remaining > 0) {
      final step = remaining < 100 ? remaining : 100;
      await tester.pump(Duration(milliseconds: step));
      remaining -= step;
    }
  }

  EditorPane _pane(String? hint, {String? label, int index = 0}) {
    final panes = tester
        .widgetList<EditorPane>(
          find.byWidgetPredicate(
            (w) =>
                w is EditorPane &&
                (hint == null || w.placeholder == hint) &&
                (label == null || w.label == label),
          ),
        )
        .toList();
    if (panes.isEmpty) {
      throw StateError(
        'No EditorPane with placeholder="$hint" label="$label"',
      );
    }
    return panes[index];
  }

  bool hasPane(String? hint, {String? label}) => tester
      .widgetList(
        find.byWidgetPredicate(
          (w) =>
              w is EditorPane &&
              (hint == null || w.placeholder == hint) &&
              (label == null || w.label == label),
        ),
      )
      .isNotEmpty;

  /// Types [text] into the editor with [hint] and advances past the live
  /// recompute debounce.
  Future<void> enter(
    String? hint, {
    String? label,
    required String text,
    int index = 0,
  }) async {
    final pane = _pane(hint, label: label, index: index);
    pane.controller!.text = text;
    pane.onChanged?.call(text);
    await settle();
  }

  String text(String? hint, {String? label, int index = 0}) =>
      _pane(hint, label: label, index: index).controller!.text;

  Future<void> tap(String label, {int index = 0}) async {
    final finder = find.text(label);
    expect(finder, findsWidgets, reason: 'No button labeled "$label"');
    await tester.tap(finder.at(index));
    await settle();
  }

  Future<void> tapIcon(IconData icon, {int index = 0}) async {
    await tester.tap(find.byIcon(icon).at(index));
    await settle();
  }
}

/// Silences analyzer warnings for harnesses kept alive by side effects.
void ignore(Object? _) {}
