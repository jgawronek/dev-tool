import 'package:flutter_test/flutter_test.dart';
import 'package:dev_tool/ui/widgets.dart';
import '../helpers/tool_harness.dart';

void main() {
  testWidgets('diff reorder, duplicates, Unicode, swap, output presentation', (
    tester,
  ) async {
    final h = ToolHarness(tester);
    await h.open('text_diff_checker');
    await h.tap('Lines');
    await h.enter(null, label: 'Input 1', text: 'a\nb\na');
    await h.enter(null, label: 'Input 2', text: 'a\na\nb');
    expect(h.text(null, label: 'Differences'), '- b\n+ b');
    await h.tap('Swap Inputs');
    expect(h.text(null, label: 'Input 1'), 'a\na\nb');
    expect(h.text(null, label: 'Input 2'), 'a\nb\na');
    expect(h.text(null, label: 'Differences'), '- a\n+ a');
    final outputFinder = find.byWidgetPredicate(
      (w) => w is EditorPane && w.label == 'Differences',
    );
    expect(tester.widget<EditorPane>(outputFinder).highlightTheme, isNotNull);
    final dropdown = find.byType(SmallDropdown);
    await tester.tap(dropdown);
    await h.settle();
    await tester.tap(find.text('Plain Text').last);
    await h.settle();
    expect(tester.widget<EditorPane>(outputFinder).highlightTheme, isNull);
    expect(h.text(null, label: 'Differences'), '- a\n+ a');
    await h.tap('Characters');
    await h.enter(null, label: 'Input 1', text: 'é🙂');
    await h.enter(null, label: 'Input 2', text: 'é漢');
    expect(h.text(null, label: 'Differences'), '- 🙂\n+ 漢');
    await h.enter(null, label: 'Input 1', text: '');
    await h.enter(null, label: 'Input 2', text: '');
    expect(h.text(null, label: 'Differences'), isEmpty);
    await h.enter(null, label: 'Input 2', text: ' ');
    expect(h.text(null, label: 'Differences'), '+  ');
    await h.tap('Words');
    await h.enter(null, label: 'Input 1', text: '   a  b ');
    await h.enter(null, label: 'Input 2', text: 'a b');
    expect(h.text(null, label: 'Differences'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
