import 'package:flutter_test/flutter_test.dart';
import 'package:dev_tool/ui/widgets.dart';
import '../helpers/tool_harness.dart';

void main() {
  void field(WidgetTester tester, String label, String value) {
    tester
            .widget<LabeledField>(
              find.byWidgetPredicate(
                (w) => w is LabeledField && w.label == label,
              ),
            )
            .controller!
            .text =
        value;
  }

  testWidgets(
    'random strings: seeds, Unicode alphabet, grouping, words, invalid input recovery',
    (tester) async {
      final h = ToolHarness(tester);
      await h.open('random_string_generator');
      field(tester, 'Seed (optional)', '123');
      await h.tap('Generate');
      final first = h.text(null);
      expect(first.split('\n'), hasLength(10));
      await h.tap('Generate');
      expect(h.text(null), first);
      field(tester, 'Seed (optional)', '124');
      await h.tap('Generate');
      expect(h.text(null), isNot(first));
      for (final label in ['Lowercased Characters', 'Symbols', 'Digits']) {
        field(tester, label, '0');
      }
      field(tester, 'Uppercased Characters', '7');
      field(tester, 'Custom Character Set', '🙂漢');
      field(tester, 'Separating Group Size', '3');
      field(tester, 'Separator', '-');
      await h.tap('Generate');
      for (final line in h.text(null).split('\n')) {
        final groups = line.split('-');
        expect(groups.map((g) => g.runes.length).toList(), [3, 3, 1]);
        expect(
          groups.join().runes.every((r) => '🙂漢'.runes.contains(r)),
          isTrue,
        );
      }
      field(tester, 'Uppercased Characters', '0');
      field(tester, 'Words', '3');
      await h.tap('Generate');
      for (final line in h.text(null).split('\n')) {
        expect(line.split('-'), hasLength(3));
        expect(line, matches(RegExp(r'^[a-z]+-[a-z]+-[a-z]+$')));
      }
      final previous = h.text(null);
      final batch = tester.widget<SmallDropdown>(
        find.byWidgetPredicate(
          (w) => w is SmallDropdown && w.items.contains('x20'),
        ),
      );
      batch.onChanged!('x20');
      await h.settle();
      expect(h.text(null).split('\n'), hasLength(20));
      expect(h.text(null).split('\n').take(10).join('\n'), previous);
      for (final invalid in ['-1', '101', 'abc']) {
        field(tester, 'Words', invalid);
        await h.tap('Generate');
        expect(h.text(null), isEmpty);
        expect(
          find.text('Word count must be a number from 0 to 100.'),
          findsOneWidget,
        );
      }
      field(tester, 'Words', '3');
      field(tester, 'Seed (optional)', 'invalid');
      await h.tap('Generate');
      expect(h.text(null), isEmpty);
      expect(
        find.textContaining('Seed must be a whole number'),
        findsOneWidget,
      );
      field(tester, 'Seed (optional)', '');
      await h.tap('Generate');
      expect(h.text(null).split('\n'), hasLength(20));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'each random string preset has exactly its advertised character counts',
    (tester) async {
      final h = ToolHarness(tester);
      await h.open('random_string_generator');
      const expected = {
        'Password': [4, 14, 4, 6],
        'API key': [0, 32, 0, 16],
        'PIN': [0, 0, 0, 6],
        'Token': [12, 24, 0, 12],
        'Slug': [0, 24, 0, 4],
      };
      for (final entry in expected.entries) {
        tester
            .widget<SmallDropdown>(
              find.byWidgetPredicate(
                (w) => w is SmallDropdown && w.items.contains('Password'),
              ),
            )
            .onChanged!(entry.key);
        await h.settle();
        for (final line in h.text(null).split('\n')) {
          final actual = [
            RegExp('[A-Z]').allMatches(line).length,
            RegExp('[a-z]').allMatches(line).length,
            RegExp(r'[!@#$%^&*]').allMatches(line).length,
            RegExp('[0-9]').allMatches(line).length,
          ];
          expect(actual, entry.value, reason: entry.key);
          expect(line.length, entry.value.reduce((a, b) => a + b));
        }
      }
      expect(tester.takeException(), isNull);
    },
  );
}
