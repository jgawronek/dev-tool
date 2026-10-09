import 'package:flutter/material.dart' show Size, TextField;
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/query_editor_service.dart';

import '../helpers/tool_harness.dart';

void main() {
  test('preserves duplicate parameters and fragment in a URL', () {
    final result = editQuery('https://example.com/a?tag=one&tag=two#section');
    expect(result.output, 'https://example.com/a?tag=one&tag=two#section');
    expect(result.fields.map((field) => field.value), ['one', 'two']);
  });

  test('preserves bare query form, duplicates, and plus-encoded spaces', () {
    expect(editQuery('?x=one&x=two#part').output, '?x=one&x=two#part');
    expect(editQuery('x=a+b&x=c%20d').fields.map((field) => field.value), [
      'a b',
      'c d',
    ]);
    expect(
      editQuery('/path?x=1#frag', edit: QueryEdit.remove, key: 'x').output,
      '/path?#frag',
    );
  });

  test('add, replace, remove and sort work on query-only input', () {
    expect(
      editQuery('b=2&a=1', edit: QueryEdit.add, key: 'a', value: '3').output,
      'b=2&a=1&a=3',
    );
    expect(
      editQuery(
        'b=2&a=1&a=3',
        edit: QueryEdit.replace,
        key: 'a',
        value: 'x',
      ).output,
      'b=2&a=x',
    );
    expect(
      editQuery('b=2&a=1&a=3', edit: QueryEdit.remove, key: 'a').output,
      'b=2',
    );
    expect(
      editQuery('b=2&a=3&a=1', edit: QueryEdit.sort).output,
      'a=1&a=3&b=2',
    );
  });

  test('encodes names and values and leaves URL path untouched', () {
    final result = editQuery(
      'https://example.com/a%20b?x=1#part',
      edit: QueryEdit.add,
      key: 'my key',
      value: 'a & b',
    );
    expect(result.output, 'https://example.com/a%20b?x=1&my+key=a+%26+b#part');
  });

  test('reports missing parameter names and malformed escapes', () {
    expect(
      editQuery('a=1', edit: QueryEdit.add).error,
      contains('parameter name'),
    );
    expect(editQuery('a=%GG').error, contains('percent escape'));
    expect(editQuery(' ').error, contains('Enter a URL'));
  });

  testWidgets('query editor updates the URL when a parameter is added', (
    tester,
  ) async {
    final h = ToolHarness(tester);
    await h.open('query_editor', surface: const Size(1450, 950));
    await h.enter('URL or query string', text: 'https://example.com/?a=1');
    await h.tap('Inspect');
    await h.tap('Add');
    await tester.enterText(
      find.widgetWithText(TextField, 'Parameter name'),
      'b',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Value'), 'two');
    await h.settle();
    expect(h.text('Edited URL or query'), 'https://example.com/?a=1&b=two');
  });
}
