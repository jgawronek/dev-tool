/// Offline digest and HMAC verification for text input.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

enum VerifyAlgorithm {
  sha256('SHA-256'),
  sha512('SHA-512'),
  sha1('SHA-1'),
  md5('MD5'),
  hmacSha256('HMAC-SHA-256'),
  hmacSha512('HMAC-SHA-512');

  const VerifyAlgorithm(this.label);
  final String label;

  bool get keyed => name.startsWith('hmac');
}

class HashVerifyResult {
  const HashVerifyResult({this.computed, this.matches, this.error});

  final String? computed;
  final bool? matches;
  final String? error;
}

HashVerifyResult verifyTextHash({
  required String text,
  required String expected,
  required VerifyAlgorithm algorithm,
  String key = '',
}) {
  if (expected.trim().isEmpty) {
    return const HashVerifyResult(error: 'Enter an expected hex digest.');
  }
  if (algorithm.keyed && key.isEmpty) {
    return const HashVerifyResult(error: 'Enter an HMAC key.');
  }
  final hash = switch (algorithm) {
    VerifyAlgorithm.sha256 || VerifyAlgorithm.hmacSha256 => sha256,
    VerifyAlgorithm.sha512 || VerifyAlgorithm.hmacSha512 => sha512,
    VerifyAlgorithm.sha1 => sha1,
    VerifyAlgorithm.md5 => md5,
  };
  final actual = (algorithm.keyed ? Hmac(hash, utf8.encode(key)) : hash)
      .convert(utf8.encode(text))
      .toString();
  final normalized = expected.trim().toLowerCase();
  if (normalized.length != actual.length ||
      !RegExp(r'^[0-9a-f]+$').hasMatch(normalized)) {
    return HashVerifyResult(
      computed: actual,
      error:
          'Expected ${actual.length} hexadecimal characters for ${algorithm.label}.',
    );
  }
  // Compare every byte even when an earlier one differs.
  var difference = 0;
  for (var i = 0; i < actual.length; i++) {
    difference |= actual.codeUnitAt(i) ^ normalized.codeUnitAt(i);
  }
  return HashVerifyResult(computed: actual, matches: difference == 0);
}
