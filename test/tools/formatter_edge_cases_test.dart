import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/json_operations_service.dart';
import 'package:dev_tool/services/javascript_code_service.dart';
import 'package:dev_tool/services/ruby_format_service.dart';

import '../helpers/formatter_engine.dart';
import '../helpers/tool_harness.dart';
import 'formatter_options_test.dart' show choose, flush;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installFormatterChannel);

  test('JSON to XML honors all three indentation choices', () {
    for (final indent in ['  ', '    ', '\t']) {
      final output = transformJson(
        {
          'nested': {'x': 1},
        },
        JsonOperation.xml,
        indent,
      );
      expect(output, contains('\n${indent * 2}<x>1</x>'));
    }
  });
  test('JSX fragments retain text and parse after minification', () {
    const source = 'const view = <>Hello  <b>world</b> !</>;';
    final result = runFormatterEngine(source, 'Minify');
    expect(result['valid'], true);
    expect(result['output'], contains('Hello  <b>world</b> !'));
    expect(
      runFormatterEngine(result['output'] as String, 'Verify')['valid'],
      true,
    );
  });
  test(
    'TypeScript obfuscation prepares runnable JavaScript; modules get a clear limit',
    () {
      final result = runFormatterEngine(
        'const text: string = "你好 🌍"; console.log(text);',
        'Obfuscate',
      );
      expect(result['valid'], true);
      final run = Process.runSync('node', ['-e', result['output'] as String]);
      expect(run.exitCode, 0);
      expect(run.stdout, contains('你好 🌍'));
      for (final source in [
        'import x from "x";',
        'export const n=1;',
        'const el=<div/>;',
      ]) {
        final rejected = runFormatterEngine(source, 'Obfuscate');
        expect(rejected['valid'], false);
        expect(rejected['output'], contains('standalone'));
      }
    },
  );
  testWidgets(
    'Obfuscate wrapper executes fixed TS Unicode fixture and recovers from errors',
    (tester) async {
      await tester.runAsync(
        () => JavascriptCodeService.process('const n=1;', 'Verify'),
      );
      final h = ToolHarness(tester);
      await h.open('js_beautify_minify', surface: const Size(2200, 1200));
      await choose(h, 'Obfuscate');
      await h.enter(
        'Paste JavaScript or TypeScript here...',
        text: 'const text: string = "你好 🌍"; console.log(text);',
      );
      await flush(h);
      final output = h.text('Output...');
      expect(output, contains('eval(_d('));
      final result = Process.runSync('node', ['-e', output]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('你好 🌍'));
      await h.enter(
        'Paste JavaScript or TypeScript here...',
        text: 'const = ;',
      );
      await flush(h);
      expect(h.text('Output...'), contains('Line'));
      expect(h.text('Output...'), isNot(contains('eval(_d(')));
      await h.enter(
        'Paste JavaScript or TypeScript here...',
        text: 'console.log(1);',
      );
      await flush(h);
      expect(h.text('Output...'), contains('eval(_d('));
      await h.enter('Paste JavaScript or TypeScript here...', text: '');
      await flush(h);
      expect(h.text('Output...'), isEmpty);
    },
  );
  testWidgets('XML malformed input has a useful error and recovers', (
    tester,
  ) async {
    final h = ToolHarness(tester);
    await h.open('xml_beautify_minify', surface: const Size(2200, 1200));
    for (final operation in ['Beautify', 'Minify']) {
      await choose(h, operation);
      await h.enter('Paste XML here...', text: '<a><b></a>');
      expect(h.text('Output...'), contains('Could not format XML'));
      await h.enter('Paste XML here...', text: '<a><b>ok</b></a>');
      expect(h.text('Output...'), contains('ok'));
      expect(h.text('Output...'), isNot(contains('Could not')));
    }
  });
  testWidgets('SQL English handles statements, comments, literals and BETWEEN', (
    tester,
  ) async {
    final h = ToolHarness(tester);
    await h.open('sql_formatter', surface: const Size(2200, 1200));
    await choose(h, 'SQL to English');
    final cases = {
      "SELECT name FROM users WHERE age BETWEEN 12 AND 18 AND name = 'A AND B'":
          ['users', 'filtered by 2 conditions'],
      "INSERT INTO users(name) VALUES ('SELECT')": ['users', 'Inserts 1 row'],
      "UPDATE users SET name = 'A' WHERE id = 2": ['users', '1 filter'],
      "DELETE FROM users WHERE id = 2": ['users', '1 condition'],
      'CREATE TABLE people(id INT)': ['people'],
      'DROP TABLE people': ['people'],
      'ALTER TABLE people ADD name TEXT': ['ALTER'],
      "-- comment\nSELECT name FROM users WHERE name = 'FROM missing WHERE x AND y'":
          ['users', '1 condition'],
      'SELECT 1': ['Selects the values: 1'],
      'SELECT COALESCE(name, nickname) FROM users': ['Retrieves 1 column'],
      'UPDATE users SET name = CONCAT(first, last) WHERE id = 1': [
        '1 column',
        '1 filter',
      ],
      'INSERT INTO users SELECT * FROM archive': [
        'rows from a subquery',
        'users',
      ],
      'SELECT * FROM users': ['users', 'all columns'],
      'SELECT name FROM users ORDER BY name LIMIT 2': [
        'users',
        'ORDER BY',
        'limited to 2 rows',
      ],
      'SELECT team, COUNT(*) FROM users GROUP BY team HAVING COUNT(*) > 1': [
        'users',
        'GROUP BY',
        'HAVING',
      ],
    };
    for (final entry in cases.entries) {
      await h.enter('Enter text...', text: entry.key);
      final output = h.text('Output...');
      expect(output, contains('SUMMARY'), reason: entry.key);
      for (final text in entry.value) {
        expect(output, contains(text), reason: entry.key);
      }
      expect(output, isNot(contains('__devutils_literal_')));
      if (entry.key.startsWith('INSERT') && entry.key.contains('VALUES')) {
        expect(output, isNot(contains('subquery')));
      }
    }
  });
  test(
    'Ruby strip comments removes inline comments, preserving literal hashes and directives',
    () {
      const source =
          '#!/usr/bin/ruby\n# frozen_string_literal: true\n# remove\nputs "# literal" # remove too\n';
      final result = RubyFormatService.process(source, keepComments: false);
      expect(result, contains('#!/usr/bin/ruby'));
      expect(result, contains('frozen_string_literal: true'));
      expect(result, contains('"# literal"'));
      expect(result, isNot(contains('remove')));
    },
  );
  test('JSON minify never strips string whitespace', () {
    const source = '{"message":" x  y ","n":[1,2]}';
    final output = transformJson(
      jsonDecode(source),
      JsonOperation.minify,
      '  ',
    );
    expect(jsonDecode(output), jsonDecode(source));
  });
}
