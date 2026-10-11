import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/ui/widgets.dart';

/// Pumps a single [EditorPane] with the given actions and overlay.
Future<void> pumpPane(
  WidgetTester tester, {
  required List<Widget> actions,
  Widget? overlay,
  bool showHeader = false,
  VoidCallback? copyAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 600,
          child: EditorPane(
            label: 'Output',
            actions: actions,
            overlay: overlay,
            copyAction: copyAction,
            showHeader: showHeader,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('Copy action is honoured', () {
    // Regression: `_isHiddenEditorAction` listed 'Copy', so the action was
    // dropped before it ever reached the header. Roughly 30 tools passed a
    // Copy ToolButton and rendered no way to copy their output.
    testWidgets('a Copy ToolButton renders a copy affordance', (tester) async {
      await pumpPane(
        tester,
        actions: [ToolButton(label: 'Copy', onPressed: () {})],
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping it invokes the callback', (tester) async {
      var taps = 0;
      await pumpPane(
        tester,
        actions: [ToolButton(label: 'Copy', onPressed: () => taps++)],
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
        ),
      );
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('it renders alongside other actions', (tester) async {
      await pumpPane(
        tester,
        actions: [
          ToolButton(label: 'Copy', onPressed: () {}),
          ToolButton(label: 'Use as input', onPressed: () {}),
        ],
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
        ),
        findsOneWidget,
      );
      expect(find.text('Use as input'), findsOneWidget);
    });

    testWidgets('an explicit copyAction still takes precedence', (
      tester,
    ) async {
      var explicit = 0;
      var fromButton = 0;
      await pumpPane(
        tester,
        actions: [ToolButton(label: 'Copy', onPressed: () => fromButton++)],
        copyAction: () => explicit++,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
        ),
      );
      await tester.pump();
      expect(explicit, 1);
      expect(fromButton, 0);
    });

    testWidgets('it works when a header is shown', (tester) async {
      await pumpPane(
        tester,
        actions: [ToolButton(label: 'Copy', onPressed: () {})],
        showHeader: true,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
        ),
        findsOneWidget,
      );
    });
  });

  group('overlay no longer swallows actions', () {
    // Regression: supplying an overlay replaced the action strip entirely, so
    // any tool passing both silently lost its buttons.
    testWidgets('actions survive alongside a custom overlay', (tester) async {
      await pumpPane(
        tester,
        actions: [ToolButton(label: 'Use as input', onPressed: () {})],
        overlay: const Text('custom overlay'),
      );
      expect(find.text('custom overlay'), findsOneWidget);
      expect(find.text('Use as input'), findsOneWidget);
    });

    testWidgets('Copy survives alongside a custom overlay', (tester) async {
      var taps = 0;
      await pumpPane(
        tester,
        actions: [ToolButton(label: 'Copy', onPressed: () => taps++)],
        overlay: const Text('custom overlay'),
      );
      expect(find.text('custom overlay'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
        ),
      );
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('an overlay with no actions is untouched', (tester) async {
      await pumpPane(
        tester,
        actions: const [],
        overlay: const Text('custom overlay'),
      );
      expect(find.text('custom overlay'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
        ),
        findsNothing,
      );
    });
  });

  group('Legacy Sample and Clear actions are hidden', () {
    testWidgets('they do not appear in the action strip', (tester) async {
      await pumpPane(
        tester,
        actions: [
          ToolButton(label: 'Sample', onPressed: () {}),
          ToolButton(label: 'Clear', onPressed: () {}),
        ],
      );
      // Samples are offered by the tool heading; editors have no Clear button.
      expect(find.text('Clear'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
        ),
        findsNothing,
      );
    });
  });
}
