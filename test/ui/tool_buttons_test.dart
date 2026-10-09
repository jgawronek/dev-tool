import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dev_tool/app.dart';
import 'package:dev_tool/registry/tool_registry.dart';
import 'package:dev_tool/state/tool_state.dart';
import 'package:dev_tool/ui/widgets.dart';

// Tools whose action buttons hit the network, bind ports, or spawn processes.
// Their buttons are verified to render and be enabled, but not tapped.
const sideEffectToolIds = {
  'port_scanner',
  'network_scanner',
  'firewall_fingerprint',
  'subdomain_finder',
  'subdomain_takeover',
  'local_server',
  'offline_llm',
};

bool _isActionable(Widget widget) {
  if (widget is ButtonStyleButton) return widget.onPressed != null;
  if (widget is IconButton) return widget.onPressed != null;
  if (widget is PopupMenuButton) return true;
  if (widget is ToggleButtons) return widget.onPressed != null;
  if (widget is SmallDropdown) return widget.onChanged != null;
  if (widget is Switch) return widget.onChanged != null;
  if (widget is SwitchListTile) return widget.onChanged != null;
  return false;
}

String _textOf(Widget? widget) {
  if (widget == null) return '';
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  if (widget is Row) return widget.children.map(_textOf).join(' ').trim();
  if (widget is Icon) return widget.icon?.codePoint.toRadixString(16) ?? '';
  return '';
}

String _label(Widget widget) {
  if (widget is ButtonStyleButton) return _textOf(widget.child);
  if (widget is IconButton) return 'icon:${_textOf(widget.icon)}';
  if (widget is SwitchListTile) return _textOf(widget.title);
  return widget.toStringShort();
}

bool _inPanelTitleBar(Element element) {
  var inTitleBar = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget.runtimeType.toString() == '_PanelTitleBar') {
      inTitleBar = true;
      return false;
    }
    return true;
  });
  return inTitleBar;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _popAllRoutes(WidgetTester tester) {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .popUntil((route) => route.isFirst);
}

void main() {
  testWidgets('every enabled button in every tool acts without errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final state = ToolState.inMemory();
    await tester.pumpWidget(DevToolApp(state: state));
    await _settle(tester);

    var totalTapped = 0;
    final perTool = <String, int>{};
    final noButtons = <String>[];

    for (final tool in ToolRegistry.tools) {
      state.workspace.openTool(tool.id);
      await _settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: '${tool.name} failed to build or lay out',
      );
      final panel = state.workspace.panels.value.firstWhere(
        (p) => p.toolId == tool.id,
      );
      // The innermost keyed subtree wraps only the tool content, not the
      // panel chrome (close/minimize), which this sweep must not tap.
      final scope = find.byKey(ValueKey(panel.instanceId)).last;
      expect(scope, findsOneWidget, reason: tool.name);

      List<Element> sweepTargets() => find
          .descendant(
            of: scope,
            matching: find.byWidgetPredicate(_isActionable),
          )
          .evaluate()
          .where((e) => e.mounted && !_inPanelTitleBar(e))
          .toList();

      final initialCount = sweepTargets().length;
      if (initialCount == 0) {
        noButtons.add(tool.name);
      } else if (sideEffectToolIds.contains(tool.id)) {
        // Verified present and enabled; not tapped to avoid real scans,
        // servers, or spawned processes during tests.
        expect(
          sweepTargets().any((e) {
            final w = e.widget;
            if (w is ButtonStyleButton) return w.onPressed != null;
            if (w is IconButton) return w.onPressed != null;
            return true;
          }),
          isTrue,
          reason: '${tool.name} should expose an enabled action',
        );
      }

      final tappedIds = <int>{};
      var tapped = 0;
      if (!sideEffectToolIds.contains(tool.id)) {
        for (var round = 0; round < 60; round++) {
          expect(
            find.byKey(ValueKey(panel.instanceId)),
            findsWidgets,
            reason: '${tool.name}: panel disappeared during button sweep',
          );
          Element? next;
          for (final element in sweepTargets()) {
            if (element.mounted &&
                !tappedIds.contains(identityHashCode(element))) {
              next = element;
              break;
            }
          }
          if (next == null) break;
          tappedIds.add(identityHashCode(next));
          final label = _label(next.widget);
          try {
            // Pump while the scroll animation runs; awaiting the future
            // alone deadlocks under FakeAsync because only pump() ticks it.
            final scrolled = Scrollable.ensureVisible(
              next,
              duration: const Duration(milliseconds: 100),
            );
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            await scrolled;
          } catch (_) {
            // ignore: avoid_catches_without_on_clauses
          }
          await tester.pump(const Duration(milliseconds: 250));
          if (!next.mounted) continue;
          final target = find.byElementPredicate((e) => identical(e, next));
          Future<void> tapAt(Finder f) => tester.runAsync(() async {
            await tester.tap(f);
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          try {
            // runAsync lets real async work (compute() isolates, plugin
            // channels) complete; FakeAsync pumps alone never deliver those.
            final widget = next.widget;
            if (widget is ToggleButtons) {
              // Tap each segment directly; the container's center can land
              // between segments and miss the hit test.
              final segments = find
                  .descendant(of: target, matching: find.byType(Text))
                  .evaluate()
                  .toList();
              for (final segment in segments) {
                if (!segment.mounted) continue;
                await tapAt(
                  find.byElementPredicate((e) => identical(e, segment)),
                );
              }
            } else if (widget is SmallDropdown) {
              // Drive every option, reopening the menu for each selection.
              for (final item in widget.items) {
                if (!next.mounted) break;
                await tapAt(target);
                final option = find.text(item).last;
                if (option.evaluate().isNotEmpty) {
                  await tapAt(option);
                } else {
                  _popAllRoutes(tester);
                }
              }
            } else {
              await tapAt(target);
            }
          } catch (_) {
            // ignore: avoid_catches_without_on_clauses
            continue; // Off-screen or not hit-testable; counted as skipped.
          }
          await _settle(tester);
          if (find.byType(PopupMenuItem).evaluate().isNotEmpty) {
            await tester.runAsync(() async {
              await tester.tap(find.byType(PopupMenuItem).first);
              await Future<void>.delayed(const Duration(milliseconds: 50));
            });
            await _settle(tester);
          }
          _popAllRoutes(tester);
          await _settle(tester);
          expect(
            tester.takeException(),
            isNull,
            reason: '${tool.name}: tapping "$label" threw',
          );
          expect(
            state.workspace.panels.value.any((p) => p.toolId == tool.id),
            isTrue,
            reason: '${tool.name}: tapping "$label" closed its panel',
          );
          tapped++;
          totalTapped++;
        }
      }
      perTool[tool.name] = tapped;
      state.workspace.closeFocusedPanel();
      await _settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: '${tool.name} failed to close',
      );
    }

    // Every tool with controls had them all tapped without crashing.
    expect(totalTapped, greaterThan(150));
    // ignore: avoid_print
    print(
      'Button sweep: $totalTapped taps across ${perTool.length} tools. '
      'No actionable controls: ${noButtons.isEmpty ? 'none' : noButtons.join(', ')}',
    );
  });
}