import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dev_tool/app.dart';
import 'package:dev_tool/registry/tool_registry.dart';
import 'package:dev_tool/state/tool_state.dart';
import 'package:dev_tool/ui/widgets.dart';

import 'functionality_audit_test.dart' as audit;

// These actions need a configured external target, model, or native process.
// Record the gap rather than presenting an unexecuted action as a pass.
const externalTools = {
  'port_scanner',
  'network_scanner',
  'firewall_fingerprint',
  'subdomain_finder',
  'subdomain_takeover',
  'local_server',
  'offline_llm',
  'antibot_detection',
  'url_parser',
};

void main() {
  for (final tool in ToolRegistry.tools) {
    testWidgets('control audit: ${tool.id}', (tester) async {
      tester.view.physicalSize = const Size(2560, 1640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      String clipboard = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            if (call.method == 'Clipboard.getData') return {'text': clipboard};
            return null;
          });
      final state = ToolState.inMemory();
      state.sidebarWidth.value = 250;
      state.workspace.openTool(tool.id);
      await tester.pumpWidget(DevToolApp(state: state));
      final records = <Map<String, Object?>>[];
      final errors = <String>[];
      void drain(String action) {
        Object? error;
        while ((error = tester.takeException()) != null) {
          errors.add('$action: $error');
        }
      }

      await audit.settle(tester);
      drain('open');
      final sample = find.widgetWithText(OutlinedButton, 'Load sample');
      if (sample.evaluate().isNotEmpty) {
        await tester.tap(sample.first);
        await audit.settle(tester);
        drain('sample');
      }
      Finder scope() =>
          find.byKey(ValueKey(state.workspace.focusedPanel!.instanceId)).last;
      List<Element> targets() => find
          .descendant(
            of: scope(),
            matching: find.byWidgetPredicate(
              (w) =>
                  (w is ButtonStyleButton &&
                      w.runtimeType.toString() != '_IconButtonM3') ||
                  w is IconButton ||
                  w is Checkbox ||
                  w is Switch ||
                  w is SmallDropdown ||
                  w is ToggleButtons ||
                  w is TextField,
            ),
          )
          .evaluate()
          .toList();
      final inputPanes = tester
          .widgetList<EditorPane>(find.byType(EditorPane))
          .where((pane) => !pane.readOnly && pane.controller != null)
          .toList();
      for (final pane in inputPanes) {
        final original = pane.controller!.text;
        for (final value in ['invalid-input-!?', '', original]) {
          pane.controller!.text = value;
          pane.onChanged?.call(value);
          await audit.settle(tester);
          drain('${pane.label} editor input ${jsonEncode(value)}');
        }
        records.add({
          'control': 'EditorPane:${pane.label}:${pane.placeholder}',
          'status': 'editor input robustness checked',
          'values': ['invalid-input-!?', '', original],
          'onChangedPresent': pane.onChanged != null,
        });
      }
      final handled = <String>{};
      // Re-discover after each update so conditionally revealed controls count.
      for (var round = 0; round < 120; round++) {
        Element? next;
        String key = '';
        final counts = <String, int>{};
        for (final e in targets()) {
          final w = e.widget;
          String label;
          if (w is ButtonStyleButton) {
            label = audit.textLabel(w.child);
          } else if (w is IconButton) {
            label = w.tooltip ?? audit.textLabel(w.icon);
          } else if (w is TextField) {
            label = w.decoration?.labelText ?? w.decoration?.hintText ?? '';
          } else if (w is SmallDropdown) {
            label = w.items.join('|');
          } else if (w is ToggleButtons) {
            label = w.children.map(audit.textLabel).join('|');
          } else {
            label = w.runtimeType.toString();
          }
          final base = '${w.runtimeType}:$label';
          final n = counts.update(base, (v) => v + 1, ifAbsent: () => 0);
          final candidate = '$base#$n';
          if (!handled.contains(candidate)) {
            next = e;
            key = candidate;
            break;
          }
        }
        if (next == null) break;
        handled.add(key);
        final w = next.widget;
        final record = <String, Object?>{'control': key};
        records.add(record);
        final external = externalTools.contains(tool.id);
        try {
          if (w is TextField) {
            if (w.readOnly || w.enabled == false) {
              record['status'] = 'read-only/disabled';
              continue;
            }
            final original = w.controller?.text ?? '';
            // Invalid and empty input must not crash; correctness is checked by
            // separate known-answer tests. Restore before later actions.
            final finder = find.byElementPredicate((e) => identical(e, next));
            for (final value in ['invalid-input-!?', '', original]) {
              if (!next.mounted) break;
              await tester.enterText(finder, value);
              await audit.settle(tester);
              drain('$key input ${jsonEncode(value)}');
            }
            record['status'] = 'input robustness checked';
            record['values'] = ['invalid-input-!?', '', original];
          } else if (w is SmallDropdown) {
            if (w.onChanged == null) {
              record['status'] = 'disabled';
              continue;
            }
            final checked = <String>[];
            for (final value in w.items) {
              if (!next.mounted) break;
              final current = next.widget as SmallDropdown;
              current.onChanged?.call(value);
              await audit.settle(tester);
              drain('$key select $value');
              checked.add(value);
            }
            record['status'] = 'option callbacks exercised';
            record['options'] = checked;
          } else if (w is ToggleButtons) {
            if (w.onPressed == null) {
              record['status'] = 'disabled';
              continue;
            }
            for (var i = 0; i < w.children.length; i++) {
              if (!next.mounted) break;
              (next.widget as ToggleButtons).onPressed?.call(i);
              await audit.settle(tester);
              drain('$key segment $i');
            }
            record['status'] = 'segment callbacks exercised';
          } else if (w is Checkbox || w is Switch) {
            final enabled = w is Checkbox
                ? w.onChanged != null
                : (w as Switch).onChanged != null;
            if (!enabled) {
              record['status'] = 'disabled';
              continue;
            }
            if (w is Checkbox) {
              w.onChanged?.call(!(w.value ?? false));
            } else {
              final s = w as Switch;
              s.onChanged?.call(!s.value);
            }
            await audit.settle(tester);
            drain(key);
            record['status'] = 'toggle callback exercised';
          } else {
            final callback = w is ButtonStyleButton
                ? w.onPressed
                : (w as IconButton).onPressed;
            if (callback == null) {
              record['status'] = 'disabled in this state';
              continue;
            }
            final externalAction =
                external &&
                RegExp(
                  r'Send|Find known|Scan|Recon|Detect LAN|Fingerprint|Start|Run|Download|Refresh',
                ).hasMatch(key);
            if (externalAction) {
              record['status'] = 'deferred: native/network/model dependency';
              continue;
            }
            final target = find.byElementPredicate((e) => identical(e, next));
            try {
              await tester.ensureVisible(target);
              await tester.pump();
            } catch (_) {
              // Record callback-only coverage for controls outside viewports.
            }
            final hit = target.hitTestable();
            if (hit.evaluate().isNotEmpty) {
              await tester.tap(hit.first);
            } else {
              callback();
            }
            await audit.settle(tester);
            drain(key);
            record['status'] = hit.evaluate().isNotEmpty
                ? 'button tapped'
                : 'button callback exercised (not hit-testable)';
            if (key.toLowerCase().contains('copy')) {
              record['clipboard'] = clipboard;
            }
          }
          tester
              .state<NavigatorState>(find.byType(Navigator).first)
              .popUntil((r) => r.isFirst);
          await audit.settle(tester);
          drain('$key close dialog');
        } catch (error) {
          record['status'] = 'exception';
          record['error'] = error.toString();
          errors.add('$key: $error');
        }
      }
      // ignore: avoid_print
      print(
        'CONTROL_AUDIT ${jsonEncode({'tool': tool.id, 'records': records, 'errors': errors, 'outputs': audit.editors(tester), 'coverageKind': 'callbacks/input robustness; not correctness proof'})}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await audit.settle(tester);
      drain('dispose');
      expect(errors, isEmpty, reason: tool.name);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
