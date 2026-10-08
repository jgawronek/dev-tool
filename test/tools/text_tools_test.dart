import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/ui/tools/common/shared.dart';
import 'package:dev_tool/ui/tool_views.dart' show markdownToHtmlForPreview;

import '../helpers/tool_harness.dart';

void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body, {
  Size? surface,
}) {
  testWidgets(description, (tester) async {
    final h = ToolHarness(tester);
    await h.open(toolId, surface: surface);
    await body(h);
  });
}

/// Types into the free-form text field (the only [TextField] that is not
/// rendered inside an [InlineTextField]).
Future<void> enterPlainTextField(WidgetTester tester, String text) async {
  final plainFields = find.byWidgetPredicate((w) {
    if (w is! TextField) return false;
    if (w.decoration?.hintText != null) return false;
    var ancestor = tester.element(find.byWidget(w));
    var insideInline = false;
    ancestor.visitAncestorElements((element) {
      if (element.widget is InlineTextField) {
        insideInline = true;
        return false;
      }
      return true;
    });
    return !insideInline;
  });
  await tester.enterText(plainFields.first, text);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('RegExp Tester', () {
    const tool = 'regexp_tester';

    /// The tester's text input is a plain TextField; output is the only
    /// EditorPane (placeholder '').
    Future<String> runRegExp(ToolHarness h, String regex, String input) async {
      await enterPlainTextField(h.tester, input);
      final field = h.tester.widget<InlineTextField>(
        find.byWidgetPredicate(
          (w) => w is InlineTextField && w.hintText == r'([A-Z])\w+',
        ),
      );
      field.controller!.text = regex;
      field.onChanged?.call(regex);
      await h.settle();
      return h.text('');
    }

    final surface = const Size(1500, 1000);

    toolTest('extracts all matches with the default format', tool, (h) async {
      final out = await runRegExp(h, r'\d+', 'a1 b22 c333');
      expect(out.trim().split('\n'), ['1', '22', '333']);
    }, surface: surface);

    toolTest('applies capture-group templates', tool, (h) async {
      final out = await runRegExp(h, r'(\w+)@(\w+)', 'me@you him@her');
      expect(out, contains('me@you'));
    }, surface: surface);

    toolTest('invalid regex surfaces an error', tool, (h) async {
      await enterPlainTextField(h.tester, 'abc');
      final field = h.tester.widget<InlineTextField>(
        find.byWidgetPredicate(
          (w) => w is InlineTextField && w.hintText == r'([A-Z])\w+',
        ),
      );
      field.controller!.text = '(unclosed';
      field.onChanged?.call('(unclosed');
      await h.settle();
      expect(find.textContaining('error'), findsNothing); // no crash
      expect(find.textContaining(RegExp('Invalid|Exception')), findsOneWidget);
    }, surface: surface);

    toolTest('no matches yields empty output', tool, (h) async {
      final out = await runRegExp(h, r'xyz', 'abc');
      expect(out, isEmpty);
    }, surface: surface);

    toolTest('search filters listed matches', tool, (h) async {
      await runRegExp(h, r'\w+', 'alpha beta');
      final search = h.tester.widget<InlineTextField>(
        find.byWidgetPredicate(
          (w) => w is InlineTextField && w.hintText == 'Search matches...',
        ),
      );
      search.controller!.text = 'bet';
      search.onChanged?.call('bet');
      await h.settle();
      expect(find.textContaining('beta'), findsWidgets);
    }, surface: surface);
  });

  group('Text Diff Checker', () {
    const tool = 'text_diff_checker';

    toolTest('marks removed and added lines', tool, (h) async {
      await h.tap('Characters');
      await h.tap('Lines');
      await h.enter('', label: 'Input 1', text: 'a\nb\nc');
      await h.enter('', label: 'Input 2', text: 'a\nx\nc');
      final out = h.text('Diff output...');
      expect(out, contains('- b'));
      expect(out, contains('+ x'));
      expect(out, isNot(contains('- a')));
    });

    toolTest('identical inputs produce no markers', tool, (h) async {
      await h.enter('', label: 'Input 1', text: 'same\nlines');
      await h.enter('', label: 'Input 2', text: 'same\nlines');
      final out = h.text('Diff output...');
      expect(out, isNot(contains('+ ')));
      expect(out, isNot(contains('- ')));
    });

    toolTest('word mode diff', tool, (h) async {
      await h.tap('Lines');
      await h.tap('Words');
      await h.enter('', label: 'Input 1', text: 'one two three');
      await h.enter('', label: 'Input 2', text: 'one TWO three');
      final out = h.text('Diff output...');
      expect(out, contains('TWO'));
    });

    toolTest('empty right side reports removals', tool, (h) async {
      await h.tap('Characters');
      await h.tap('Lines');
      await h.enter('', label: 'Input 1', text: 'only-left');
      await h.enter('', label: 'Input 2', text: '');
      expect(h.text('Diff output...'), contains('- only-left'));
    });
  });

  group('Lorem Ipsum Generator', () {
    const tool = 'lorem_ipsum_generator';

    toolTest('inserts a sentence', tool, (h) async {
      await h.tap('Sentence');
      expect(h.text('Generated text...'), 'Lorem ipsum dolor sit amet.');
    });

    toolTest('count multiplies insertions', tool, (h) async {
      await h.tap('x1');
      await h.tap('x5');
      await h.tap('Word');
      final out = h.text('Generated text...');
      expect('Lorem'.allMatches(out), hasLength(5));
    });

    toolTest('append mode accumulates', tool, (h) async {
      await h.tap('Replace');
      await h.tap('Append');
      await h.tap('Word');
      await h.tap('Word');
      final out = h.text('Generated text...');
      expect(out.split('\n'), hasLength(2));
    });
  });

  group('String Inspector', () {
    const tool = 'string_inspector';

    toolTest('counts characters, words and bytes', tool, (h) async {
      await h.enter('Type or paste text to inspect...', text: 'Hello world');
      expect(find.text('11'), findsWidgets); // characters + bytes (ASCII)
      expect(find.text('2'), findsWidgets); // words
    });

    toolTest('counts UTF-8 bytes for non-ASCII', tool, (h) async {
      await h.enter('Type or paste text to inspect...', text: 'é');
      expect(find.text('1'), findsWidgets); // characters (single rune)
      expect(find.text('2'), findsWidgets); // UTF-8 bytes
    });

    toolTest('empty input shows zeros', tool, (h) async {
      await h.enter('Type or paste text to inspect...', text: 'x');
      await h.enter('Type or paste text to inspect...', text: '');
      expect(find.text('0'), findsWidgets);
    });
  });

  group('String Case Converter', () {
    const tool = 'string_case_converter';

    toolTest('converts to camelCase by default', tool, (h) async {
      await h.enter('Enter text...', text: 'request URL decoder ID');
      expect(h.text('Output...'), 'requestUrlDecoderId');
    });

    toolTest('converts to snake_case', tool, (h) async {
      await h.tap('camelCase');
      await h.tap('snake_case');
      await h.enter('Enter text...', text: 'request URL decoder ID');
      expect(h.text('Output...'), 'request_url_decoder_id');
    });

    toolTest('converts to kebab-case', tool, (h) async {
      await h.tap('camelCase');
      await h.tap('kebab-case');
      await h.enter('Enter text...', text: 'request URL decoder ID');
      expect(h.text('Output...'), 'request-url-decoder-id');
    });

    toolTest('PascalCase', tool, (h) async {
      await h.tap('camelCase');
      await h.tap('PascalCase');
      await h.enter('Enter text...', text: 'hello world');
      expect(h.text('Output...'), 'HelloWorld');
    });
  });

  group('Markdown Preview', () {
    const tool = 'markdown_preview';

    toolTest('renders the preview pane for markdown input', tool, (h) async {
      await h.enter('Drop a .md file here or type Markdown...', text: '# Title\n\n**bold**');
      expect(find.byKey(const ValueKey('html-rendered-preview')), findsOneWidget);
      expect(find.text('Rendered Markdown'), findsOneWidget);
    });

    test('markdown converts headings, bold, and lists', () {
      final html = markdownToHtmlForPreview('# Hi\n\n**b** text\n\n- item');
      expect(html, contains('<h1>Hi</h1>'));
      expect(html, contains('<strong>b</strong>'));
      expect(html, contains('<li>item</li>'));
    });

    test('markdown escapes raw HTML', () {
      final html = markdownToHtmlForPreview('<script>alert(1)</script>');
      expect(html, isNot(contains('<script>')));
    });

    test('markdown links and inline code', () {
      final html = markdownToHtmlForPreview('[site](https://x.dev) and `code`');
      expect(html, contains('<a href='));
      expect(html, contains('x.dev'));
      expect(html, contains('<code>code</code>'));
    });
  });

  group('Line Sort/Dedupe', () {
    const tool = 'line_sort_dedupe';

    toolTest('sorts and dedupes lines', tool, (h) async {
      await h.tap('With Duplicates');
      await h.tap('Without Duplicates');
      await h.enter('Line 1\nLine 2\nLine 2', text: 'b\na\nb\nc');
      expect(h.text('Line 1\nLine 2'), 'a\nb\nc');
    });

    toolTest('keeps duplicates by default', tool, (h) async {
      await h.enter('Line 1\nLine 2\nLine 2', text: 'b\na\nb');
      expect(h.text('Line 1\nLine 2'), 'a\nb\nb');
    });

    toolTest('descending sort', tool, (h) async {
      await h.tap('A -> Z (Text)');
      await h.tap('Z -> A (Text)');
      await h.enter('Line 1\nLine 2\nLine 2', text: 'a\nb\nc');
      expect(h.text('Line 1\nLine 2'), 'c\nb\na');
    });

    toolTest('empty lines are preserved or dropped consistently', tool, (
      h,
    ) async {
      await h.enter('Line 1\nLine 2\nLine 2', text: 'b\n\na');
      final out = h.text('Line 1\nLine 2');
      expect(out.split('\n'), containsAllInOrder(['a', 'b']));
    });
  });

  group('Cron Job Parser', () {
    const tool = 'cron_job_parser';

    Future<void> typeCron(ToolHarness h, String expr) async {
      final field = h.tester.widget<InlineTextField>(
        find.byWidgetPredicate((w) => w is InlineTextField && w.hintText == '*/5 * * * *'),
      );
      field.controller!.text = expr;
      field.onChanged?.call(expr);
      await h.settle();
    }

    toolTest('parses step expressions', tool, (h) async {
      await typeCron(h, '*/5 * * * *');
      expect(find.textContaining('Minutes:'), findsOneWidget);
      expect(find.textContaining('0, 5'), findsOneWidget);
    });

    toolTest('parses ranges and lists', tool, (h) async {
      await typeCron(h, '0 9-11 * * 1,3');
      expect(find.textContaining('Hours: 9, 10, 11'), findsOneWidget);
      expect(find.textContaining('Day of Week: 1, 3'), findsOneWidget);
    });

    toolTest('shows next executions', tool, (h) async {
      await typeCron(h, '0 12 * * *');
      expect(find.text('Next executions:'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2}')), findsWidgets);
    });

    toolTest('invalid expression surfaces an error', tool, (h) async {
      await typeCron(h, 'not a cron');
      expect(find.textContaining(RegExp('Invalid|error', caseSensitive: false)), findsOneWidget);
    });
  });

  group('URL Parser', () {
    const tool = 'url_parser';

    toolTest('parses protocol, host, path and query', tool, (h) async {
      await h.enter(null, label: 'Input', text: 'https://api.dev:8443/v1/items?limit=10&q=x#frag');
      expect(find.text('Protocol: https'), findsOneWidget);
      expect(find.textContaining('Host: api.dev'), findsOneWidget);
      expect(find.textContaining('Path: /v1/items'), findsOneWidget);
      final queryJson = h.text('{ }');
      expect(queryJson, contains('"limit"'));
      expect(queryJson, contains('"10"'));
    });

    toolTest('query params decode into JSON', tool, (h) async {
      await h.enter(null, label: 'Input', text: 'https://x.dev/search?a=1&b=hello%20world');
      final queryJson = h.text('{ }');
      expect(queryJson, contains('"b": "hello world"'));
    });

    toolTest('unparseable URL surfaces an error', tool, (h) async {
      await h.enter(null, label: 'Input', text: 'http://x.dev/%zz');
      expect(find.textContaining(RegExp('Invalid|Format')), findsWidgets);
    });

    toolTest('relative reference parses with empty scheme and host', tool, (
      h,
    ) async {
      await h.enter(null, label: 'Input', text: 'docs/setup.md?ref=main');
      expect(find.text('Protocol: '), findsOneWidget);
      expect(find.text('Host: '), findsOneWidget);
      expect(find.textContaining('Path: docs/setup.md'), findsOneWidget);
    });
  });
}
