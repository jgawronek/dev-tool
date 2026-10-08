import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/password_hash_service.dart';
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

HashOutcome _hash(
  String password,
  PasswordHashAlgorithm algorithm, {
  PasswordHashParams params = const PasswordHashParams(),
}) {
  return hashPasswordSync(PasswordHashRequest(password, algorithm, params));
}

/// Cheap-but-valid parameters so tests stay fast without weakening coverage.
PasswordHashParams _paramsFor(PasswordHashAlgorithm algorithm) {
  if (algorithm == PasswordHashAlgorithm.bcrypt) {
    return const PasswordHashParams(rounds: 4);
  }
  if (algorithm.usesScryptParams) {
    return const PasswordHashParams(scryptN: 1024);
  }
  if (algorithm.phcPrefix.startsWith('argon2')) {
    return const PasswordHashParams(iterations: 2, memoryKiB: 1024);
  }
  if (algorithm.usesIterations) {
    return const PasswordHashParams(iterations: 1000);
  }
  return const PasswordHashParams();
}

void main() {
  group('reference interoperability', () {
    // These pin the implementation to published vectors so a refactor cannot
    // silently produce hashes that other systems cannot verify.

    test('bcrypt reproduces a Python bcrypt hash byte for byte', () {
      final result = _hash(
        'swordfish',
        PasswordHashAlgorithm.bcrypt,
        params: const PasswordHashParams(
          rounds: 6,
          salt: r'$2a$06$RzKlsrXtOCkfiDgiI.obXePDzAqZ5X',
        ),
      );
      expect(
        result.encoded,
        r'$2a$06$RzKlsrXtOCkfiDgiI.obXePDzAqZ5Xwx41U/.JhTqI6bXNRlH/P9y',
      );
    });

    test('pbkdf2-sha256 matches hashlib.pbkdf2_hmac', () {
      // password="password", salt="salt"
      final cases = {
        1: r'Eg+2z/z4syxD5yJSVsT4N6hlSMkszDVICAWYfLcL4Xs',
        1000: r'YywoEuRtRgQQK6dhjp1tfS+BKPYma0oDJk0qBGC33LM',
        4096: r'xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o',
      };
      cases.forEach((iterations, expected) {
        final result = _hash(
          'password',
          PasswordHashAlgorithm.pbkdf2Sha256,
          params: PasswordHashParams(iterations: iterations, salt: 'c2FsdA'),
        );
        expect(result.encoded.split(r'$').last, expected, reason: '$iterations');
      });
    });

    test('pbkdf2-sha512 matches hashlib.pbkdf2_hmac', () {
      final result = _hash(
        'password',
        PasswordHashAlgorithm.pbkdf2Sha512,
        params: const PasswordHashParams(iterations: 1000, salt: 'c2FsdA'),
      );
      expect(
        result.encoded.split(r'$').last,
        r'r+bFUweFtsxrHGRTOEcxvV7kMu5Un9QvtmlXea2KHFs',
      );
    });

    test('scrypt matches hashlib.scrypt', () {
      final result = _hash(
        'password',
        PasswordHashAlgorithm.scrypt,
        params: const PasswordHashParams(scryptN: 1024, salt: 'c2FsdA'),
      );
      expect(
        result.encoded.split(r'$').last,
        r'FtvIkGdjx/BIl3po+dMF93EOBoyizZXas3ISW7Pxlgg',
      );
    });

    test('argon2i verifies against the phc-winner-argon2 published hash', () {
      // password="password", salt="somesalt", t=2, m=65536, p=1
      const published =
          r'$argon2i$v=19$m=65536,t=2,p=1$c29tZXNhbHQ$wWKIMhR9lyDFvRz9YTZweHKfbftvj+qf+YFY4NeBbtA';
      final result = verifyPasswordSync('password', published);
      expect(result.matched, isTrue, reason: result.message);
      expect(result.algorithm, 'argon2i');
      expect(verifyPasswordSync('wrong', published).matched, isFalse);
    });

    test('a bcrypt hash from Python verifies here', () {
      const fromPython =
          r'$2a$06$RzKlsrXtOCkfiDgiI.obXePDzAqZ5Xwx41U/.JhTqI6bXNRlH/P9y';
      expect(verifyPasswordSync('swordfish', fromPython).matched, isTrue);
      expect(verifyPasswordSync('nope', fromPython).matched, isFalse);
    });
  });

  group('round trips', () {
    test('every algorithm verifies its own output and rejects others', () {
      for (final algorithm in PasswordHashAlgorithm.values) {
        final result = _hash('swordfish', algorithm, params: _paramsFor(algorithm));
        expect(result.error, isNull, reason: '$algorithm: ${result.error}');
        expect(result.encoded, startsWith(r'$'), reason: algorithm.label);
        expect(
          verifyPasswordSync('swordfish', result.encoded).matched,
          isTrue,
          reason: algorithm.label,
        );
        expect(
          verifyPasswordSync('wrong', result.encoded).matched,
          isFalse,
          reason: algorithm.label,
        );
      }
    });

    test('argon2 variants emit distinct prefixes', () {
      for (final algorithm in [
        PasswordHashAlgorithm.argon2d,
        PasswordHashAlgorithm.argon2i,
        PasswordHashAlgorithm.argon2id,
      ]) {
        final result = _hash('abc', algorithm, params: _paramsFor(algorithm));
        expect(result.encoded, startsWith('\$${algorithm.phcPrefix}\$v=19\$'));
        expect(verifyPasswordSync('abc', result.encoded).matched, isTrue);
      }
    });

    test('an explicit salt makes hashing reproducible', () {
      const params = PasswordHashParams(iterations: 1000, salt: 'c2FsdHNhbHQ');
      final first = _hash('abc', PasswordHashAlgorithm.pbkdf2Sha256, params: params);
      final second = _hash('abc', PasswordHashAlgorithm.pbkdf2Sha256, params: params);
      expect(first.encoded, second.encoded);
    });

    test('an omitted salt produces a different hash each time', () {
      final first = _hash('abc', PasswordHashAlgorithm.pbkdf2Sha256, params: const PasswordHashParams(iterations: 1000));
      final second = _hash('abc', PasswordHashAlgorithm.pbkdf2Sha256, params: const PasswordHashParams(iterations: 1000));
      expect(first.encoded, isNot(second.encoded));
      expect(verifyPasswordSync('abc', first.encoded).matched, isTrue);
      expect(verifyPasswordSync('abc', second.encoded).matched, isTrue);
    });
  });

  group('input handling', () {
    test('empty inputs are rejected with guidance', () {
      expect(_hash('', PasswordHashAlgorithm.bcrypt).error, contains('Enter a password'));
      expect(verifyPasswordSync('x', '').message, contains('Paste a hash'));
      expect(verifyPasswordSync('', 'anything').message, contains('password'));
    });

    test('unrecognized and malformed hashes report readably', () {
      expect(
        verifyPasswordSync('x', 'not-a-hash').message,
        contains('Unrecognized'),
      );
      expect(verifyPasswordSync('x', r'$2a$10$tooshort').message, isNotNull);
      expect(
        verifyPasswordSync('x', r'$pbkdf2-sha256$abc$c2FsdA$aGFzaA').message,
        isNotNull,
      );
      expect(
        verifyPasswordSync('x', r'$argon2id$v=18$m=1024,t=2,p=1$c2FsdA$aGFzaA').message,
        isNotNull,
      );
    });

    test('invalid cost parameters report the constraint', () {
      expect(
        _hash('x', PasswordHashAlgorithm.bcrypt,
            params: const PasswordHashParams(rounds: 2)).error,
        contains('cost'),
      );
      expect(
        _hash('x', PasswordHashAlgorithm.scrypt,
            params: const PasswordHashParams(scryptN: 1000)).error,
        contains('power of 2'),
      );
      expect(
        _hash('x', PasswordHashAlgorithm.argon2id,
            params: const PasswordHashParams(memoryKiB: 1)).error,
        contains('memory'),
      );
    });

    test('weak cost factors warn without failing', () {
      expect(
        _hash('x', PasswordHashAlgorithm.bcrypt,
            params: const PasswordHashParams(rounds: 4)).warning,
        contains('below'),
      );
      expect(
        _hash('x', PasswordHashAlgorithm.argon2id,
            params: const PasswordHashParams(iterations: 2, memoryKiB: 1024)).warning,
        contains('below'),
      );
      expect(
        _hash('x', PasswordHashAlgorithm.pbkdf2Sha256,
            params: const PasswordHashParams(iterations: 1000)).warning,
        contains('below'),
      );
    });

    test('strong parameters raise no warning', () {
      expect(
        _hash('x', PasswordHashAlgorithm.bcrypt,
            params: const PasswordHashParams(rounds: 10)).warning,
        isNull,
      );
    });
  });

  group('tool view', () {
    /// Opens the editor context menu with bounded pumps; `pumpAndSettle`
    /// never returns here because the hashing spinner animates continuously.
    Future<void> editorMenu(ToolHarness h, String item) async {
      final pane = find.byType(EditorPane).first;
      await h.tester.tapAt(
        h.tester.getCenter(pane),
        buttons: kSecondaryMouseButton,
      );
      await h.settle();
      await h.tap(item);
      await h.settle();
    }

    /// Drives the "Hash to check" TextField, which is a plain TextField
    /// rather than an EditorPane.
    Future<void> setVerifyHash(ToolHarness h, String value) async {
      final field = h.tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere(
            (f) => f.decoration?.hintText == 'Paste a bcrypt or PHC hash...',
          );
      field.controller!.text = value;
      field.onChanged!(value);
      await h.settle();
    }

    /// Hashing runs in a `compute` isolate, so the widget tests must let real
    /// async complete before a single pump (pumpAndSettle would never settle
    /// because the editors blink their cursor forever).
    Future<void> settleAsync(ToolHarness h, {int ms = 700}) async {
      await h.tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await h.tester.pump();
    }

    toolTest('hashes an entered password to a bcrypt string', 'password_hashing',
        (h) async {
      await h.enter('Enter a password...', text: 'swordfish');
      await settleAsync(h);
      final output = h.text('Generated hash...');
      expect(output, startsWith(r'$2a$'));
      expect(verifyPasswordSync('swordfish', output).matched, isTrue);
    });

    toolTest('verify mode reports a match', 'password_hashing', (h) async {
      const hash = r'$2a$06$RzKlsrXtOCkfiDgiI.obXePDzAqZ5Xwx41U/.JhTqI6bXNRlH/P9y';
      await h.tap('Verify');
      await setVerifyHash(h, hash);
      await h.enter('Enter a password...', text: 'swordfish');
      await settleAsync(h);
      expect(h.text('Verification result...'), contains('matches'));
      expect(find.textContaining('bcrypt'), findsWidgets);
    });

    toolTest('verify mode reports a mismatch', 'password_hashing', (h) async {
      const hash = r'$2a$06$RzKlsrXtOCkfiDgiI.obXePDzAqZ5Xwx41U/.JhTqI6bXNRlH/P9y';
      await h.tap('Verify');
      await setVerifyHash(h, hash);
      await h.enter('Enter a password...', text: 'not the password');
      await settleAsync(h);
      expect(h.text('Verification result...'), contains('does not match'));
    });

    toolTest('verify mode prompts when no hash is pasted', 'password_hashing',
        (h) async {
      await h.tap('Verify');
      await h.enter('Enter a password...', text: 'swordfish');
      await h.settle();
      expect(find.textContaining('Paste the hash'), findsOneWidget);
    });

    toolTest('clear empties the editors', 'password_hashing', (h) async {
      await h.enter('Enter a password...', text: 'swordfish');
      await editorMenu(h, 'Clear');
      expect(h.text('Enter a password...'), isEmpty);
    });
  });
}