import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/chmod_service.dart';

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

void main() {
  ChmodInfo parse(String value) => parseChmod(value)!.info!;

  group('tool view', () {
    /// The tool exposes a single "Octal or symbolic" text field.
    Future<void> enterMode(ToolHarness h, String value) async {
      final field = h.tester.widgetList<TextField>(find.byType(TextField)).firstWhere(
        (f) => f.decoration?.labelText == 'Octal or symbolic',
      );
      field.controller!.text = value;
      field.onChanged!(value);
      await h.settle();
    }

    toolTest('shows octal and symbolic for the default mode', 'chmod_calculator',
        (h) async {
      expect(find.text('755'), findsWidgets);
      expect(find.text('rwxr-xr-x'), findsWidgets);
    });

    toolTest('converts symbolic input', 'chmod_calculator', (h) async {
      await enterMode(h, 'rwsr-xr-x');
      expect(find.text('4755'), findsWidgets);
      expect(find.textContaining('Setuid'), findsWidgets);
    });

    toolTest('rejects a non-mode', 'chmod_calculator', (h) async {
      await enterMode(h, '999');
      expect(find.textContaining('Not a mode'), findsOneWidget);
    });

    toolTest('toggling a bit updates the mode', 'chmod_calculator', (h) async {
      await enterMode(h, '644');
      // The first 'All' belongs to the owner class, so 644 -> 744.
      await h.tap('All', index: 0);
      expect(find.text('744'), findsWidgets);
      expect(find.text('rwxr--r--'), findsWidgets);
    });

    toolTest('presets load their mode', 'chmod_calculator', (h) async {
      await h.tap('1777');
      expect(find.text('1777'), findsWidgets);
      expect(find.text('rwxrwxrwt'), findsWidgets);
    });

    toolTest('copy controls are present', 'chmod_calculator', (h) async {
      expect(find.text('Copy chmod'), findsOneWidget);
      expect(find.text('Copy report'), findsOneWidget);
    });
  });

  group('octal parsing', () {
    test('common modes', () {
      expect(parse('755').symbolic, 'rwxr-xr-x');
      expect(parse('644').symbolic, 'rw-r--r--');
      expect(parse('600').symbolic, 'rw-------');
      expect(parse('700').symbolic, 'rwx------');
      expect(parse('777').symbolic, 'rwxrwxrwx');
      expect(parse('775').symbolic, 'rwxrwxr-x');
      expect(parse('000').symbolic, '---------');
      expect(parse('400').symbolic, 'r--------');
    });

    test('octal digits decompose correctly', () {
      final info = parse('754');
      expect(info.user.octal, 7);
      expect(info.group.octal, 5);
      expect(info.other.octal, 4);
      expect(info.symbolic, 'rwxr-xr--');
    });

    test('special bits produce a single leading digit', () {
      final setuid = parse('4755');
      expect(setuid.octal, '4755');
      expect(setuid.symbolic, 'rwsr-xr-x');
      expect(setuid.setuid, isTrue);

      final setgid = parse('2755');
      expect(setgid.octal, '2755');
      expect(setgid.symbolic, 'rwxr-sr-x');
      expect(setgid.setgid, isTrue);

      final sticky = parse('1777');
      expect(sticky.octal, '1777');
      expect(sticky.symbolic, 'rwxrwxrwt');
      expect(sticky.sticky, isTrue);
    });

    test('combined special bits', () {
      final both = parse('6755');
      expect(both.setuid, isTrue);
      expect(both.setgid, isTrue);
      expect(both.octal, '6755');
      final all = parse('7777');
      expect(all.octal, '7777');
      expect(all.symbolic, 'rwsrwsrwt');
    });

    test('modes with no special bits are three digits', () {
      expect(parse('755').octal, '755');
      expect(parse('644').octal, '644');
    });
  });

  group('symbolic parsing', () {
    test('parses standard symbolic forms', () {
      expect(parse('rwxr-xr-x').octal, '755');
      expect(parse('rw-r--r--').octal, '644');
      expect(parse('rwsr-xr-x').octal, '4755');
      expect(parse('rwxrwxrwt').octal, '1777');
    });

    test('uppercase S means setuid without execute', () {
      final info = parse('rwSr-xr-x');
      expect(info.user.execute, isFalse);
      expect(info.symbolic, 'rwSr-xr-x');
      expect(info.octal, '4655');
      expect(info.setuid, isTrue);
    });

    test('uppercase T means sticky without execute', () {
      final info = parse('rwxrwxr-T');
      expect(info.other.execute, isFalse);
      expect(info.symbolic, 'rwxrwxr-T');
      expect(info.octal, '1774');
      expect(info.sticky, isTrue);
    });

    test('round trips octal through symbolic and back', () {
      for (final mode in ['755', '644', '600', '400', '4755', '2755', '1777']) {
        final first = parse(mode);
        expect(parse(first.symbolic).octal, mode, reason: mode);
      }
    });
  });

  group('relative modes', () {
    test('a=rwx grants everything', () {
      expect(parse('a=rwx').octal, '777');
    });

    test('u+x grants execute to the owner only', () {
      expect(parse('u+x').octal, '700');
    });

    test('go-w removes write from group and other', () {
      expect(parse('go-w').octal, '000');
      final info = parse('go-w');
      expect(info.user.octal, 0);
    });

    test('a-s clears setuid', () {
      expect(parse('u+s').setuid, isTrue);
      expect(parse('u-s').setuid, isFalse);
    });
  });

  group('bit toggling', () {
    test('clearing and setting a whole class', () {
      final info = parse('755');
      expect(info.setAll(ChmodClass.group, false).symbolic, 'rwx---r-x');
      expect(info.setAll(ChmodClass.group, true).symbolic, 'rwxrwxr-x');
    });

    test('toggling inverts the bits', () {
      final info = parse('755');
      expect(info.toggle(ChmodClass.user).symbolic, '---r-xr-x');
      expect(info.toggle(ChmodClass.other).symbolic, 'rwxr-x-w-');
    });

    test('withClass replaces only the target class', () {
      final info = parse('644');
      final updated = info.withClass(
        ChmodClass.user,
        const PermissionBits(read: true, write: true, execute: true),
      );
      expect(updated.symbolic, 'rwxr--r--');
      expect(updated.octal, '744');
    });

    test('withBits toggles specials independently', () {
      final info = parse('755');
      expect(info.withBits(setuid: true).octal, '4755');
      expect(info.withBits(setuid: true).setgid, isFalse);
      expect(info.withBits(sticky: true).octal, '1755');
    });
  });

  group('rejections', () {
    test('non-modes return null', () {
      expect(parseChmod('999'), isNull);
      expect(parseChmod('xyz'), isNull);
      expect(parseChmod('77777'), isNull);
      expect(parseChmod(''), isNull);
      expect(parseChmod('12'), isNull);
    });

    test('an unknown special prefix is reported', () {
      expect(() => parseChmod('5777'), throwsFormatException);
    });
  });

  group('report', () {
    test('lists octal, symbolic and per-class detail', () {
      final report = parse('4755').toReport();
      expect(report, contains('4755'));
      expect(report, contains('rwsr-xr-x'));
      expect(report, contains('Setuid'));
      expect(report, contains('set-user-ID'));
    });

    test('omits specials that are not set', () {
      expect(parse('755').toReport(), isNot(contains('Sticky')));
    });
  });

  group('presets', () {
    test('every advertised preset parses', () {
      for (final mode in commonModes.keys) {
        final parsed = parseChmod(mode);
        expect(parsed, isNotNull, reason: mode);
        expect(parsed!.info, isNotNull, reason: mode);
      }
    });
  });
}