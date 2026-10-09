import 'package:flutter/material.dart' show Size, TextField;
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/csv_inspector_service.dart';
import 'package:dev_tool/ui/widgets.dart';

import '../helpers/tool_harness.dart';

void main() {
  test('quoted commas, escaped quotes and newlines round-trip', () {
    const input = 'id,note\n1,"a,b"\n2,"say ""hi""\nagain"';
    final result = inspectCsv(input);
    expect(result.error, isNull);
    expect(result.rowCount, 2);
    expect(result.output, input);
  });

  test('filters selected column case-insensitively and sorts numeric rows', () {
    const input = 'id,name\n10,Ada\n2,Bob\n1,Anna';
    final result = inspectCsv(
      input,
      filterColumn: 'name',
      filterText: 'a',
      sortColumn: 'id',
    );
    expect(result.output, 'id,name\n1,Anna\n10,Ada');
    expect(result.matchedCount, 2);
    expect(
      inspectCsv(input, sortColumn: 'id', descending: true).output,
      'id,name\n10,Ada\n2,Bob\n1,Anna',
    );
  });

  test('rejects ragged, duplicate-column and malformed quoted input', () {
    expect(inspectCsv('a,b\n1').error, contains('Row 2'));
    expect(inspectCsv('a,a\n1,2').error, contains('unique'));
    expect(inspectCsv('a\n"unfinished').error, contains('Unclosed'));
    expect(inspectCsv('a\n"one"oops').error, contains('Unexpected'));
  });

  testWidgets('CSV inspector filters and sorts from controls', (tester) async {
    final h = ToolHarness(tester);
    await h.open('csv_inspector', surface: const Size(1450, 950));
    await h.enter(
      'CSV with header row',
      text: 'id,name\n10,Ada\n2,Bob\n1,Anna',
    );
    expect(h.text('Filtered CSV'), contains('10,Ada'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Filter contains'),
      'a',
    );
    await h.settle();
    expect(h.text('Filtered CSV'), isNot(contains('2,Bob')));
    final dropdown = find.byWidgetPredicate(
      (widget) => widget is SmallDropdown && widget.items.contains('None'),
    );
    await tester.tap(dropdown);
    await h.settle();
    await h.tap('id');
    expect(h.text('Filtered CSV'), 'id,name\n1,Anna\n10,Ada');
  });
}
