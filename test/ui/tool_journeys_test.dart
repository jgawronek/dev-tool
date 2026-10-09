import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/app.dart';
import 'package:dev_tool/registry/tool_registry.dart';
import 'package:dev_tool/state/tool_state.dart';
import 'package:dev_tool/ui/sidebar.dart';
import 'package:dev_tool/ui/widgets.dart';

class _AppJourney {
  _AppJourney(this.tester, this.state);

  final WidgetTester tester;
  final ToolState state;

  static Future<_AppJourney> launch(
    WidgetTester tester, {
    Size size = const Size(1450, 950),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = ToolState.inMemory();
    await tester.pumpWidget(DevToolApp(state: state));
    await _settle(tester);
    return _AppJourney(tester, state);
  }

  static Future<void> _settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> searchAndOpen(String name, String id) async {
    final field = find.widgetWithText(TextField, 'Search tools');
    await tester.enterText(field, name);
    await _settle(tester);
    final result = find.descendant(
      of: find.byType(Sidebar),
      matching: find.text(name),
    );
    expect(result, findsWidgets);
    await tester.tap(result.last);
    await _settle(tester);
    expect(
      state.workspace.panels.value.any((panel) => panel.toolId == id),
      isTrue,
    );
  }

  Future<void> typeInto(String hint, String text) async {
    // re_editor's CodeEditor is not an EditableText. Mirror a user edit via
    // EditorPane's controller and change callback, as the existing tests do.
    final pane = find.byWidgetPredicate(
      (widget) => widget is EditorPane && widget.placeholder == hint,
    );
    expect(pane, findsOneWidget);
    final editor = tester.widget<EditorPane>(pane);
    editor.controller!.text = text;
    editor.onChanged?.call(text);
    await _settle(tester);
  }

  String output(String hint) {
    final pane = tester.widget<EditorPane>(
      find.byWidgetPredicate(
        (widget) => widget is EditorPane && widget.placeholder == hint,
      ),
    );
    return pane.controller!.text;
  }

  Future<void> chooseDropdown(String containsItem, String item) async {
    final dropdown = find.byWidgetPredicate(
      (widget) =>
          widget is SmallDropdown && widget.items.contains(containsItem),
    );
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await _settle(tester);
    await tester.tap(find.text(item).last);
    await _settle(tester);
  }

  Future<void> editorMenu(String hint, String item) async {
    final pane = find.byWidgetPredicate(
      (widget) => widget is EditorPane && widget.placeholder == hint,
    );
    await tester.tapAt(tester.getCenter(pane), buttons: kSecondaryMouseButton);
    await _settle(tester);
    await tester.tap(find.text(item).last);
    await _settle(tester);
  }
}

void main() {
  testWidgets('every registered tool opens and builds in the workspace', (
    tester,
  ) async {
    final app = await _AppJourney.launch(tester);
    for (final tool in ToolRegistry.tools) {
      app.state.workspace.openTool(tool.id);
      await _AppJourney._settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: '${tool.name} failed to build',
      );
      app.state.workspace.closeFocusedPanel();
      await _AppJourney._settle(tester);
    }
  });

