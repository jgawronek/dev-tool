import 'dart:convert';

import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/json_operations_service.dart';
import 'package:dev_tool/ui/tools/common/shared.dart';
import 'package:dev_tool/ui/widgets.dart';

import '../helpers/tool_harness.dart';

void main() {
  test('default mode prettifies and validates every JSON root type', () {
    final cases = <String, Object?>{
      '{"nested":{"n":1}}': {
        'nested': {'n': 1},
      },
      '[1,true,null]': [1, true, null],
      '"text"': 'text',
      '42': 42,
      'false': false,
      'null': null,
    };
    for (final entry in cases.entries) {
      final result = formatJsonSync(entry.key, '    ');
      expect(result.error, isNull, reason: entry.key);
      expect(jsonDecode(result.output!), entry.value, reason: entry.key);
      expect(result.summary, isNotEmpty);
    }
    expect(
      formatJsonSync('{"a":{"b":1}}', '    ').output,
      '{\n    "a": {\n        "b": 1\n    }\n}',
    );
  });

  test('minify preserves the decoded value and removes formatting', () {
    const source = '{ "url": "https://example.com/a b", "items": [1, 2] }';
    final output = formatJsonSync(source, '  ', JsonOperation.minify);
    expect(output.error, isNull);
    expect(output.output, '{"url":"https://example.com/a b","items":[1,2]}');
    expect(jsonDecode(output.output!), jsonDecode(source));
  });

  test('stringify wraps valid JSON as a parseable JSON string', () {
    final result = formatJsonSync(
      '{"a":"line\\nnext"}',
      '  ',
      JsonOperation.stringify,
    );
    expect(jsonDecode(result.output!), '{"a":"line\\nnext"}');
    expect(jsonDecode(jsonDecode(result.output!) as String), {
      'a': 'line\nnext',
    });
  });

  test('stringify and escape handle primitive JSON values', () {
    expect(
      formatJsonSync('null', '  ', JsonOperation.stringify).output,
      '"null"',
    );
    expect(formatJsonSync('true', '  ', JsonOperation.escape).output, 'true');
    final stringified = formatJsonSync(
      r'"a\"b"',
      '  ',
      JsonOperation.stringify,
    );
    expect(jsonDecode(jsonDecode(stringified.output!) as String), 'a"b');
  });

  test('escape emits escaped JSON text without enclosing quotes', () {
    const source = '{"message":"a\\nb"}';
    final result = formatJsonSync(source, '  ', JsonOperation.escape);
    expect(result.output, isNot(startsWith('"')));
    expect(jsonDecode('"${result.output}"'), jsonEncode(jsonDecode(source)));
  });

  test('XML conversion preserves arrays, null and invalid tag names', () {
    final result = formatJsonSync(
      r'{"invalid key":"<&\"", "list":[1,null,{"ok":true}]}',
      '  ',
      JsonOperation.xml,
    );
    expect(result.error, isNull);
    expect(result.output, contains('<entry key="invalid key">'));
    expect(result.output, contains('&lt;&amp;&quot;'));
    expect(result.output, contains('<item/>'));
    expect(result.output, contains('<ok>true</ok>'));
  });

  test('XML conversion keeps unusual keys and removes forbidden controls', () {
    final result = formatJsonSync(
      '{"xmlThing":"a\\u0001b","space key":2,"":"empty"}',
      '  ',
      JsonOperation.xml,
    );
    expect(result.error, isNull);
    expect(result.output, contains('<entry key="xmlThing">'));
    expect(result.output, contains('<entry key="space key">'));
    expect(result.output, contains('<entry key="">'));
    expect(result.output, isNot(contains('\u0001')));
    expect(result.output, contains('\uFFFD'));
  });

  test('XML emits a single root for primitive and empty values', () {
    expect(
      formatJsonSync('null', '  ', JsonOperation.xml).output,
      contains('<root/>'),
    );
    expect(
      formatJsonSync('false', '  ', JsonOperation.xml).output,
      contains('<root>false</root>'),
    );
    expect(
      formatJsonSync('[]', '  ', JsonOperation.xml).output,
      contains('<root>\n</root>'),
    );
    expect(
      formatJsonSync('{}', '  ', JsonOperation.xml).output,
      contains('<root>\n</root>'),
    );
  });

  test('XML escapes attribute values and text independently', () {
    final outcome = formatJsonSync(
      r'{"bad<key":"A & B > C", "a\"b": "x\u0027y"}',
      '  ',
      JsonOperation.xml,
    );
    expect(outcome.error, isNull);
    expect(outcome.output, contains('key="bad&lt;key"'));
    expect(outcome.output, contains('A &amp; B &gt; C'));
    expect(outcome.output, contains('key="a&quot;b"'));
    expect(outcome.output, contains('x&apos;y'));
  });

  test(
    'sort keys alphabetically at every object depth without sorting arrays',
    () {
      final result = formatJsonSync(
        '{"z":{"b":1,"a":2},"a":[{"d":3,"c":4},2,1]}',
        '  ',
        JsonOperation.sortKeys,
      );
      expect(
        result.output!.indexOf('"a"'),
        lessThan(result.output!.indexOf('"z"')),
      );
      expect(
        result.output,
        contains(
          '[\n    {\n      "c": 4,\n      "d": 3\n    },\n    2,\n    1\n  ]',
        ),
      );
    },
  );

  test('sort arrays numerically and recursively, preserving object keys', () {
    final result = formatJsonSync(
      '{"z":[10,2,1],"nested":{"values":["b","a"]}}',
      '  ',
      JsonOperation.sortArrays,
    );
    expect(jsonDecode(result.output!), {
      'z': [1, 2, 10],
      'nested': {
        'values': ['a', 'b'],
      },
    });
    expect(
      result.output!.indexOf('"z"'),
      lessThan(result.output!.indexOf('"nested"')),
    );
  });

  test(
    'sort arrays handles booleans, nulls, duplicates, negatives, and empty arrays',
    () {
      final result = formatJsonSync(
        '{"flags":[true,false,true],"numbers":[-2,3.5,-2,0],"empty":[],"nulls":[null,null]}',
        '  ',
        JsonOperation.sortArrays,
      );
      expect(result.error, isNull);
      expect(jsonDecode(result.output!), {
        'flags': [false, true, true],
        'numbers': [-2, -2, 0, 3.5],
        'empty': <Object?>[],
        'nulls': [null, null],
      });
    },
  );

  test(
    'array sorting reports mixed and object arrays rather than guessing',
    () {
      for (final source in ['[1,"2"]', '[{"x":1},{"x":2}]']) {
        final outcome = formatJsonSync(source, '  ', JsonOperation.sortArrays);
        expect(outcome.output, isNull);
        expect(outcome.error, contains('one primitive type'));
      }
    },
  );

  test(
    'invalid input retains location-aware JSON validation in every mode',
    () {
      for (final operation in JsonOperation.values) {
        final outcome = formatJsonSync('{"a":}', '  ', operation);
        expect(outcome.output, isNull);
        expect(
          outcome.error,
          contains('Line 1, column'),
          reason: operation.label,
        );
      }
    },
  );

  test('isolate worker uses the selected operation', () {
    final result = formatJsonWorker((
      ' {"z": [3, 1]} ',
      '  ',
      JsonOperation.sortArrays,
    ));
    expect(jsonDecode(result.output!), {
      'z': [1, 3],
    });
  });

  test(
    'empty session clears output and validation status in every mode',
    () async {
      final session = JsonToolSession();
      addTearDown(session.dispose);
      for (final operation in JsonOperation.values) {
        session.operation = operation;
        session.input.text = '{"n":1}';
        await session.format();
        expect(session.status.value.isValid, isTrue, reason: operation.label);
        session.input.clear();
        await session.format();
        expect(session.output.text, isEmpty, reason: operation.label);
        expect(
          session.status.value.hasMessage,
          isFalse,
          reason: operation.label,
        );
      }
    },
  );

  testWidgets('JSON panel changes operation and recomputes live', (
    tester,
  ) async {
    final h = ToolHarness(tester);
    await h.open('json_format_validate', surface: const Size(1450, 950));
    await h.enter('Paste JSON...', text: '{"z": [10, 2], "a": 1}');
    expect(h.text('Formatted JSON...'), contains('"z": ['));

    Future<void> chooseOperation(String label) async {
      final dropdown = find.byWidgetPredicate(
        (widget) =>
            widget is SmallDropdown && widget.items.contains('Sort arrays'),
      );
      await tester.tap(dropdown);
      await h.settle();
      await h.tap(label);
    }

    await chooseOperation('Minify');
    expect(h.text('Formatted JSON...'), '{"z":[10,2],"a":1}');

    await chooseOperation('Sort arrays');
    expect(jsonDecode(h.text('Formatted JSON...')), {
      'z': [2, 10],
      'a': 1,
    });
    await h.enter('Paste JSON...', text: '{"a":}');
    expect(h.text('Formatted JSON...'), isEmpty);
    expect(find.textContaining('Line 1, column'), findsWidgets);
  });

  for (final operation in JsonOperation.values) {
    testWidgets('JSON panel ${operation.label}: input, output, and recovery', (
      tester,
    ) async {
      final h = ToolHarness(tester);
      await h.open('json_format_validate', surface: const Size(1450, 950));

      final dropdown = find.byWidgetPredicate(
        (widget) =>
            widget is SmallDropdown && widget.items.contains('Sort arrays'),
      );
      if (operation != JsonOperation.prettify) {
        await tester.tap(dropdown);
        await h.settle();
        await h.tap(operation.label);
      }

      const source = '{"z":[3,1],"a":"<hi>"}';
      await h.enter('Paste JSON...', text: source);
      expect(h.text('Paste JSON...'), source);
      expect(
        h.text('Formatted JSON...'),
        transformJson(jsonDecode(source), operation, '  '),
      );
      expect(find.textContaining('object'), findsWidgets);

      await h.enter('Paste JSON...', text: '{"broken":}');
      expect(h.text('Formatted JSON...'), isEmpty);
      expect(find.textContaining('Line 1, column'), findsWidgets);

      await h.enter('Paste JSON...', text: source);
      expect(
        h.text('Formatted JSON...'),
        transformJson(jsonDecode(source), operation, '  '),
      );
      await h.enter('Paste JSON...', text: '');
      expect(h.text('Formatted JSON...'), isEmpty);
      expect(
        find.text('Paste or drop JSON to validate and format.'),
        findsWidgets,
      );
    });
  }
}
