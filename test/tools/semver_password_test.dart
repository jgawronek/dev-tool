import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/password_generator_service.dart';
import 'package:dev_tool/services/semver_service.dart';

import '../helpers/tool_harness.dart';

void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body,
) {
  testWidgets(description, (tester) async {
    final h = ToolHarness(tester);
    await h.open(toolId, surface: const Size(1600, 1200));
    await body(h);
  });
}

/// Sets the text field carrying [label] in the form-style tools.
Future<void> setLabelled(
  ToolHarness h,
  String label,
  String value,
) async {
  final field = h.tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((f) => f.decoration?.labelText == label);
  field.controller!.text = value;
  field.onChanged!(value);
  await h.settle();
}

String visibleText(ToolHarness h) =>
    h.tester.widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => '${w.data ?? ''}\n${w.selectionControls == null ? '' : ''}')
        .join('\n');

void main() {
  group('semver tool view', () {
    toolTest('compares two versions', 'semver_calculator', (h) async {
      await setLabelled(h, 'A', '1.2.3');
      await setLabelled(h, 'B', '2.0.0');
      expect(find.textContaining('left is older'), findsWidgets);
      expect(find.textContaining('major (1)'), findsWidgets);
      expect(find.textContaining('Next major   2.0.0'), findsWidgets);
    });

    toolTest('says equal for identical versions', 'semver_calculator', (h) async {
      await setLabelled(h, 'A', '1.2.3');
      await setLabelled(h, 'B', '1.2.3');
      expect(find.textContaining('equal'), findsWidgets);
    });

    toolTest('resolves a caret range', 'semver_calculator', (h) async {
      await setLabelled(h, 'Range', '^1.2.0');
      expect(find.textContaining('highest satisfying: 1.9.9'), findsWidgets);
    });

    toolTest('reports an unparseable version', 'semver_calculator', (h) async {
      await setLabelled(h, 'A', 'not-a-version');
      expect(
        find.textContaining('Not a valid semantic version'),
        findsOneWidget,
      );
    });

    toolTest('swap exchanges the two versions', 'semver_calculator', (h) async {
      await setLabelled(h, 'A', '1.0.0');
      await setLabelled(h, 'B', '2.0.0');
      await h.tap('Swap');
      expect(find.textContaining('left is newer'), findsOneWidget);
    });
  });

  group('password generator tool view', () {
    toolTest('generates a value on open', 'password_generator', (h) async {
      expect(find.text('Regenerate'), findsOneWidget);
      expect(find.textContaining('characters from a'), findsOneWidget);
    });

    toolTest('regenerating produces a different value', 'password_generator',
        (h) async {
      final before = (find.byType(SelectableText).evaluate().first.widget
              as SelectableText)
          .data;
      await h.tap('Regenerate');
      await h.settle();
      final after = (find.byType(SelectableText).evaluate().first.widget
              as SelectableText)
          .data;
      expect(after, isNot(before));
      expect(after, isNotEmpty);
    });

    toolTest('switching to passphrase changes the summary', 'password_generator',
        (h) async {
      await h.tap('Random characters');
      await h.tap('Wordlist passphrase');
      await h.settle();
      expect(find.textContaining('words from a'), findsOneWidget);
    });

    toolTest('switching to token reports 128 bits', 'password_generator',
        (h) async {
      await h.tap('Random characters');
      await h.tap('UUID / token');
      await h.settle();
      expect(find.textContaining('128 bits'), findsOneWidget);
    });

    toolTest('shows crack-time estimates', 'password_generator', (h) async {
      expect(find.textContaining('Online crack:'), findsOneWidget);
      expect(find.textContaining('Offline (fast hash):'), findsOneWidget);
    });

    toolTest('copy controls are present', 'password_generator', (h) async {
      expect(find.text('Copy'), findsOneWidget);
    });
  });

  group('semver parsing', () {
    test('parses a full version', () {
      final version = parseSemVer('1.2.3')!;
      expect(version.major, 1);
      expect(version.minor, 2);
      expect(version.patch, 3);
      expect(version.isPrerelease, isFalse);
    });

    test('parses pre-release and build metadata', () {
      final version = parseSemVer('1.0.0-alpha.1+build.5')!;
      expect(version.preRelease, ['alpha', '1']);
      expect(version.build, 'build.5');
      expect(version.isPrerelease, isTrue);
      expect(version.toString(), '1.0.0-alpha.1+build.5');
    });

    test('rejects invalid versions', () {
      expect(parseSemVer('1.2'), isNull);
      expect(parseSemVer('1.2.3.4'), isNull);
      expect(parseSemVer('01.2.3'), isNull);
      expect(parseSemVer('1.2.x'), isNull);
      expect(parseSemVer('a.b.c'), isNull);
      expect(parseSemVer('1.2.3-'), isNull);
      expect(parseSemVer('1.2.3+'), isNull);
      expect(parseSemVer(''), isNull);
    });
  });

  group('semver precedence', () {
    test('matches the canonical semver.org ordering chain', () {
      const chain = [
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-alpha.beta',
        '1.0.0-beta',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-rc.1',
        '1.0.0',
      ];
      for (var i = 0; i < chain.length - 1; i++) {
        expect(
          compareSemVer(parseSemVer(chain[i])!, parseSemVer(chain[i + 1])!),
          lessThan(0),
          reason: '${chain[i]} should precede ${chain[i + 1]}',
        );
      }
    });

    test('build metadata is ignored for ordering', () {
      expect(
        compareSemVer(parseSemVer('1.0.0+a')!, parseSemVer('1.0.0+b')!),
        0,
      );
    });

    test('a pre-release sorts below its stable release', () {
      expect(compareSemVer(parseSemVer('1.0.0-rc.1')!, parseSemVer('1.0.0')!), lessThan(0));
    });

    test('numeric identifiers compare numerically, not as text', () {
      expect(compareSemVer(parseSemVer('1.0.0-2')!, parseSemVer('1.0.0-11')!), lessThan(0));
    });

    test('numeric identifiers rank below alphanumeric ones', () {
      expect(compareSemVer(parseSemVer('1.0.0-1')!, parseSemVer('1.0.0-alpha')!), lessThan(0));
    });
  });

  group('range resolution', () {
    // Every expectation here was produced by the reference `semver` npm
    // package's maxSatisfying() over the same version list.
    final available = <String>[
      '0.9.0',
      '0.9.9',
      '1.0.0-alpha',
      '1.0.0',
      '1.0.1',
      '1.1.0',
      '1.2.0',
      '1.2.3',
      '1.2.4',
      '1.5.0',
      '1.9.9',
      '2.0.0-rc.1',
      '2.0.0',
      '3.0.0',
    ].map(parseSemVer).whereType<SemVer>().toList();

    const expectations = <String, String>{
      '^1.2.3': '1.9.9',
      '~1.2.3': '1.2.4',
      '1.2': '1.2.4',
      '1': '1.9.9',
      '1.x': '1.9.9',
      '1.2.x': '1.2.4',
      '*': '3.0.0',
      '>=1.2.0 <2.0.0': '1.9.9',
      '1.2.3 - 1.2.9': '1.2.4',
      '>1.0.0': '3.0.0',
      '>1.2.3': '3.0.0',
      '<=1.2.3': '1.2.3',
      '=1.2.3': '1.2.3',
      // ^0.x is narrower than ^1.x, so nothing here satisfies it.
      '^0.2.3': '',
      '^0.0.3': '',
    };

    expectations.forEach((range, expected) {
      test('"$range" resolves to ${expected.isEmpty ? 'no match' : expected}', () {
        expect(resolveRange(range, available).highest, expected);
      });
    });

    test('pre-releases are excluded unless the range names one', () {
      expect(resolveRange('^1.0.0', available).matched.map((v) => v.toString()),
          isNot(contains('1.0.0-alpha')));
      expect(resolveRange('>=1.0.0-alpha', available).matched.map((v) => v.toString()),
          contains('1.0.0-alpha'));
    });

    test('an unparseable range matches nothing rather than everything', () {
      expect(resolveRange('not-a-range', available).matched, isEmpty);
    });
  });

  group('diff and bump', () {
    test('classifies the size of a change', () {
      expect(
        describeDiff(diffSemVer(parseSemVer('1.2.3')!, parseSemVer('2.0.0')!)),
        'major (1)',
      );
      expect(
        describeDiff(diffSemVer(parseSemVer('1.2.3')!, parseSemVer('1.3.0')!)),
        'minor (1)',
      );
      expect(
        describeDiff(diffSemVer(parseSemVer('1.2.3')!, parseSemVer('1.2.4')!)),
        'patch (1)',
      );
      expect(
        describeDiff(diffSemVer(parseSemVer('1.2.3')!, parseSemVer('1.2.3')!)),
        'no change',
      );
    });

    test('detects a pre-release change', () {
      expect(
        describeDiff(diffSemVer(parseSemVer('1.2.3')!, parseSemVer('1.2.3-rc.1')!)),
        'pre-release change',
      );
    });

    test('bumps reset the lower components', () {
      final base = parseSemVer('1.2.3')!;
      expect(bumpSemVer(base, 'major').toString(), '2.0.0');
      expect(bumpSemVer(base, 'minor').toString(), '1.3.0');
      expect(bumpSemVer(base, 'patch').toString(), '1.2.4');
    });

    test('the report names the differing components', () {
      final report = compareReport(parseSemVer('1.2.3')!, parseSemVer('1.3.0')!);
      expect(report, contains('left is older'));
      expect(report, contains('Minor      2 vs 3  (differs)'));
      expect(report, contains('Patch      3 vs 0'));
    });
  });

  group('password generation', () {
    test('random characters honour the requested length', () {
      final secret = generateSecret(const PasswordOptions(length: 24));
      expect(secret.value, hasLength(24));
    });

    test('length is clamped to a sane range', () {
      expect(generateSecret(const PasswordOptions(length: 1)).value, hasLength(4));
      expect(generateSecret(const PasswordOptions(length: 999)).value, hasLength(256));
    });

    test('selected classes drive the alphabet', () {
      final lowerOnly = generateSecret(
        const PasswordOptions(length: 60, includeUpper: false, includeDigits: false),
      );
      expect(lowerOnly.value, matches(RegExp(r'^[a-z]+$')));
      final withDigits = generateSecret(
        const PasswordOptions(length: 80, includeUpper: false),
      );
      expect(withDigits.value, matches(RegExp(r'^[a-z0-9]+$')));
    });

    test('entropy grows with length', () {
      final short = generateSecret(const PasswordOptions(length: 8));
      final long = generateSecret(const PasswordOptions(length: 32));
      expect(long.bitsOfEntropy, greaterThan(short.bitsOfEntropy));
    });

    test('passphrases use the wordlist and separator', () {
      final secret = generateSecret(
        const PasswordOptions(style: PasswordStyle.passphrase, words: 5, separator: '_'),
      );
      final parts = secret.value.split('_');
      expect(parts, hasLength(5));
      expect(secret.words, hasLength(5));
      expect(secret.bitsOfEntropy, greaterThan(40));
    });

    test('capitalised passphrases are title-cased', () {
      final secret = generateSecret(
        const PasswordOptions(
          style: PasswordStyle.passphrase,
          words: 4,
          capitalizeWords: true,
        ),
      );
      for (final word in secret.words) {
        expect(word[0], word[0].toUpperCase());
      }
    });

    test('PINs are numeric and sized', () {
      final secret = generateSecret(
        const PasswordOptions(style: PasswordStyle.pin, length: 6),
      );
      expect(secret.value, matches(RegExp(r'^\d{6}$')));
    });

    test('tokens are 128-bit UUID formatted', () {
      final secret = generateSecret(const PasswordOptions(style: PasswordStyle.uuidToken));
      expect(secret.value, matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')));
      expect(secret.bitsOfEntropy, 128);
    });

    test('successive generations differ', () {
      final first = generateSecret(const PasswordOptions(length: 32));
      final second = generateSecret(const PasswordOptions(length: 32));
      expect(first.value, isNot(second.value));
    });
  });

  group('crack time estimates', () {
    test('weak secrets are called out as fast to break', () {
      // 2^20 guesses at 1e10/s is a fraction of a second.
      expect(estimateCrackTime(20), 'instant');
      expect(estimateCrackTime(35), contains('seconds'));
      expect(estimateCrackTime(50), contains('hours'));
    });

    test('strong secrets are reported as long', () {
      expect(estimateCrackTime(128), contains('age of the universe'));
      expect(estimateCrackTime(0), 'instant');
    });

    test('an offline hash is faster than an online rate limit', () {
      expect(estimateOfflineCrackTime(64), isNot(estimateCrackTime(64)));
    });
  });
}