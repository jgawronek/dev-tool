import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/js_obfuscator_service.dart';
import 'package:dev_tool/ui/widgets.dart';

import '../helpers/tool_harness.dart';

void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body,
) {
  testWidgets(description, (tester) async {
    final h = ToolHarness(tester);
    await h.open(toolId, surface: const Size(1500, 1000));
    await body(h);
  });
}

/// EditorPane moves Sample and Clear into a right-click menu as 'Example'
/// and 'Clear'.
Future<void> editorMenu(ToolHarness h, String item) async {
  await h.tester.tapAt(
    h.tester.getCenter(find.byType(EditorPane).first),
    buttons: kSecondaryMouseButton,
  );
  await h.settle();
  await h.tap(item);
  await h.settle();
}

Future<void> loadSample(ToolHarness h) => editorMenu(h, 'Example');

/// The node binary, or null when this machine cannot run the differential
/// checks.
String? get _node {
  try {
    final result = Process.runSync('node', const ['--version']);
    return result.exitCode == 0 ? result.stdout.toString().trim() : null;
  } on ProcessException {
    return null;
  }
}

/// Runs [source] under node and returns its stdout.
String _runNode(String source, {String extension = '.cjs'}) {
  final file = File('${Directory.systemTemp.path}/devutils_obf$extension');
  file.writeAsStringSync(source);
  try {
    final result = Process.runSync('node', [file.path]);
    if (result.exitCode != 0) {
      throw StateError(
        'node exited ${result.exitCode}\n${result.stderr}\nsource:\n$source',
      );
    }
    return result.stdout.toString();
  } finally {
    if (file.existsSync()) file.deleteSync();
  }
}

List<JsToken> _significant(String source) =>
    tokenizeJs(source).where((t) => !t.isTrivia).toList();

