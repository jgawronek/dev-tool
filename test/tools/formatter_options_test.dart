import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:dev_tool/services/markup_format_service.dart';
import 'package:dev_tool/services/javascript_code_service.dart';
import 'package:dev_tool/services/ruby_format_service.dart';
import 'package:dev_tool/ui/tools/common/shared.dart';
import 'package:dev_tool/ui/widgets.dart';

import '../helpers/formatter_engine.dart';
import '../helpers/tool_harness.dart';

const tools = {
  'json_format_validate': ('Paste JSON...', '{"z":[3,1],"a":{"b":2}}'),
  'html_beautify_minify': (
    'Paste HTML here...',
    '<div><p>Hello <b>world</b> !</p></div>',
  ),
  'css_beautify_minify': (
    'Drop a .css file here or paste CSS...',
    'body{color:red;margin:0}',
  ),
  'js_beautify_minify': (
    'Paste JavaScript or TypeScript here...',
    'for(let i=0;i<3;i++){console.log(i);}',
  ),
  'rb_beautify_minify': (
    'Paste RB here...',
    'class A\ndef f\nputs "hello"\nend\nend',
  ),
  'xml_beautify_minify': ('Paste XML here...', '<root><child>x</child></root>'),
  'sql_formatter': ('Enter text...', 'select name, id from users where id = 1'),
};

Future<void> flush(ToolHarness h) async {
  await h.tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  });
  await h.settle();
}

Future<void> choose(ToolHarness h, String option) async {
  final dropdown = find.byWidgetPredicate(
    (widget) => widget is SmallDropdown && widget.items.contains(option),
  );
  expect(dropdown, findsOneWidget, reason: option);
  await h.tester.tap(dropdown);
  await h.settle();
  await h.tester.tap(find.text(option).last);
  await h.settle();
  await flush(h);
}

