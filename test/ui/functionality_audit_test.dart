import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dev_tool/app.dart';
import 'package:dev_tool/services/javascript_code_service.dart';

import '../helpers/formatter_engine.dart';
import 'package:dev_tool/registry/tool_registry.dart';
import 'package:dev_tool/state/tool_state.dart';
import 'package:dev_tool/ui/widgets.dart';

// These samples prepare requests/files rather than calculating a local result.
const preparationSamples = {
  'subdomain_finder',
  'port_scanner',
  'firewall_fingerprint',
  'antibot_detection',
  'payload_embedder',
  'text_encryption', // Its sample needs a user-supplied key.
};
const visualResults = {
  'qr_code_reader_generator',
  'html_preview',
  'markdown_preview',
  'uml_class_diagram',
  'string_inspector',
};

String textLabel(Widget? widget) {
  if (widget is Text) return widget.data ?? '';
  if (widget is Row) return widget.children.map(textLabel).join(' ');
  if (widget is Icon) return 'icon:${widget.icon?.codePoint}';
  return '';
}

Map<String, String> editors(WidgetTester tester) => {
  for (final p in tester.widgetList<EditorPane>(find.byType(EditorPane)))
    '${p.label}:${p.placeholder}': p.controller?.text ?? '',
};

Future<void> settle(WidgetTester tester) async {
  // Real async work includes compute isolates; fake time advances debounces.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() => sampleAuditTests();

void sampleAuditTests({bool native = false}) {
  for (final tool in ToolRegistry.tools) {
    testWidgets('sample audit: ${tool.id}', (tester) async {
      tester.view.physicalSize = const Size(2560, 1640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      void stage(String value) {
        if (native && tool.id == 'uml_class_diagram') {
          // ignore: avoid_print
          print('NATIVE_DIAGRAM_STAGE $value');
        }
      }

      if (native) {
        await const MethodChannel(
          'devutils/testing',
        ).invokeMethod<void>('activate');
      }
      stage('warm');
      if (!native) installFormatterChannel();
      await tester.runAsync(
        () => JavascriptCodeService.process('const warm = 1;', 'Verify'),
      );
      if (!native) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async => null,
            );
      }
      final state = ToolState.inMemory();
      state.sidebarWidth.value = 250;
      state.workspace.openTool(tool.id);
      stage('pumpWidget');
      await tester.pumpWidget(DevToolApp(state: state));
      stage('initial settle');
      await settle(tester);
      final errors = <String>[];
      void drain() {
        Object? error;
        while ((error = tester.takeException()) != null) {
          errors.add(error.toString());
        }
      }

      drain();
      final before = editors(tester);
      final fieldsBefore = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      final sample = find.widgetWithText(OutlinedButton, 'Load sample');
      final result = <String, Object?>{
        'tool': tool.id,
        'samplePresent': sample.evaluate().isNotEmpty,
        'before': before,
      };
      if (sample.evaluate().isNotEmpty) {
        final button = tester.widget<OutlinedButton>(sample.first);
        result['sampleEnabled'] = button.onPressed != null;
        if (button.onPressed != null) {
          stage('sample tap');
          await tester.tap(sample.first);
          await settle(tester);
          drain();
          // Password hashing and other isolate work can take longer under a
          // concurrent suite. Wait for an actual output, not just fake time.
          if (!preparationSamples.contains(tool.id) &&
              !visualResults.contains(tool.id)) {
            for (var attempt = 0; attempt < 15; attempt++) {
              final pending = tester
                  .widgetList<EditorPane>(find.byType(EditorPane))
                  .where((p) => p.readOnly)
                  .toList();
              if (pending.isEmpty ||
                  pending.any(
                    (p) => p.controller?.text.trim().isNotEmpty ?? false,
                  )) {
                break;
              }
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 200)),
              );
              await tester.pump();
              drain();
            }
          }
          final after = editors(tester);
          final fieldsAfter = tester
              .widgetList<TextField>(find.byType(TextField))
              .map((f) => f.controller?.text ?? '')
              .toList();
          result['after'] = after;
          result['fieldsAfter'] = fieldsAfter;
          final changed =
              jsonEncode(before) != jsonEncode(after) ||
              jsonEncode(fieldsBefore) != jsonEncode(fieldsAfter);
          result['changed'] = changed;
          final outputs = tester
              .widgetList<EditorPane>(find.byType(EditorPane))
              .where((p) => p.readOnly)
              .map((p) => p.controller?.text ?? '')
              .toList();
          result['outputs'] = outputs;
          if (!changed &&
              !visualResults.contains(tool.id) &&
              tool.id != 'cron_job_parser') {
            errors.add('Load sample did not change any editor or text field.');
          }
          if (!preparationSamples.contains(tool.id) &&
              !visualResults.contains(tool.id) &&
              outputs.isNotEmpty &&
              outputs.every((s) => s.trim().isEmpty)) {
            errors.add('Load sample left all output editors empty.');
          }
          // Repeat the sample to catch one-shot or stale callback registration.
          stage('sample tap');
          await tester.tap(sample.first);
          await settle(tester);
          drain();
          result['repeatOutputs'] = editors(tester);
        }
      }
      final scope = find
          .byKey(ValueKey(state.workspace.focusedPanel!.instanceId))
          .last;
      final controls = find.descendant(
        of: scope,
        matching: find.byWidgetPredicate(
          (w) =>
              w is ButtonStyleButton ||
              w is IconButton ||
              w is Checkbox ||
              w is Switch ||
              w is ToggleButtons ||
              w is SmallDropdown ||
              w is TextField,
        ),
      );
      result['controls'] = controls.evaluate().map((e) {
        final w = e.widget;
        if (w is ButtonStyleButton) {
          return {
            'type': w.runtimeType.toString(),
            'label': textLabel(w.child),
            'enabled': w.onPressed != null,
          };
        }
        if (w is IconButton) {
          return {
            'type': 'IconButton',
            'label': w.tooltip ?? textLabel(w.icon),
            'enabled': w.onPressed != null,
          };
        }
        if (w is Checkbox) {
          return {
            'type': 'Checkbox',
            'value': w.value,
            'enabled': w.onChanged != null,
          };
        }
        if (w is Switch) {
          return {
            'type': 'Switch',
            'value': w.value,
            'enabled': w.onChanged != null,
          };
        }
        if (w is SmallDropdown) {
          return {
            'type': 'Dropdown',
            'items': w.items,
            'enabled': w.onChanged != null,
          };
        }
        if (w is ToggleButtons) {
          return {
            'type': 'Segments',
            'labels': w.children.map(textLabel).toList(),
            'enabled': w.onPressed != null,
          };
        }
        final f = w as TextField;
        return {
          'type': 'TextField',
          'label': f.decoration?.labelText ?? f.decoration?.hintText,
          'value': f.controller?.text,
          'readOnly': f.readOnly,
          'enabled': f.enabled ?? true,
        };
      }).toList();
      result['errors'] = errors;
      // Machine-readable evidence remains available even when the assertion fails.
      // ignore: avoid_print
      print('FUNCTIONALITY_AUDIT ${jsonEncode(result)}');
      stage('unmount');
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      drain();
      expect(errors, isEmpty, reason: '${tool.name}: sample/output audit');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
