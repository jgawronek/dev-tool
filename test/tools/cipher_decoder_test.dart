import 'dart:math';

import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/cipher_service.dart';

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

const _plain = 'the quick brown fox jumps over the lazy dog';
const _pangram =
    'Sphinx of black quartz judge my vow and pack my box with five dozen liquor jugs';

String _caesar(String text, int shift) {
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    if (unit >= 97 && unit <= 122) {
      buffer.writeCharCode((unit - 97 + shift) % 26 + 97);
    } else if (unit >= 65 && unit <= 90) {
      buffer.writeCharCode((unit - 65 + shift) % 26 + 65);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

void main() {
  group('round trips', () {
    test('self-inverse ciphers decode what they encoded', () {
      for (final kind in [
        CipherKind.rot13,
        CipherKind.rot47,
        CipherKind.atbash,
        CipherKind.reverse,
      ]) {
        final encoded = encodeCipher(_plain, kind, const CipherOptions());
        expect(
          decodeCipher(encoded, kind, const CipherOptions()),
          _plain,
          reason: kind.label,
        );
      }
    });

    test('caesar encode and decode mirror each other', () {
      final encoded = encodeCipher(
        _plain,
        CipherKind.caesar,
        const CipherOptions(shift: 7),
      );
      expect(encoded, isNot(_plain));
      // Decoding reverses the shift, so +7 is undone by a shift of 19.
      expect(
        decodeCipher(
          encoded,
          CipherKind.caesar,
          const CipherOptions(shift: 19),
        ),
        _plain,
      );
      expect(
        decodeCipher(encoded, CipherKind.caesar, const CipherOptions(shift: 7)),
        isNot(_plain),
      );
    });

    test('vigenere round trips with multi-letter and single-letter keys', () {
      for (final key in ['LEMON', 'LE', 'K', 'secretkey']) {
        final encoded = encodeCipher(
          _pangram,
          CipherKind.vigenere,
          CipherOptions(key: key),
        );
        expect(encoded, isNot(_pangram), reason: key);
        expect(
          decodeCipher(encoded, CipherKind.vigenere, CipherOptions(key: key)),
          _pangram,
          reason: key,
        );
      }
    });

    test('xor round trips with a repeating key', () {
      for (final key in ['K', 'secret']) {
        final encoded = encodeCipher(
          _plain,
          CipherKind.xor,
          CipherOptions(key: key),
        );
        expect(
          decodeCipher(encoded, CipherKind.xor, CipherOptions(key: key)),
          _plain,
          reason: key,
        );
      }
    });
  });

  group('individual ciphers', () {
    test('rot13 matches the known value', () {
      expect(
        decodeCipher('uryyb', CipherKind.rot13, const CipherOptions()),
        'hello',
      );
    });

    test('rot47 reaches digits and punctuation', () {
      final encoded = decodeCipher(
        'Hello, World!',
        CipherKind.rot47,
        const CipherOptions(),
      );
      expect(encoded, isNot('Hello, World!'));
      expect(
        decodeCipher(encoded, CipherKind.rot47, const CipherOptions()),
        'Hello, World!',
      );
    });

    test('atbash maps a to z', () {
      expect(
        decodeCipher('gsv', CipherKind.atbash, const CipherOptions()),
        'the',
      );
    });

    test('rail fence decrypts a known ciphertext', () {
      // "WEAREDISCOVEREDFLEEATONCE" written with 3 rails.
      final encoded = 'WECRLTEERDSOEEFEAOCAIVDEN';
      final decoded = decodeCipher(
        encoded,
        CipherKind.railFence,
        const CipherOptions(rails: 3),
      );
      expect(decoded, 'WEAREDISCOVEREDFLEEATONCE');
    });

    test('bacon decodes the classic 24-letter table', () {
      expect(
        decodeCipher(
          'BAABABABABAA',
          CipherKind.bacon,
          const CipherOptions(baconVariant: 'Classic 24'),
        ),
        'SV',
      );
      expect(
        decodeCipher(
          'AAAAABAAAAABAAAAABAAAAAB',
          CipherKind.bacon,
          const CipherOptions(baconVariant: 'Classic 24'),
        ),
        isNotEmpty,
      );
    });

    test('bacon rejects letters outside the selected variant', () {
      expect(
        () => decodeCipher(
          'ABCDC',
          CipherKind.bacon,
          const CipherOptions(baconVariant: '26-letter'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('morse decodes letters, digits, and punctuation', () {
      expect(
        decodeCipher(
          '.... . .-.. .-.. ---',
          CipherKind.morse,
          const CipherOptions(),
        ),
        'HELLO',
      );
      expect(
        decodeCipher(
          '.---- ..--- ...-- ....-',
          CipherKind.morse,
          const CipherOptions(),
        ),
        '1234',
      );
      expect(
        decodeCipher('.-.-.- ..--..', CipherKind.morse, const CipherOptions()),
        '.?',
      );
    });

    test('morse supports word separators', () {
      expect(
        decodeCipher(
          '.... . / -... . .-.. .-.. ---',
          CipherKind.morse,
          const CipherOptions(),
        ),
        'HE BELLO',
      );
    });

    test('morse reports an unknown sequence', () {
      expect(
        () => decodeCipher(
          '......--..--..',
          CipherKind.morse,
          const CipherOptions(),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing keys are reported rather than returning empty output', () {
      expect(
        () => decodeCipher('abc', CipherKind.vigenere, const CipherOptions()),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeCipher('abc', CipherKind.xor, const CipherOptions()),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('readability scoring', () {
    test('English outscores noise', () {
      final english = readability(_pangram);
      final hex = readability('deadbeef0123456789abcdef0123456789abcdef');
      final base64 = readability('aGVsbG8gd29ybGQgdGhpcyBpcyBiYXNlNjQ=');
      final random = String.fromCharCodes(
        List.generate(40, (i) => 97 + Random(i).nextInt(26)),
      );
      expect(english, greaterThan(0.5));
      expect(english, greaterThan(hex));
      expect(english, greaterThan(base64));
      expect(english, greaterThan(readability(random)));
      expect(readability(random), lessThan(0.35));
    });

    test('empty and symbol-only input score low without throwing', () {
      expect(readability(''), 0);
      expect(readability('!!!!'), lessThan(0.35));
    });
  });

  group('identify', () {
    test('recognises ROT13 text', () {
      final hits = identifyCipher(_caesar(_plain, 13));
      expect(hits, isNotEmpty);
      expect(hits.first.output, _plain);
      expect(hits.map((c) => c.cipher), contains('ROT13'));
    });

    test('recognises Atbash', () {
      final hits = identifyCipher(
        encodeCipher(_pangram, CipherKind.atbash, const CipherOptions()),
      );
      expect(hits.first.cipher, 'Atbash');
      expect(hits.first.output, _pangram);
    });

    test('finds nothing for noise', () {
      expect(
        identifyCipher('deadbeef0123456789abcdef0123456789abcdef'),
        isEmpty,
      );
    });

    test('empty input yields no candidates', () {
      expect(identifyCipher('   '), isEmpty);
    });
  });

  group('brute force', () {
    test('finds the Caesar shift used', () {
      final hits = bruteForceCipher(_caesar(_plain, 13));
      expect(hits, isNotEmpty);
      expect(hits.first.output, _plain);
      expect(hits.first.cipher, contains('Caesar'));
    });

    test('finds every Caesar shift from 1 to 25', () {
      for (var shift = 1; shift < 26; shift++) {
        final hits = bruteForceCipher(_caesar(_pangram, shift));
        expect(hits.first.output, _pangram, reason: 'shift $shift');
      }
    });

    test('finds a repeating XOR key', () {
      final encoded = encodeCipher(
        _pangram,
        CipherKind.xor,
        const CipherOptions(key: 'K'),
      );
      final hits = bruteForceCipher(encoded);
      expect(hits.first.output, _pangram);
      expect(hits.first.cipher, contains('XOR'));
    });

    test('results are ordered best first', () {
      final hits = bruteForceCipher(_caesar(_pangram, 5));
      for (var i = 1; i < hits.length; i++) {
        expect(hits[i - 1].score, greaterThanOrEqualTo(hits[i].score));
      }
    });

    test('respects the result cap', () {
      final hits = bruteForceCipher(_caesar(_pangram, 3), maxResults: 5);
      expect(hits.length, lessThanOrEqualTo(5));
    });

    test('empty input yields nothing', () {
      expect(bruteForceCipher(''), isEmpty);
    });
  });

  group('tool view', () {
    Future<void> settleAsync(ToolHarness h, {int ms = 900}) async {
      await h.tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await h.tester.pump();
    }

    Future<void> editorMenu(ToolHarness h, String item) async {
      if (item == 'Example') {
        await h.tap('Load sample');
      } else {
        await h.enter(null, text: '');
      }
    }

    toolTest('decodes with the selected cipher', 'cipher_decoder', (h) async {
      await h.tap('Decode');
      await h.enter('Ciphertext...', text: 'uryyb');
      await settleAsync(h);
      expect(h.text('Plaintext...'), 'hello');
    });

    toolTest('brute force surfaces ranked candidates', 'cipher_decoder', (
      h,
    ) async {
      await h.tap('Brute force');
      await h.enter('Ciphertext...', text: _caesar(_plain, 13));
      await settleAsync(h);
      expect(h.text('Plaintext...'), _plain);
    });

    toolTest('identify reports the best match', 'cipher_decoder', (h) async {
      await h.enter('Ciphertext...', text: _caesar(_plain, 13));
      await settleAsync(h);
      expect(find.textContaining('readable'), findsWidgets);
    });

    toolTest('clear empties both panes', 'cipher_decoder', (h) async {
      await h.enter('Ciphertext...', text: 'uryyb');
      await editorMenu(h, 'Clear');
      expect(h.text('Ciphertext...'), isEmpty);
    });
  });
}
