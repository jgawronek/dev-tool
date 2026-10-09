import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/ui/tools/common/shared.dart';

import '../helpers/tool_harness.dart';

void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body,
) {
  testWidgets(description, (tester) async {
    final h = ToolHarness(tester);
    await h.open(toolId);
    await body(h);
  });
}

/// Types into an [InlineTextField] found by its hint text.
Future<void> enterInline(WidgetTester tester, String hint, String text) async {
  final field = tester.widget<InlineTextField>(
    find.byWidgetPredicate((w) => w is InlineTextField && w.hintText == hint),
  );
  field.controller!.text = text;
  field.onChanged?.call(text);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('YAML ↔ JSON', () {
    const tool = 'yaml_json_converter';

    toolTest('converts a YAML list of maps to JSON', tool, (h) async {
      await h.enter('---\n- item: Super Hoop', text: '- name: Ada\n  age: 36');
      final out = h.text('[]');
      expect(out, contains('"name": "Ada"'));
      expect(out, contains('"age": 36'));
    });

    toolTest('converts nested YAML maps to JSON', tool, (h) async {
      await h.enter(
        '---\n- item: Super Hoop',
        text: 'store:\n  book:\n    - title: T1',
      );
      final out = h.text('[]');
      expect(out, contains('"store"'));
      expect(out, contains('"title": "T1"'));
    });

    toolTest('converts scalars and keeps types', tool, (h) async {
      await h.enter(
        '---\n- item: Super Hoop',
        text: 'count: 42\nflag: true\nname: "x"',
      );
      final out = h.text('[]');
      expect(out, contains('"count": 42'));
      expect(out, contains('"flag": true'));
    });

    toolTest('converts JSON to YAML', tool, (h) async {
      await h.tap('JSON → YAML');
      await h.enter('{"store": {"book": []}}', text: '{"a": 1, "b": [1, 2]}');
      final out = h.text('store:\n  book: []');
      expect(out, contains('a: 1'));
      expect(out, contains('b:'));
      expect(out, contains('- 1'));
      expect(out, contains('- 2'));
    });

    toolTest('invalid YAML surfaces an error', tool, (h) async {
      await h.enter('---\n- item: Super Hoop', text: 'a: [unclosed');
      expect(h.text('[]'), isEmpty);
      expect(find.textContaining('Error on line'), findsOneWidget);
    });

    toolTest('empty input clears output', tool, (h) async {
      await h.enter('---\n- item: Super Hoop', text: 'a: 1');
      await h.enter('---\n- item: Super Hoop', text: '');
      expect(h.text('[]'), '');
    });
  });

  group('JSON ↔ CSV', () {
    const tool = 'json_csv_converter';

    toolTest('converts CSV rows to JSON objects', tool, (h) async {
      await h.enter('id,name,note', text: 'id,name\n1,DevUtils');
      final out = h.text('[]');
      expect(out, contains('"id": "1"'));
      expect(out, contains('"name": "DevUtils"'));
    });

    toolTest('handles quoted CSV cells with commas', tool, (h) async {
      await h.enter('id,name,note', text: 'id,note\n1,"a, b"');
      final out = h.text('[]');
      expect(out, contains('"a, b"'));
    });

    toolTest('converts JSON array to CSV', tool, (h) async {
      await h.tap('JSON → CSV');
      await h.enter(
        '{"data":[{"id":1}]}',
        text: '[{"id": 1, "name": "Ada"}, {"id": 2}]',
      );
      final out = h.text('id,name');
      final lines = out.trim().split('\n');
      expect(lines.first, contains('id'));
      expect(lines.first, contains('name'));
      expect(lines, hasLength(3));
      expect(out, contains('Ada'));
    });

    toolTest('invalid JSON surfaces an error', tool, (h) async {
      await h.tap('JSON → CSV');
      await h.enter('{"data":[{"id":1}]}', text: '{not json}');
      expect(h.text('id,name'), isEmpty);
    });
  });

  group('Number Base Converter', () {
    const tool = 'number_base_converter';
    final inputField = find.byKey(const ValueKey('number-base-input'));

    Future<void> type(WidgetTester tester, String value) async {
      await tester.enterText(inputField, value);
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('parses hex with 0x prefix and lists all bases', (
      tester,
    ) async {
      final h = ToolHarness(tester);
      await h.open(tool);
      await type(tester, '0xDEADBEEF');
      expect(find.text('Base 16'), findsOneWidget);
      // The inspector repeats the unsigned value, so scope to the base row.
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('base-value-Decimal')),
            )
            .data,
        '3735928559',
      );
      expect(find.text('0xDEADBEEF'), findsWidgets);
      expect(find.text('0o33653337357'), findsOneWidget);
    });

    testWidgets('parses decimal and binary', (tester) async {
      final h = ToolHarness(tester);
      await h.open(tool);
      await type(tester, '255');
      expect(find.text('0xFF'), findsOneWidget);
      expect(find.text('0b11111111'), findsOneWidget);
      expect(find.text('0o377'), findsOneWidget);

      await type(tester, '0b1010');
      // Scoped by key: the inspector legitimately shows 10 for both the
      // unsigned and signed interpretations of the same value.
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('base-value-Decimal')),
            )
            .data,
        '10',
      );
    });

    testWidgets('handles huge BigInt values', (tester) async {
      final h = ToolHarness(tester);
      await h.open(tool);
      await type(tester, '0xffffffffffffffffffffffffffffffff');
      expect(
        find.text('340282366920938463463374607431768211455'),
        findsOneWidget,
      );
      expect(find.text('0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'), findsOneWidget);
    });

    testWidgets('invalid input shows an error message', (tester) async {
      final h = ToolHarness(tester);
      await h.open(tool);
      await type(tester, 'not a number');
      expect(
        find.text('Enter a valid value for the selected base.'),
        findsOneWidget,
      );
    });

    testWidgets('negative decimal is parsed', (tester) async {
      final h = ToolHarness(tester);
      await h.open(tool);
      await type(tester, '-255');
      expect(find.text('-255'), findsWidgets);
    });
  });

  group('Hex ↔ ASCII', () {
    const tool = 'hex_ascii_converter';
    // Encode(hex→ascii default? placeholders flip): hex→ascii input '48 65 6C 6C 6F'

    toolTest('decodes space-separated hex to text', tool, (h) async {
      await h.enter('48 65 6C 6C 6F', text: '48 65 6C 6C 6F');
      expect(h.text('Hello'), 'Hello');
    });

    toolTest('accepts 0x prefixes and mixed case', tool, (h) async {
      await h.enter('48 65 6C 6C 6F', text: '0x48 0x65 0x6c 0x6C 0x6F');
      expect(h.text('Hello'), 'Hello');
    });

    toolTest('pads odd-length tokens', tool, (h) async {
      await h.enter('48 65 6C 6C 6F', text: '48656c6c6f');
      expect(h.text('Hello'), 'Hello');
    });

    toolTest('decodes UTF-8 sequences', tool, (h) async {
      await h.enter('48 65 6C 6C 6F', text: 'C3 A9');
      expect(h.text('Hello'), 'é');
    });

    toolTest('encodes text to hex', tool, (h) async {
      await h.tap('ASCII → Hex');
      await h.enter('Hello', text: 'Hello');
      expect(h.text('48 65 6C 6C 6F'), '48 65 6C 6C 6F');
    });
  });

  group('Color Converter', () {
    const tool = 'color_converter';

    Future<void> openLarge(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = ToolHarness(tester);
      await h.open(tool);
    }

    testWidgets('expands a hex input into every format', (tester) async {
      await openLarge(tester);
      await enterInline(tester, '#5CC07F, rgb(92, 192, 127)', '#5CC07F');
      expect(find.text('#5CC07F'), findsWidgets);
      expect(find.text('rgb(92, 192, 127)'), findsWidgets);
      expect(find.text('rgba(92, 192, 127, 1.00)'), findsOneWidget);
      expect(find.text('cmyk(52%, 0%, 34%, 25%)'), findsOneWidget);
    });

    testWidgets('parses rgb() input', (tester) async {
      await openLarge(tester);
      await enterInline(
        tester,
        '#5CC07F, rgb(92, 192, 127)',
        'rgb(92, 192, 127)',
      );
      expect(find.text('#5CC07F'), findsWidgets);
    });

    testWidgets('invalid color shows an error', (tester) async {
      await openLarge(tester);
      await enterInline(tester, '#5CC07F, rgb(92, 192, 127)', 'not-a-color');
      expect(find.text('Invalid color.'), findsOneWidget);
    });
  });

  group('PHP Serializer', () {
    toolTest('serializes JSON into PHP format', 'php_serializer', (h) async {
      await h.enter(
        'Paste JSON to serialize into a PHP string...',
        text: '{"a":1,"b":"x"}',
      );
      expect(
        h.text('PHP serialized output...'),
        'a:2:{s:1:"a";i:1;s:1:"b";s:1:"x";}',
      );
    });

    toolTest('serializes nested arrays and booleans', 'php_serializer', (
      h,
    ) async {
      await h.enter(
        'Paste JSON to serialize into a PHP string...',
        text: '[true, null, 2.5]',
      );
      final out = h.text('PHP serialized output...');
      expect(out, contains('b:1'));
      expect(out, contains('N;'));
      expect(out, contains('d:2.5;'));
    });

    toolTest('unserializes scalars', 'php_unserializer', (h) async {
      await h.enter(
        'Paste a PHP serialized string to decode...',
        text: 'i:42;',
      );
      expect(h.text('Decoded JSON output...'), '42');
    });

    toolTest('unserializes strings', 'php_unserializer', (h) async {
      await h.enter(
        'Paste a PHP serialized string to decode...',
        text: 's:5:"Hello";',
      );
      expect(h.text('Decoded JSON output...'), '"Hello"');
    });

    toolTest('unserializes arrays into JSON', 'php_unserializer', (h) async {
      await h.enter(
        'Paste a PHP serialized string to decode...',
        text: 'a:2:{s:1:"a";i:1;s:1:"b";s:1:"x";}',
      );
      final out = h.text('Decoded JSON output...');
      expect(out, contains('"a": 1'));
      expect(out, contains('"b": "x"'));
    });

    toolTest('invalid serialized data surfaces an error', 'php_unserializer', (
      h,
    ) async {
      await h.enter('Paste a PHP serialized string to decode...', text: 'x:1:');
      expect(
        h.text('Decoded JSON output...'),
        contains('Invalid PHP serialized input'),
      );
    });
  });

  group('PHP to JS', () {
    const tool = 'php_to_js';

    toolTest('converts variables and echo to JavaScript', tool, (h) async {
      await h.enter(
        '<?php\n\$name = "DevUtils";\necho "Hello \$name";',
        text: '<?php\n\$name = "DevUtils";\necho "Hello \$name";',
      );
      final out = h.text('JavaScript output...');
      expect(out, contains('var name = "DevUtils"'));
      expect(out, contains('console.log'));
    });

    toolTest('converts a PHP function', tool, (h) async {
      await h.enter(
        '<?php\n\$name = "DevUtils";\necho "Hello \$name";',
        text: '<?php\nfunction add(\$a, \$b) {\n  return \$a + \$b;\n}',
      );
      final out = h.text('JavaScript output...');
      expect(out, contains('function add'));
      expect(out, contains('return'));
    });
  });

  group('SVG to CSS', () {
    const tool = 'svg_to_css';

    toolTest('builds a data-URI background rule', tool, (h) async {
      await h.enter(
        'Drop an .svg file here or paste SVG source...',
        text:
            '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"></svg>',
      );
      final out = h.text('Output...');
      expect(out, contains('background-image'));
      expect(out, contains('data:image/svg+xml'));
      expect(out, contains('%3Csvg'));
    });

    toolTest('non-SVG input reports an error', tool, (h) async {
      await h.enter(
        'Drop an .svg file here or paste SVG source...',
        text: '<div>nope</div>',
      );
      expect(h.text('Output...'), isEmpty);
      expect(find.textContaining('does not look like SVG'), findsOneWidget);
    });
  });

  group('cURL to Code', () {
    const tool = 'curl_to_code';

    toolTest('generates fetch code from a curl command', tool, (h) async {
      await h.enter(
        'Enter text...',
        text: "curl 'https://api.example.com/data'",
      );
      final out = h.text('Output...');
      expect(out, contains('fetch('));
      expect(out, contains('api.example.com'));
    });

    toolTest('maps -X POST and headers into the request', tool, (h) async {
      await h.enter(
        'Enter text...',
        text:
            "curl -X POST -H 'Content-Type: application/json' -d '{\"k\": 1}' https://api.example.com/submit",
      );
      final out = h.text('Output...');
      expect(out, contains('POST'));
      expect(out, contains('Content-Type'));
    });
  });

  group('JSON to Code', () {
    const tool = 'json_to_code';

    toolTest('generates Swift structs from JSON', tool, (h) async {
      await h.enter(
        'Drop a .json file here or enter your text...',
        text: '{"user": {"id": 1, "name": "Ada"}}',
      );
      final out = h.text('- Right click -> Save to file...');
      expect(out, contains('struct'));
      expect(out, contains('Codable'));
      expect(out, contains('let user'));
    });

    toolTest('generates TypeScript interfaces from JSON', tool, (h) async {
      await h.tap('Swift');
      await h.tap('TypeScript');
      await h.enter(
        'Drop a .json file here or enter your text...',
        text: '{"id": 1, "active": true}',
      );
      final out = h.text('- Right click -> Save to file...');
      expect(out, contains('interface'));
      expect(out, contains('id: number'));
      expect(out, contains('active: boolean'));
    });

    toolTest('invalid JSON surfaces an error', tool, (h) async {
      await h.enter(
        'Drop a .json file here or enter your text...',
        text: '{oops}',
      );
      expect(
        h.text('- Right click -> Save to file...'),
        contains('Invalid JSON'),
      );
    });
  });

  group('HTML to JSX', () {
    const tool = 'html_to_jsx';

    toolTest('converts class attributes and self-closing tags', tool, (
      h,
    ) async {
      await h.enter('Paste HTML here...', text: '<div class="a"><br></div>');
      final out = h.text('JSX output...');
      expect(out, contains('className="a"'));
      expect(out, contains('<br />'));
    });

    toolTest('keeps text content', tool, (h) async {
      await h.enter('Paste HTML here...', text: '<p>Hello JSX</p>');
      expect(h.text('JSX output...'), contains('Hello JSX'));
    });
  });

  group('JS to TS Converter', () {
    const tool = 'js_to_ts_converter';

    toolTest('preserves untyped functions and adds JSDoc annotations', tool, (
      h,
    ) async {
      await h.enter(
        'Choose a .js/.jsx file or paste JavaScript...',
        text: 'function greet(name) {\n  return name;\n}',
      );
      final out = h.text('TypeScript output...');
      expect(out, contains('function greet(name)'));

      await h.enter(
        'Choose a .js/.jsx file or paste JavaScript...',
        text:
            '/** @param {string} name */\nfunction greet(name) {\n  return name;\n}',
      );
      final annotated = h.text('TypeScript output...');
      expect(annotated, contains('name: string'));
    });

    toolTest('keeps behavior when converting TS back to JS', tool, (h) async {
      await h.tap('TS → JS');
      await h.enter(
        'Choose a .ts/.tsx file or paste TypeScript...',
        text:
            'const n: number = 5;\nfunction f(a: string): string { return a; }',
      );
      final out = h.text('JavaScript output...');
      expect(out, contains('const n = 5'));
      expect(out, contains('function f(a)'));
      expect(out, isNot(contains(': string')));
    });
  });

  group('Unix Time Converter', () {
    const tool = 'unix_time_converter';
    final inputField = find.byKey(const ValueKey('unix-time-input'));

    testWidgets('converts an epoch to date rows', (tester) async {
      final h = ToolHarness(tester);
      await h.open(tool);
      await tester.enterText(inputField, '1700000000');
      await tester.pump(const Duration(milliseconds: 300));
      // The Unix time row is timezone-independent.
      expect(find.text('1700000000'), findsWidgets);
      expect(find.textContaining('2023-11-14'), findsWidgets);
    });

    testWidgets('supports arithmetic expressions', (tester) async {
      final h = ToolHarness(tester);
      await h.open(tool); // initializes the workspace
      ignore(h);
      await tester.enterText(inputField, '1700000000 + 60');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1700000060'), findsWidgets);
    });

    testWidgets('invalid input shows an error', (tester) async {
      final h = ToolHarness(tester);
      await h.open(tool); // initializes the workspace
      ignore(h);
      await tester.enterText(inputField, 'banana');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Invalid number input.'), findsOneWidget);
    });
  });
}