  testWidgets(
    'sidebar search → hash verifier → mismatch → correction → clear',
    (tester) async {
      final app = await _AppJourney.launch(tester);
      await app.searchAndOpen('Hash/HMAC Verifier', 'hash_verifier');
      await app.typeInto('Text to verify (UTF-8)', 'abc');
      final expected = find.widgetWithText(TextField, 'Expected hex digest');
      await tester.enterText(expected, '0' * 64);
      await _AppJourney._settle(tester);
      expect(app.output('Digest verification'), contains('No match'));
      await tester.enterText(
        expected,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      await _AppJourney._settle(tester);
      expect(app.output('Digest verification'), contains('Match'));
      await app.editorMenu('Text to verify (UTF-8)', 'Clear');
      expect(app.output('Digest verification'), isEmpty);
    },
  );

  testWidgets('sidebar search → URL query add and sort → copyable output', (
    tester,
  ) async {
    final app = await _AppJourney.launch(tester);
    await app.searchAndOpen('URL Query Editor', 'query_editor');
    await app.typeInto(
      'URL or query string',
      'https://example.com/path?z=1&z=2#frag',
    );
    expect(app.output('Edited URL or query'), contains('z=1&z=2#frag'));
    await app.chooseDropdown('Inspect', 'Add');
    await tester.enterText(
      find.widgetWithText(TextField, 'Parameter name'),
      'a',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Value'),
      'two words',
    );
    await _AppJourney._settle(tester);
    expect(
      app.output('Edited URL or query'),
      'https://example.com/path?z=1&z=2&a=two+words#frag',
    );
    await app.chooseDropdown('Inspect', 'Sort');
    expect(
      app.output('Edited URL or query'),
      'https://example.com/path?z=1&z=2#frag',
    );
    expect(find.byTooltip('Copy'), findsWidgets);
  });

  testWidgets(
    'sidebar search → CSV filter and sort → malformed input → recovery',
    (tester) async {
      final app = await _AppJourney.launch(tester);
      await app.searchAndOpen('CSV Inspector', 'csv_inspector');
      await app.typeInto(
        'CSV with header row',
        'id,name\n10,Ada\n2,Bob\n1,Anna',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Filter contains'),
        'a',
      );
      await _AppJourney._settle(tester);
      await app.chooseDropdown('None', 'id');
      expect(app.output('Filtered CSV'), 'id,name\n1,Anna\n10,Ada');
      await app.typeInto('CSV with header row', 'id,name\n1');
      expect(app.output('Filtered CSV'), isEmpty);
      expect(find.textContaining('Row 2'), findsWidgets);
      await app.typeInto('CSV with header row', 'id,name\n2,Ada');
      expect(app.output('Filtered CSV'), contains('2,Ada'));
    },
  );

  testWidgets(
    'sidebar search → date offset calculation → invalid input → correction',
    (tester) async {
      final app = await _AppJourney.launch(tester);
      await app.searchAndOpen('Date/Time Difference', 'date_difference');
      await tester.enterText(
        find.widgetWithText(TextField, 'Start (ISO 8601 + zone)'),
        '2024-01-01T00:00:00Z',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'End (ISO 8601 + zone)'),
        '2023-12-31T19:00:00-05:00',
      );
      await _AppJourney._settle(tester);
      expect(
        app.output('Elapsed time and UTC instants'),
        contains('Same instant'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'End (ISO 8601 + zone)'),
        'invalid',
      );
      await _AppJourney._settle(tester);
      expect(app.output('Elapsed time and UTC instants'), isEmpty);
      expect(find.textContaining('timezone'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextField, 'End (ISO 8601 + zone)'),
        '2024-01-03T00:00:00Z',
      );
      await _AppJourney._settle(tester);
      expect(app.output('Elapsed time and UTC instants'), contains('2 days'));
    },
  );

  testWidgets('JSON operations remain accessible through the real sidebar', (
    tester,
  ) async {
    final app = await _AppJourney.launch(tester);
    await app.searchAndOpen('JSON Format/Validate', 'json_format_validate');
    await app.typeInto('Paste JSON...', '{"z":[3,1],"a":true}');
    await app.chooseDropdown('Sort arrays', 'Sort arrays');
    expect(jsonDecode(app.output('Formatted JSON...')), {
      'z': [1, 3],
      'a': true,
    });
    await app.chooseDropdown('Sort arrays', 'Minify');
    expect(app.output('Formatted JSON...'), '{"z":[3,1],"a":true}');
  });

  for (final size in [const Size(1100, 720), const Size(900, 650)]) {
    testWidgets(
      'tools lay out without overflow at ${size.width}×${size.height}',
      (tester) async {
        final app = await _AppJourney.launch(tester, size: size);
        for (final tool in const [
          ('Hash/HMAC Verifier', 'hash_verifier'),
          ('URL Query Editor', 'query_editor'),
          ('CSV Inspector', 'csv_inspector'),
          ('Date/Time Difference', 'date_difference'),
        ]) {
          await app.searchAndOpen(tool.$1, tool.$2);
          expect(tester.takeException(), isNull, reason: '${tool.$1} at $size');
        }
      },
    );
  }
}
