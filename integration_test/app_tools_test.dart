import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dev_tool/app.dart';
import 'package:dev_tool/state/tool_state.dart';
import 'package:dev_tool/ui/sidebar.dart';
import 'package:dev_tool/ui/widgets.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> openTool(WidgetTester tester, ToolState state, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  state.searchQuery.value = '';
  await settle(tester);
  final search = find.widgetWithText(TextField, 'Find a tool');
  await tester.tap(search);
  await tester.enterText(search, name);
  await settle(tester);
  final result = find.descendant(
    of: find.byType(Sidebar),
    matching: find.text(name),
  );
  expect(result, findsWidgets, reason: 'Sidebar search should show $name');
  await tester.tap(result.last);
  await settle(tester);
}

Future<void> typeInEditor(
  WidgetTester tester,
  String hint,
  String value,
) async {
  final pane = tester.widget<EditorPane>(
    find.byWidgetPredicate(
      (widget) => widget is EditorPane && widget.placeholder == hint,
    ),
  );
  pane.controller!.text = value;
  pane.onChanged?.call(value);
  await settle(tester);
}

String editorOutput(WidgetTester tester, String hint) => tester
    .widget<EditorPane>(
      find.byWidgetPredicate(
        (widget) => widget is EditorPane && widget.placeholder == hint,
      ),
    )
    .controller!
    .text;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS app opens JSON and verifies SHA-256', (tester) async {
    final state = ToolState.inMemory();
    state.sidebarWidth.value = 250;
    await tester.pumpWidget(DevToolApp(state: state));
    await settle(tester);

    await openTool(tester, state, 'JSON Format/Validate');
    await typeInEditor(tester, 'Paste JSON...', '{"name":"DevUtils"}');
    expect(
      editorOutput(tester, 'Formatted JSON...'),
      contains('"name": "DevUtils"'),
    );

    await openTool(tester, state, 'Hash/HMAC Verifier');
    await typeInEditor(tester, 'Text to verify (UTF-8)', 'abc');
    await tester.enterText(
      find.widgetWithText(TextField, 'Expected hex digest'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    await settle(tester);
    expect(editorOutput(tester, 'Digest verification'), contains('Match'));
  });
}
