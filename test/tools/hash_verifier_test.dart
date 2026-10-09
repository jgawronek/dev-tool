import 'package:flutter/material.dart' show Size, TextField;
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/hash_verifier_service.dart';

import '../helpers/tool_harness.dart';

void main() {
  test('SHA-256 matches known digest, including uppercase expected hex', () {
    final result = verifyTextHash(
      text: 'abc',
      expected:
          'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD',
      algorithm: VerifyAlgorithm.sha256,
    );
    expect(result.error, isNull);
    expect(result.matches, isTrue);
  });

  test('SHA-256 mismatch and malformed digest are distinct', () {
    final mismatched = verifyTextHash(
      text: 'abc',
      expected: '0' * 64,
      algorithm: VerifyAlgorithm.sha256,
    );
    expect(mismatched.matches, isFalse);
    expect(mismatched.computed, isNotEmpty);
    final invalid = verifyTextHash(
      text: 'abc',
      expected: 'not hex',
      algorithm: VerifyAlgorithm.sha256,
    );
    expect(invalid.matches, isNull);
    expect(invalid.error, contains('hexadecimal'));
  });

  test('HMAC-SHA256 uses the key and validates it is present', () {
    final result = verifyTextHash(
      text: 'The quick brown fox jumps over the lazy dog',
      expected:
          'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
      algorithm: VerifyAlgorithm.hmacSha256,
      key: 'key',
    );
    expect(result.matches, isTrue);
    expect(
      verifyTextHash(
        text: 'x',
        expected: 'a' * 64,
        algorithm: VerifyAlgorithm.hmacSha256,
      ).error,
      contains('HMAC key'),
    );
  });

  test('empty text is valid but missing expected digest is not', () {
    expect(
      verifyTextHash(
        text: '',
        expected:
            'e3b0c44298fc1c149afbf4c8996fb924'
            '27ae41e4649b934ca495991b7852b855',
        algorithm: VerifyAlgorithm.sha256,
      ).matches,
      isTrue,
    );
    expect(
      verifyTextHash(
        text: 'x',
        expected: '',
        algorithm: VerifyAlgorithm.md5,
      ).error,
      contains('expected'),
    );
  });

  testWidgets('verifier updates result when expected hex changes', (
    tester,
  ) async {
    final h = ToolHarness(tester);
    await h.open('hash_verifier', surface: const Size(1450, 950));
    await h.enter('Text to verify (UTF-8)', text: 'abc');
    final field = find.widgetWithText(TextField, 'Expected hex digest');
    await tester.enterText(
      field,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    await h.settle();
    expect(h.text('Digest verification'), contains('Match'));
    await tester.enterText(field, '0' * 64);
    await h.settle();
    expect(h.text('Digest verification'), contains('No match'));
  });
}
