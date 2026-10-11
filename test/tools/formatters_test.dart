import 'package:flutter_test/flutter_test.dart';

import '../helpers/tool_harness.dart';
import '../helpers/formatter_engine.dart';
import 'package:dev_tool/services/javascript_code_service.dart';

void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body,
) {
  testWidgets(description, (tester) async {
    final h = _FormatterHarness(tester);
    await tester.runAsync(
      () => JavascriptCodeService.process('const n = 1;', 'Verify'),
    );
    await h.open(toolId);
    await body(h);
  });
}

class _FormatterHarness extends ToolHarness {
  _FormatterHarness(super.tester);

  @override
  Future<void> enter(
    String? hint, {
    String? label,
    required String text,
    int index = 0,
  }) async {
    await super.enter(hint, label: label, text: text, index: index);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await settle();
  }
}

void main() {
  setUp(installFormatterChannel);
  group('JSON Format/Validate', () {
    const tool = 'json_format_validate';

    toolTest('formats minified JSON live', tool, (h) async {
      await h.enter('Paste JSON...', text: '{"name":"DevUtils","n":2}');
      final out = h.text('Formatted JSON...');
      expect(out, contains('"name": "DevUtils"'));
      expect(out, contains('"n": 2'));
    });

    toolTest('nested objects and arrays are indented', tool, (h) async {
      await h.enter('Paste JSON...', text: '{"a":[1,{"b":2}]}');
      final out = h.text('Formatted JSON...');
      expect(out, contains('    "b": 2'));
    });

    toolTest('invalid JSON keeps output empty', tool, (h) async {
      await h.enter('Paste JSON...', text: '{"broken":');
      expect(h.text('Formatted JSON...'), isEmpty);
    });

    toolTest('empty input clears output', tool, (h) async {
      await h.enter('Paste JSON...', text: '{"a":1}');
      await h.enter('Paste JSON...', text: '');
      expect(h.text('Formatted JSON...'), isEmpty);
    });
  });

  group('HTML Beautify/Minify', () {
    const tool = 'html_beautify_minify';

    toolTest('beautifies nested markup with indentation', tool, (h) async {
      await h.enter('Paste HTML here...', text: '<div><p>Hi</p></div>');
      final out = h.text('Output...');
      expect(out, contains('<p>'));
      expect(out, contains('<p>Hi</p>'));
    });

    toolTest('minify collapses whitespace', tool, (h) async {
      await h.tap('Beautify');
      await h.tap('Minify');
      await h.enter('Paste HTML here...', text: '<div>\n  <p>Hi</p>\n</div>');
      expect(h.text('Output...'), '<div><p>Hi</p></div>');
    });

    toolTest('keeps doctype and comments on their own lines', tool, (h) async {
      await h.enter(
        'Paste HTML here...',
        text: '<!DOCTYPE html><!-- note --><html><body>x</body></html>',
      );
      final out = h.text('Output...');
      expect(out, contains('<!DOCTYPE html>'));
      expect(out, contains('<!-- note -->'));
    });
  });

  group('CSS Beautify/Minify', () {
    const tool = 'css_beautify_minify';

    toolTest('beautifies rules with spaced properties', tool, (h) async {
      await h.enter(
        'Drop a .css file here or paste CSS...',
        text: 'body{color:red;margin:0}',
      );
      final out = h.text('Output...');
      expect(out, contains('color: red'));
      expect(out, contains('margin: 0'));
      expect(out, contains('{'));
    });

    toolTest('minify strips whitespace', tool, (h) async {
      await h.tap('Beautify');
      await h.tap('Minify');
      await h.enter(
        'Drop a .css file here or paste CSS...',
        text: 'body {\n  color: red;\n}\n\np {\n  margin: 0;\n}',
      );
      expect(h.text('Output...'), 'body{color:red}p{margin:0}');
    });
  });

  group('JS Beautify/Minify', () {
    const tool = 'js_beautify_minify';

    toolTest('beautifies statements onto separate lines', tool, (h) async {
      await h.enter(
        'Paste JavaScript or TypeScript here...',
        text: 'function a(){return 1;}function b(){return 2;}',
      );
      final out = h.text('Output...');
      expect(out, contains('function a()'));
      expect(out, contains('return 1;'));
      expect(out.split('\n').length, greaterThan(3));
    });

    toolTest('minify removes newlines and indentation', tool, (h) async {
      await h.tap('Beautify');
      await h.tap('Minify');
      await h.enter(
        'Paste JavaScript or TypeScript here...',
        text: 'function a() {\n  return 1;\n}',
      );
      final out = h.text('Output...');
      expect(out, isNot(contains('\n')));
      expect(out, contains('return 1;'));
    });
  });

  group('RB Beautify/Minify', () {
    const tool = 'rb_beautify_minify';

    toolTest('beautifies methods with indentation', tool, (h) async {
      await h.enter('Paste RB here...', text: 'class A\ndef f\n1\nend\nend');
      final out = h.text('Output...');
      expect(out, contains('class A'));
      expect(out, contains('def f'));
      expect(out.split('\n').length, greaterThan(2));
    });

    toolTest('minify collapses indentation', tool, (h) async {
      await h.tap('Beautify');
      await h.tap('Minify');
      await h.enter(
        'Paste RB here...',
        text: 'class A\n  def f\n    1\n  end\nend',
      );
      final out = h.text('Output...');
      expect(out, isNot(contains('  def')));
    });
  });

  group('XML Beautify/Minify', () {
    const tool = 'xml_beautify_minify';

    toolTest('beautifies nested elements', tool, (h) async {
      await h.enter('Paste XML here...', text: '<a><b>x</b></a>');
      final out = h.text('Output...');
      expect(out, contains('<b>'));
      expect(out, contains('x'));
      expect(out, contains('\n'));
    });

    toolTest('minify strips inter-element whitespace', tool, (h) async {
      await h.tap('Beautify');
      await h.tap('Minify');
      await h.enter('Paste XML here...', text: '<a>\n  <b>x</b>\n</a>');
      expect(h.text('Output...'), '<a><b>x</b></a>');
    });

    toolTest('strip comments removes them in minify mode', tool, (h) async {
      await h.tap('Beautify');
      await h.tap('Minify');
      await h.tap('Keep comments');
      await h.tap('Strip comments');
      await h.enter('Paste XML here...', text: '<a><!-- hi --><b>x</b></a>');
      final out = h.text('Output...');
      expect(out, isNot(contains('<!-- hi -->')));
    });

    toolTest('keeps CDATA content intact when beautifying', tool, (h) async {
      await h.enter('Paste XML here...', text: '<a><![CDATA[x < y]]></a>');
      final out = h.text('Output...');
      expect(out, contains('<![CDATA[x < y]]>'));
    });
  });

  group('SQL Formatter', () {
    const tool = 'sql_formatter';

    toolTest('formats keywords uppercase with indentation', tool, (h) async {
      await h.enter('Enter text...', text: 'select * from users where id = 1');
      final out = h.text('Output...');
      expect(out, contains('SELECT'));
      expect(out, contains('FROM'));
      expect(out, contains('WHERE'));
      expect(out, contains('\n'));
    });

    toolTest('lowercase keyword mode', tool, (h) async {
      await h.tap('Uppercase');
      await h.tap('Lowercase');
      await h.enter('Enter text...', text: 'SELECT 1');
      expect(h.text('Output...'), contains('select'));
    });

    toolTest('SQL to English explains the query', tool, (h) async {
      await h.tap('Format');
      await h.tap('SQL to English');
      await h.enter('Enter text...', text: 'SELECT * FROM users WHERE id = 1');
      final out = h.text('Output...');
      expect(out, contains('SUMMARY'));
      expect(out, contains('users'));
    });
  });
}