void formatterWidgetTests({bool native = false}) {
  for (final entry in tools.entries) {
    testWidgets('${entry.key}: every dropdown, sample, copy and empty input', (
      tester,
    ) async {
      final h = ToolHarness(tester, nativeFormatters: native);
      await tester.runAsync(
        () => JavascriptCodeService.process('const n = 1;', 'Verify'),
      );
      await h.open(entry.key, surface: const Size(2200, 1200));
      await h.enter(entry.value.$1, text: entry.value.$2);
      await flush(h);
      String output() => h.text(
        entry.key == 'json_format_validate' ? 'Formatted JSON...' : 'Output...',
      );
      expect(output(), isNotEmpty);
      expect(output(), isNot(contains('Could not')));
      final operations = tester
          .widgetList<SmallDropdown>(find.byType(SmallDropdown))
          .where(
            (dropdown) =>
                dropdown.items.contains('Beautify') ||
                dropdown.items.contains('Prettify') ||
                dropdown.items.contains('SQL to English'),
          )
          .first
          .items
          .toList();
      for (final operation in operations) {
        await choose(h, operation);
        if (operation == 'Preview') {
          final preview = tester.widget<HtmlRenderedPreview>(
            find.byType(HtmlRenderedPreview),
          );
          expect(preview.html, entry.value.$2);
          if (native) {
            expect(find.byType(WebViewWidget), findsOneWidget);
            final webView = tester.widget<WebViewWidget>(
              find.byType(WebViewWidget),
            );
            final text = await webView.platform.params.controller
                .runJavaScriptReturningResult('document.body.innerText');
            expect(text.toString(), contains('Hello world !'));
          }
          await choose(h, 'Beautify');
          continue;
        }
        expect(output(), isNotEmpty, reason: operation);
        expect(output(), isNot(contains('Could not')), reason: operation);
        if (operation == 'Minify' &&
            ![
              'rb_beautify_minify',
              'xml_beautify_minify',
            ].contains(entry.key)) {
          expect(output(), isNot(contains('\n')), reason: operation);
        }
        if (operation == 'Verify') {
          expect(output(), contains('No syntax errors'));
        }
        if (operation == 'Obfuscate') expect(output(), contains('eval(_d('));
        if (operation == 'SQL to English') {
          expect(output(), contains('SUMMARY'));
        }
      }
      await choose(h, operations.first);
      if (entry.key != 'sql_formatter' || operations.first == 'Format') {
        for (final (label, indent) in [
          ('2 spaces', '  '),
          ('4 spaces', '    '),
          ('Tabs', '\t'),
        ]) {
          await choose(h, label);
          expect(
            output(),
            contains('\n$indent'),
            reason: '${entry.key} $label',
          );
        }
      }
      if (entry.key == 'json_format_validate') {
        for (final label in ['Wrap', 'No wrap']) {
          await choose(h, label);
          expect(
            tester
                .widget<JsonSplitEditors>(find.byType(JsonSplitEditors))
                .outputSoftWrap,
            label == 'Wrap',
          );
        }
      }
      if (entry.key == 'sql_formatter') {
        await choose(h, 'Lowercase');
        expect(output(), contains('select'));
        await choose(h, 'Uppercase');
        expect(output(), contains('SELECT'));
      }
      if (['xml_beautify_minify', 'rb_beautify_minify'].contains(entry.key)) {
        await choose(h, 'Minify');
        final source = entry.key == 'xml_beautify_minify'
            ? '<r><!-- note --><x>1</x></r>'
            : '# note\nputs "# literal"';
        await h.enter(entry.value.$1, text: source);
        await choose(h, 'Keep comments');
        expect(output(), contains('note'));
        await choose(h, 'Strip comments');
        expect(output(), isNot(contains('note')));
      }
      await h.enter(entry.value.$1, text: '');
      await flush(h);
      expect(output(), isEmpty);
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Load sample').first,
      );
      await h.settle();
      await flush(h);
      expect(h.text(entry.value.$1), isNotEmpty);
      expect(output(), isNotEmpty);
      expect(output(), isNot(contains('Could not')));
      String? copied;
      final previousClipboard = native
          ? await Clipboard.getData('text/plain')
          : null;
      if (!native) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            });
      }
      await tester.tap(find.byTooltip('Copy Output').first);
      await h.settle();
      if (native) copied = (await Clipboard.getData('text/plain'))?.text;
      expect(copied, output());
      if (native) {
        await Clipboard.setData(
          previousClipboard ?? const ClipboardData(text: ''),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installFormatterChannel);
  formatterWidgetTests();

  for (final indent in ['2 spaces', '4 spaces', 'Tabs']) {
    test('native JS/TS and HTML/CSS indentation: $indent', () {
      final prefix = indent == 'Tabs'
          ? '\t'
          : indent == '4 spaces'
          ? '    '
          : '  ';
      for (final (operation, source) in [
        ('Beautify', 'function f(){return 1;}'),
        ('HTML Beautify', '<div><section><p>x</p></section></div>'),
        ('CSS Beautify', 'a{color:red}'),
      ]) {
        final result = runFormatterEngine(source, operation, indent);
        expect(result['valid'], true);
        expect(result['output'], contains('\n$prefix'));
      }
    });
  }
  test('HTML preserves inline spaces, attributes and raw text in both modes', () {
    const source =
        '<div title="a  b > c"><span>Hello</span> <span>world</span><pre> x  y\n z </pre><textarea>a  b</textarea><script>const s="a  b";</script></div>';
    for (final operation in ['HTML Beautify', 'HTML Minify']) {
      final result = runFormatterEngine(source, operation);
      expect(result['valid'], true);
      final output = result['output'] as String;
      for (final text in [
        'a  b > c',
        '</span> <span>',
        ' x  y\n z ',
        'a  b',
        'const s="a  b";',
      ]) {
        expect(output, contains(text), reason: operation);
      }
    }
  });
  test('CSS preserves strings, selectors, calc and custom properties', () {
    const source =
        'a:hover .b { content: "a  b /*keep*/"; width: calc(100% - 2px); --data: "x;y{}"; background: url("https://x/a b"); }';
    for (final operation in ['CSS Beautify', 'CSS Minify']) {
      final result = runFormatterEngine(source, operation);
      expect(result['valid'], true);
      for (final text in [
        'a:hover .b',
        'a  b /*keep*/',
        'calc(100% - 2px)',
        'x;y{}',
      ]) {
        expect(result['output'], contains(text), reason: operation);
      }
    }
  });
  test('JS minify preserves execution, ASI, regex, templates and Unicode', () {
    final cases = [
      'const s="a  b"; console.log(s);',
      'function f(){return\n {a:1};} console.log(f());',
      'const r=/a b/; console.log(r.test("a b"));',
      r'const n=2; console.log(`hello ${n}  world`);',
      'let a=1; let b=2; console.log(a + ++b);',
      'console.log("你好 🌍");',
      'let n=1; n\n++n; console.log(n);',
    ];
    for (final source in cases) {
      final result = runFormatterEngine(source, 'Minify');
      expect(result['valid'], true);
      final original = Process.runSync('node', ['-e', source]);
      final minified = Process.runSync('node', [
        '-e',
        result['output'] as String,
      ]);
      expect(
        minified.exitCode,
        0,
        reason: '${minified.stderr}\n${result['output']}',
      );
      expect(minified.stdout, original.stdout, reason: source);
    }
  });
  test(
    'JS verify handles valid JS, TS, TSX and malformed code without running source',
    () {
      for (final source in [
        'const n: number = 2;',
        'const element = <div>Hello</div>;',
        'throw new Error("must not run");',
        'let n1=0,n2=1; console.log(n1+n2);',
      ]) {
        expect(
          runFormatterEngine(source, 'Verify')['valid'],
          true,
          reason: source,
        );
      }
      for (final source in [
        'const = ;',
        'function f( {',
        'const x = "unfinished',
      ]) {
        final result = runFormatterEngine(source, 'Verify');
        expect(result['valid'], false);
        expect(result['output'], contains('Line'));
      }
      final loop =
          runFormatterEngine(
                'for(let i=0;i<3;i++){console.log(i);}',
                'Beautify',
              )['output']
              as String;
      expect(loop, contains('for (let i = 0; i < 3; i++)'));
    },
  );
  test('XML preserves mixed content, text, CDATA, attributes and xml:space', () {
    const source =
        '<r><p>Hello <b>world</b> !</p><v a="a  b"> x  y </v><c><![CDATA[x  < y]]></c><pre xml:space="preserve">\n  a\n</pre></r>';
    for (final pretty in [true, false]) {
      final output = XmlFormatService.process(source, pretty: pretty);
      final before = XmlDocument.parse(source),
          after = XmlDocument.parse(output);
      for (final tag in ['p', 'v', 'c', 'pre']) {
        expect(
          after.findAllElements(tag).single.innerText,
          before.findAllElements(tag).single.innerText,
        );
      }
      expect(after.findAllElements('v').single.getAttribute('a'), 'a  b');
    }
    expect(
      () => XmlFormatService.process('<a><b></a>', pretty: true),
      throwsA(isA<XmlException>()),
    );
  });
  test('Ruby preserves heredocs, multiline literals, comments and data', () {
    const source =
        'class A\nvalue = <<~TEXT\n  hello  world\n\nTEXT\ns = "first\n  second\n"\nq = %q{first\n  second\n}\n# comment\nend\n__END__\n  data  stays\n';
    for (final indent in [null, '  ', '    ', '\t']) {
      final output = RubyFormatService.process(source, indent: indent);
      for (final text in [
        '  hello  world\n\nTEXT',
        'first\n  second\n',
        '__END__\n  data  stays\n',
      ]) {
        expect(output, contains(text));
      }
      final dir = Directory.systemTemp.createTempSync('ruby-formatter-');
      try {
        final file = File('${dir.path}/input.rb')..writeAsStringSync(output);
        expect(
          Process.runSync('/usr/bin/ruby', ['-c', file.path]).exitCode,
          0,
          reason: output,
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    }
  });
  testWidgets('SQL protects literals, identifiers and comments in both cases', (
    tester,
  ) async {
    final h = ToolHarness(tester);
    await h.open('sql_formatter', surface: const Size(2200, 1200));
    const source =
        'select "order", \'from where AND  a  b\', \$\$select from\$\$ from users -- select from comment\nwhere name = \'it\'\'s select\'';
    await h.enter('Enter text...', text: source);
    for (final label in ['Uppercase', 'Lowercase']) {
      await choose(h, label);
      final output = h.text('Output...');
      for (final text in [
        '"order"',
        "'from where AND  a  b'",
        r'$$select from$$',
        "'it''s select'",
        '-- select from comment\n',
      ]) {
        expect(output, contains(text));
      }
    }
  });
}