void main() {
  group('tokenizer', () {
    test('classifies the basics', () {
      final types = _significant('const x = 42;').map((t) => t.type).toList();
      expect(
        types,
        containsAllInOrder(<JsTokenType>[
          JsTokenType.keyword,
          JsTokenType.identifier,
          JsTokenType.operator,
          JsTokenType.number,
          JsTokenType.punctuation,
        ]),
      );
    });

    test('treats single and double quoted strings as one token', () {
      final tokens = _significant('''var a = "he said \\"hi\\""; var b = 'x';''');
      final strings = tokens.where((t) => t.type == JsTokenType.string).toList();
      expect(strings, hasLength(2));
      expect(strings.first.text, '"he said \\"hi\\""');
    });

    test('does not treat comment markers inside strings as comments', () {
      final tokens = tokenizeJs('var url = "http://x/y"; // real comment');
      expect(tokens.where((t) => t.type == JsTokenType.string), hasLength(1));
      expect(tokens.where((t) => t.type == JsTokenType.comment), hasLength(1));
    });

    test('handles block comments containing newlines', () {
      final tokens = tokenizeJs('/* a\nb */ var x;');
      expect(tokens.first.type, JsTokenType.comment);
      expect(tokens.first.text, '/* a\nb */');
    });

    test('reads a division as an operator, not a regex', () {
      final tokens = _significant('var half = total / 2;');
      expect(tokens.where((t) => t.type == JsTokenType.regex), isEmpty);
      expect(tokens.any((t) => t.text == '/'), isTrue);
    });

    test('reads a regex literal after a keyword', () {
      final tokens = _significant('return /ab+c/gi;');
      final regex = tokens.firstWhere((t) => t.type == JsTokenType.regex);
      expect(regex.text, '/ab+c/gi');
    });

    test('reads a regex literal after an opening paren', () {
      final tokens = _significant('const re = (/\\d+/g);');
      expect(
        tokens.any((t) => t.type == JsTokenType.regex && t.text == r'/\d+/g'),
        isTrue,
      );
    });

    test('reads division after a closing paren as division', () {
      final tokens = _significant('var x = (a + b) / c;');
      expect(tokens.where((t) => t.type == JsTokenType.regex), isEmpty);
    });

    test('does not split a regex containing a slash in a class', () {
      final regex = _significant('var re = /[/]/;')
          .firstWhere((t) => t.type == JsTokenType.regex);
      expect(regex.text, '/[/]/');
    });

    test('records template substitutions as code ranges', () {
      final template = _significant(r'var t = `a ${b.c} d`;')
          .firstWhere((t) => t.type == JsTokenType.templateString);
      expect(template.text, r'`a ${b.c} d`');
      expect(template.codeRanges, hasLength(1));
      expect(template.text.substring(
            template.codeRanges.first.start,
            template.codeRanges.first.end,
          ), 'b.c');
    });

    test('handles nested braces inside a template substitution', () {
      final template = _significant(r'var t = `${ {a: 1}.a } end`;')
          .firstWhere((t) => t.type == JsTokenType.templateString);
      expect(template.codeRanges, hasLength(1));
      expect(
        template.text
            .substring(
              template.codeRanges.first.start,
              template.codeRanges.first.end,
            )
            .trim(),
        '{a: 1}.a',
      );
    });

    test('round-trips source exactly', () {
      const source =
          r'const a = /re/g; // c' '\n' r'var s = "x"; /* d */ `t${u}`;';
      expect(tokenizeJs(source).map((t) => t.text).join(), source);
    });
  });

  group('identifier mangling', () {
    test('renames a local binding and its uses', () {
      final report = obfuscateJs(
        'function calc(){ var secretValue = 41; return secretValue + 1; }',
      );
      expect(report.output, isNot(contains('secretValue')));
      expect(report.identifiersRenamed, greaterThan(0));
    });

    test('keeps property accesses intact', () {
      final report = obfuscateJs('var total = user.accountBalance;');
      expect(report.output, contains('.accountBalance'));
      expect(report.propertiesPreserved, greaterThan(0));
    });

    test('keeps optional-chained property names intact', () {
      final report = obfuscateJs('var v = store?.sessionToken;');
      expect(report.output, contains('.sessionToken'));
    });

    test('keeps object literal keys intact', () {
      final report = obfuscateJs('var cfg = { apiKey: 1, maxRetries: 2 };');
      expect(report.output, contains('apiKey:'));
      expect(report.output, contains('maxRetries:'));
    });

    test('keeps class method names intact', () {
      final report = obfuscateJs(
        'class Widget { render() { return 1; } }',
      );
      expect(report.output, contains('render()'));
    });

    test('never renames a protected global', () {
      const source = 'fetch(url); console.log(window.x); JSON.parse(s);';
      final report = obfuscateJs(source);
      expect(report.output, contains('fetch('));
      expect(report.output, contains('window.x'));
      expect(report.output, contains('JSON.parse'));
    });

    test('never renames a reserved word', () {
      final report = obfuscateJs('function f(){ return typeof 1; }');
      expect(report.output, contains('function'));
      expect(report.output, contains('return'));
      expect(report.output, contains('typeof'));
    });

    test('renames identifiers inside template substitutions', () {
      final report = obfuscateJs(
        r'const secretToken = "x"; const t = `value ${secretToken}`;',
      );
      expect(report.output, isNot(contains('secretToken')));
      // The substitution must still read a real binding.
      expect(report.output, contains(r'${'));
    });

    test('never generates a name starting with a digit', () {
      for (final style in ManglerStyle.values) {
        final report = obfuscateJs(
          'function alpha(){ var beta = 1; var gamma = 2; return beta+gamma; }',
          options: ObfuscatorOptions(style: style, hoistStrings: false),
        );
        final identifiers = _significant(report.output)
            .where((t) => t.type == JsTokenType.identifier)
            .map((t) => t.text);
        for (final name in identifiers) {
          expect(
            RegExp(r'^[0-9]').hasMatch(name),
            isFalse,
            reason: '$style produced "$name"',
          );
        }
      }
    });

    test('maps distinct bindings to distinct names', () {
      final report = obfuscateJs(
        'function outer(){ var first = 1; var second = 2;'
        ' var third = 3; return first + second + third; }',
        options: const ObfuscatorOptions(deadCodeInjection: false),
      );
      final identifiers = _significant(report.output)
          .where((t) => t.type == JsTokenType.identifier)
          .map((t) => t.text)
          .toSet();
      // outer, first, second, third -> four distinct names.
      expect(identifiers, hasLength(4));
    });

    test('is deterministic for a given seed', () {
      final a = obfuscateJs('var alphaValue = 1; return alphaValue;');
      final b = obfuscateJs('var alphaValue = 1; return alphaValue;');
      expect(a.output, b.output);
    });
  });

  group('string array pass', () {
    test('removes string literals from the statement body', () {
      final report = obfuscateJs('var password = "hunter2";');
      final table = RegExp(r'var __strs=\[[^\]]*\]').firstMatch(report.output)!;
      final body = report.output.replaceAll(table.group(0)!, '');
      expect(body, isNot(contains('hunter2')));
      expect(report.stringsHoisted, 1);
      expect(report.output, contains(StringArrayPass.arrayName));
    });

    test('reads the hoisted values back correctly', () {
      final report = obfuscateJs('log("alpha", "beta");');
      expect(report.output, contains('"alpha"'));
      expect(report.output, contains('"beta"'));
    });

    test('escapes quotes and control characters when re-encoding', () {
      final report = obfuscateJs(r'log("say \"hi\"\n");');
      // The hoisted entry must still be a single valid literal.
      final array = RegExp(
        r'var __strs=\[([^\]]*)\]',
      ).firstMatch(report.output)!.group(1)!;
      expect(array, contains(r'\"'));
      expect(array, contains(r'\n'));
    });

    test('leaves a directive prologue in place', () {
      final report = obfuscateJs(
        '"use strict"; var x = 1;',
        options: const ObfuscatorOptions(deadCodeInjection: false),
      );
      expect(report.output.trimLeft(), startsWith('"use strict";'));
      expect(report.stringsSkipped, 1);
    });

    test('can be turned off', () {
      final report = obfuscateJs(
        'var s = "text";',
        options: const ObfuscatorOptions(hoistStrings: false),
      );
      expect(report.output, contains('"text"'));
      expect(report.stringsHoisted, 0);
    });

    test('handles a string containing a comma', () {
      final report = obfuscateJs('log("Hello, ", "world");');
      final array = RegExp(
        r'var __strs=\[([^\]]*)\]',
      ).firstMatch(report.output)!.group(1)!;
      expect(array.split('"Hello, "'), hasLength(2));
    });
  });

  group('auxiliary passes', () {
    test('dead code injection keeps the program parseable', () {
      final report = obfuscateJs(
        'const { age } = person;\nconsole.log(age);',
        options: const ObfuscatorOptions(deadCodeInjection: true),
      );
      expect(report.output, contains('if(!![]&&![])'));
    });

    test('self-defending adds an integrity check', () {
      final report = obfuscateJs(
        'var s = "text";',
        options: const ObfuscatorOptions(selfDefending: true),
      );
      expect(report.output, contains('integrity check failed'));
    });

    test('console disabling rewrites call sites to a no-op alias', () {
      final report = obfuscateJs(
        'console.log("x");',
        options: const ObfuscatorOptions(disableConsoleOutput: true),
      );
      expect(report.output, isNot(contains('console.log')));
      expect(report.output, contains('__silentConsole.log'));
    });

    test('mangleIdentifiers: false leaves every name alone', () {
      const source = 'var keepMe = 1; function helper() { return keepMe; }';
      final report = obfuscateJs(
        source,
        options: const ObfuscatorOptions(
          mangleIdentifiers: false,
          deadCodeInjection: false,
        ),
      );
      expect(report.output, source);
      expect(report.identifiersRenamed, 0);
    });

    test('debug protection prepends a debugger trap', () {
      final report = obfuscateJs(
        'var x = 1;',
        options: const ObfuscatorOptions(debugProtection: true),
      );
      expect(report.output, contains('debugger'));
    });

    test('debug protection does not wrap the program in a closure', () {
      // Wrapping would move top-level declarations out of global scope.
      final report = obfuscateJs(
        'var globalFlag = 1;',
        options: const ObfuscatorOptions(
          debugProtection: true,
          mangleIdentifiers: false,
          deadCodeInjection: false,
        ),
      );
      // Prepended, not wrapped: no IIFE is closed around the body.
      expect(report.output, isNot(contains('})();')));
      expect(report.output.trimRight(), endsWith('var globalFlag = 1;'));
    });

    test('reports an error for empty input', () {
      final report = obfuscateJs('   ');
      expect(report.error, isNotNull);
      expect(report.output, isEmpty);
    });
  });

  group('node differential tests', () {
    final node = _node;
    if (node == null) {
      test('skipped because node is unavailable', () {});
      return;
    }

    /// Runs the same snippet before and after obfuscation and compares stdout.
    void behavesIdentically(
      String description,
      String source, {
      ObfuscatorOptions options = const ObfuscatorOptions(
        deadCodeInjection: false,
      ),
    }) {
      test(description, () {
        final expected = _runNode(source);
        final report = obfuscateJs(source, options: options);
        expect(report.error, isNull, reason: report.describe());
        expect(
          _runNode(report.output),
          expected,
          reason: 'obfuscated source:\n${report.output}',
        );
      });
    }

    behavesIdentically(
      'functions, loops and string concatenation',
      '''
function greet(name, times) {
  var out = [];
  for (var i = 0; i < times; i++) { out.push("Hello, " + name + "!"); }
  return out.join(", ");
}
console.log(greet("Ada", 2));
''',
    );

    behavesIdentically(
      'object literals, nesting and destructuring',
      '''
const user = { name: "Ada", age: 36, nested: { deep: true } };
const { age } = user;
console.log(age, user.nested.deep, user.name.length);
''',
    );

    behavesIdentically(
      'regex literals and division',
      r'''
const re = /ab+c/gi;
const half = 100 / 4 / 2;
console.log(re.test("xxABBBCyy"), half, "a/b".split("/").length);
''',
    );

    behavesIdentically(
      'template literals with substitutions',
      r'''

const firstName = "Ada";
const lastName = "Lovelace";
const full = `${firstName} ${lastName}`;
console.log(full, `${firstName.length}:${lastName.length}`);
''',
    );

    behavesIdentically(
      'classes, getters and methods',
      '''
class Store {
  constructor(items) { this.items = items; }
  get first() { return this.items[0]; }
  describe(prefix) { return prefix + this.items.length; }
}
const s = new Store([1, 2, 3]);
console.log(s.first, s.describe("n="), typeof Store);
''',
    );

    behavesIdentically(
      'arrow functions and closures',
      '''
const makeCounter = (start) => {
  let value = start;
  return { inc: () => ++value, read: () => value };
};
const counter = makeCounter(10);
counter.inc(); counter.inc();
console.log(counter.read());
''',
    );

    behavesIdentically(
      'try/catch and error types',
      '''
try { null.boom; } catch (err) { console.log(err instanceof TypeError); }
try { JSON.parse("{"); } catch (err) { console.log(err instanceof SyntaxError); }
''',
    );

    behavesIdentically(
      'labels, switch and fallthrough',
      '''
outer: for (let i = 0; i < 3; i++) {
  for (let j = 0; j < 3; j++) { if (j === 1) continue outer; }
}
let n = 0;
switch (2) { case 1: n += 1; case 2: n += 10; case 3: n += 100; break; default: n = -1; }
console.log(n);
''',
    );

    behavesIdentically(
      'a "use strict" directive prologue',
      r'''
"use strict";
const value = 1;
console.log(value, (function(){ return this === undefined; })());
''',
    );

    behavesIdentically(
      'dead code injection leaves behaviour unchanged',
      '''
function total(items) {
  var sum = 0;
  for (var i = 0; i < items.length; i++) { sum += items[i]; }
  return sum;
}
console.log(total([1, 2, 3, 4]));
''',
      options: const ObfuscatorOptions(deadCodeInjection: true),
    );

    behavesIdentically(
      'self-defending leaves behaviour unchanged',
      '''
var greeting = "hello";
console.log(greeting + " world");
''',
      options: const ObfuscatorOptions(selfDefending: true),
    );

    for (final style in ManglerStyle.values) {
      behavesIdentically(
        'the ${style.label} name style runs the same',
        '''
var firstName = "Grace";
var lastName = "Hopper";
function label() { return lastName + ", " + firstName; }
console.log(label());
''',
        options: ObfuscatorOptions(style: style, hoistStrings: false),
      );
    }

    test('the integrity check trips when the string table is edited', () {
      final report = obfuscateJs(
        'var s = "value";',
        options: const ObfuscatorOptions(selfDefending: true),
      );
      // Drop one element from the hoisted table.
      final tampered = report.output.replaceFirstMapped(
        RegExp(r'var __strs=\[[^\]]*\]'),
        (match) => 'var __strs=[]',
      );
      expect(tampered, isNot(report.output));
      expect(
        () => _runNode(tampered),
        throwsA(isA<StateError>()),
      );
    });

    test('disabling console silences output', () {
      final report = obfuscateJs(
        'console.log("should not appear");',
        options: const ObfuscatorOptions(disableConsoleOutput: true),
      );
      expect(_runNode(report.output).trim(), isEmpty);
    });
  });

  group('js obfuscator view', () {
    toolTest('obfuscates the loaded sample', 'js_obfuscator', (h) async {
      await loadSample(h);
      final output = h.text('Obfuscated source');
      expect(output, isNotEmpty);
      // The embedded secret moves into the string table rather than being
      // renamed; `apiKey` itself stays because it is an object key.
      expect(output, contains('sk-live-0123456789'));
      expect(output, isNot(contains('loadProfile')));
      expect(output, isNot(contains('class Store')));
      expect(output, isNot(contains('async function')));
    });

    toolTest('shows a report of what it did', 'js_obfuscator', (h) async {
      await loadSample(h);
      expect(find.textContaining('Identifiers renamed'), findsOneWidget);
      expect(find.textContaining('Strings hoisted'), findsOneWidget);
    });

    toolTest('toggling identifier renaming off leaves names alone',
        'js_obfuscator', (h) async {
      await h.enter('Paste JavaScript or TypeScript',
          text: 'var keepMe = 1; console.log(keepMe);');
      await h.tap('Rename identifiers');
      expect(h.text('Obfuscated source'), contains('keepMe'));
    });

    toolTest('clearing empties both panes', 'js_obfuscator', (h) async {
      await loadSample(h);
      expect(h.text('Obfuscated source'), isNotEmpty);
      await editorMenu(h, 'Clear');
      expect(h.text('Obfuscated source'), isEmpty);
      expect(h.text('Paste JavaScript or TypeScript'), isEmpty);
    });
  });
}
