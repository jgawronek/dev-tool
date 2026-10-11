import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:dev_tool/ui/widgets.dart';
import 'package:dev_tool/ui/tools/common/shared.dart';

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

/// Sets a [LabeledField] controller by its label.
Future<void> setLabeledField(
  WidgetTester tester,
  String label,
  String text,
) async {
  final field = tester.widget<LabeledField>(
    find.byWidgetPredicate((w) => w is LabeledField && w.label == label),
  );
  field.controller!.text = text;
  await tester.pump(const Duration(milliseconds: 200));
}

/// Sets an [InlineTextField] controller by its hint text.
Future<void> setInlineField(
  WidgetTester tester,
  String hint,
  String text,
) async {
  final field = tester.widget<InlineTextField>(
    find.byWidgetPredicate((w) => w is InlineTextField && w.hintText == hint),
  );
  field.controller!.text = text;
  field.onChanged?.call(text);
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('UUID/ULID Generate/Decode', () {
    const tool = 'uuid_ulid_generate_decode';
    const generatedHint = 'Generated IDs...';
    const inputHint = '00000000-0000-0000-0000-000000000000';
    final uuidV4 = RegExp(
      r'^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$',
    );
    final surface = const Size(1500, 1000);

    toolTest('generates uppercase UUID v4 by default', tool, (h) async {
      await h.tap('Generate', index: 1);
      expect(
        uuidV4.hasMatch(h.text(generatedHint)),
        isTrue,
        reason: h.text(generatedHint),
      );
    }, surface: surface);

    toolTest('generates the requested count', tool, (h) async {
      await setInlineField(h.tester, '1', '3');
      await h.tap('Generate', index: 1);
      final lines = h.text(generatedHint).trim().split('\n');
      expect(lines, hasLength(3));
      for (final line in lines) {
        expect(uuidV4.hasMatch(line), isTrue, reason: line);
      }
    }, surface: surface);

    toolTest('generates lowercase when enabled', tool, (h) async {
      await h.tester.tap(find.byType(Checkbox).first);
      await h.settle();
      await h.tap('Generate', index: 1);
      final out = h.text(generatedHint);
      expect(out, out.toLowerCase());
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(out),
        isTrue,
        reason: out,
      );
    }, surface: surface);

    toolTest('decodes a UUID into version and variant', tool, (h) async {
      await h.enter(inputHint, text: '110ec58a-a0f2-4ac4-8393-c866d813b8d1');
      expect(find.text('UUID v4'), findsWidgets);
      expect(find.text('RFC 4122'), findsOneWidget);
    }, surface: surface);

    toolTest('generates ULIDs with valid shape', tool, (h) async {
      await h.tap('UUID v4');
      await h.tap('ULID');
      await h.tap('Generate', index: 1);
      final out = h.text(generatedHint).trim();
      expect(
        RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$').hasMatch(out),
        isTrue,
        reason: out,
      );
    }, surface: surface);

    toolTest('invalid UUID surfaces an error', tool, (h) async {
      await h.enter(inputHint, text: 'not-a-uuid');
      expect(find.text('Not a valid UUID or ULID.'), findsOneWidget);
    }, surface: surface);
  });

  group('Random String Generator', () {
    const tool = 'random_string_generator';

    toolTest('generates with the default field recipe', tool, (h) async {
      await h.tap('Load sample');
      final out = h.text('Generated strings...').trim().split('\n');
      expect(out, hasLength(10), reason: out.join('|')); // count x10 default
      for (final line in out) {
        expect(
          line,
          hasLength(46),
        ); // 18 upper + 18 lower + 2 symbols + 8 digits
        expect(line, contains(RegExp(r'[A-Z]')));
        expect(line, contains(RegExp(r'[a-z]')));
        expect(line, contains(RegExp(r'[0-9]')));
      }
    });

    toolTest('respects custom counts', tool, (h) async {
      await setLabeledField(h.tester, 'Uppercased Characters', '2');
      await setLabeledField(h.tester, 'Lowercased Characters', '3');
      await setLabeledField(h.tester, 'Symbols', '0');
      await setLabeledField(h.tester, 'Digits', '1');
      await h.tap('Load sample');
      final out = h.text('Generated strings...').trim().split('\n');
      expect(out.first, hasLength(6));
      expect(RegExp(r'[A-Z]').allMatches(out.first), hasLength(2));
      expect(RegExp(r'[a-z]').allMatches(out.first), hasLength(3));
      expect(RegExp(r'\d').allMatches(out.first), hasLength(1));
    });
  });

  group('QR Code Reader/Generator', () {
    const tool = 'qr_code_reader_generator';

    toolTest('renders a QR preview for text content', tool, (h) async {
      await h.enter('BEGIN:VCARD...', text: 'https://devutils.app');
      expect(find.byType(QrImageView), findsOneWidget);
    });

    toolTest('template dropdown applies vCard structure', tool, (h) async {
      await h.tap('Plain text');
      await h.tap('vCard');
      expect(h.text('BEGIN:VCARD...'), contains('BEGIN:VCARD'));
    });
  });
}
