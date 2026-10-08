/// Password hashing (bcrypt, PBKDF2, scrypt, Argon2) and verification.
///
/// Isolate-safe like `compression_service.dart`: the top-level workers are
/// what the tool view hands to `compute`, because a real cost factor takes
/// hundreds of milliseconds to seconds on the UI thread.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bcrypt/bcrypt.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/argon2.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/key_derivators/scrypt.dart';
import 'package:pointycastle/macs/hmac.dart';

/// The password hashing functions the tool exposes.
enum PasswordHashAlgorithm {
  bcrypt('bcrypt', '2a'),
  pbkdf2Sha256('PBKDF2-HMAC-SHA256', 'pbkdf2-sha256'),
  pbkdf2Sha512('PBKDF2-HMAC-SHA512', 'pbkdf2-sha512'),
  scrypt('scrypt', 'scrypt'),
  argon2d('Argon2d', 'argon2d'),
  argon2i('Argon2i', 'argon2i'),
  argon2id('Argon2id', 'argon2id');

  const PasswordHashAlgorithm(this.label, this.phcPrefix);

  final String label;

  /// Identifier used in modular-crypt (PHC) encoded strings.
  final String phcPrefix;

  bool get usesCost => this == PasswordHashAlgorithm.bcrypt;

  bool get usesIterations =>
      this == PasswordHashAlgorithm.pbkdf2Sha256 ||
      this == PasswordHashAlgorithm.pbkdf2Sha512 ||
      this == PasswordHashAlgorithm.argon2d ||
      this == PasswordHashAlgorithm.argon2i ||
      this == PasswordHashAlgorithm.argon2id;

  bool get usesScryptParams => this == PasswordHashAlgorithm.scrypt;

  bool get usesMemory => phcPrefix.startsWith('argon2');
}

/// Cost parameters for one hash operation.
class PasswordHashParams {
  const PasswordHashParams({
    this.rounds = 10,
    this.iterations = 210000,
    this.memoryKiB = 19456,
    this.lanes = 1,
    this.scryptN = 16384,
    this.scryptR = 8,
    this.scryptP = 1,
    this.salt,
  });

  /// bcrypt log2 cost (4-31).
  final int rounds;

  /// PBKDF2 and Argon2 iteration count.
  final int iterations;

  /// Argon2 memory cost in KiB.
  final int memoryKiB;

  /// Argon2 degree of parallelism.
  final int lanes;

  /// scrypt CPU/memory cost (must be a power of two).
  final int scryptN;

  final int scryptR;
  final int scryptP;

  /// Reuse this salt instead of generating a fresh one. Accepts standard
  /// base64, with or without padding.
  final String? salt;
}

/// Result of hashing a password.
class HashOutcome {
  const HashOutcome.success({
    required this.encoded,
    required this.elapsedMs,
    this.warning,
  }) : error = null;

  const HashOutcome.failure(this.error)
    : encoded = '',
      elapsedMs = 0,
      warning = null;

  /// Modular-crypt string, e.g. `$2a$10$...` or `$argon2id$v=19$...`.
  final String encoded;

  final int elapsedMs;
  final String? error;

  /// Non-fatal advice, e.g. a cost factor that is low for production.
  final String? warning;
}

/// Result of checking a password against an encoded hash.
class VerifyOutcome {
  const VerifyOutcome({
    required this.matched,
    required this.message,
    this.algorithm,
  });

  final bool matched;
  final String message;
  final String? algorithm;
}

/// Top-level so it can run inside an isolate via `compute`.
HashOutcome hashPasswordWorker(PasswordHashRequest request) =>
    hashPasswordSync(request);

/// Top-level so it can run inside an isolate via `compute`.
VerifyOutcome verifyPasswordWorker(VerifyRequest request) =>
    verifyPasswordSync(request.password, request.encoded);

/// Arguments for [hashPasswordWorker]; kept as a named type because `compute`
/// needs a single sendable message.
class PasswordHashRequest {
  const PasswordHashRequest(this.password, this.algorithm, this.params);

  final String password;
  final PasswordHashAlgorithm algorithm;
  final PasswordHashParams params;
}

/// Arguments for [verifyPasswordWorker].
class VerifyRequest {
  const VerifyRequest(this.password, this.encoded);

  final String password;
  final String encoded;
}

/// Hashes [password] with [algorithm] and returns a modular-crypt string.
HashOutcome hashPasswordSync(PasswordHashRequest request) {
  final password = request.password;
  if (password.isEmpty) {
    return const HashOutcome.failure('Enter a password to hash.');
  }
  final stopwatch = Stopwatch()..start();
  try {
    final encoded = switch (request.algorithm) {
      PasswordHashAlgorithm.bcrypt => _bcrypt(password, request.params),
      PasswordHashAlgorithm.pbkdf2Sha256 ||
      PasswordHashAlgorithm.pbkdf2Sha512 => _pbkdf2(
        password,
        request.params,
        request.algorithm == PasswordHashAlgorithm.pbkdf2Sha256
            ? SHA256Digest()
            : SHA512Digest(),
        request.algorithm.phcPrefix,
      ),
      PasswordHashAlgorithm.scrypt => _scrypt(password, request.params),
      PasswordHashAlgorithm.argon2d ||
      PasswordHashAlgorithm.argon2i ||
      PasswordHashAlgorithm.argon2id => _argon2(password, request.params, request.algorithm),
    };
    stopwatch.stop();
    return HashOutcome.success(
      encoded: encoded,
      elapsedMs: stopwatch.elapsedMilliseconds,
      warning: _costWarning(request.algorithm, request.params),
    );
  } on ArgumentError catch (error) {
    stopwatch.stop();
    return HashOutcome.failure('Invalid parameter: ${_message(error)}');
  } catch (error) {
    stopwatch.stop();
    return HashOutcome.failure('Hashing failed: ${_message(error)}');
  }
}

/// Checks [password] against [encoded], detecting the algorithm from the
/// modular-crypt prefix so hashes from other tools verify correctly.
VerifyOutcome verifyPasswordSync(String password, String encoded) {
  final trimmed = encoded.trim();
  if (trimmed.isEmpty) {
    return const VerifyOutcome(matched: false, message: 'Paste a hash to verify.');
  }
  if (password.isEmpty) {
    return const VerifyOutcome(
      matched: false,
      message: 'Enter the password to check.',
    );
  }

  try {
    if (trimmed.startsWith(r'$2a$') ||
        trimmed.startsWith(r'$2b$') ||
        trimmed.startsWith(r'$2y$')) {
      final matched = BCrypt.checkpw(password, trimmed);
      return VerifyOutcome(
        matched: matched,
        algorithm: 'bcrypt',
        message: matched
            ? 'Password matches.'
            : 'Password does not match.',
      );
    }

    final parts = trimmed.split(r'$');
    // PHC strings begin with an empty segment from the leading '$'.
    if (parts.length < 5 || parts.first.isNotEmpty) {
      return const VerifyOutcome(
        matched: false,
        message: 'Unrecognized hash format. Expected a bcrypt or PHC string.',
      );
    }
    final id = parts[1];
    final salt = _decodeSalt(parts[parts.length - 2]);
    final expected = _decodeSalt(parts.last);

    switch (id) {
      case 'pbkdf2-sha256':
      case 'pbkdf2-sha512':
        final iterations = int.tryParse(parts[2]);
        if (iterations == null) break;
        final derived = _pbkdf2(
          password,
          PasswordHashParams(iterations: iterations, salt: _b64(salt)),
          id == 'pbkdf2-sha256' ? SHA256Digest() : SHA512Digest(),
          id,
        );
        return _compare(derived, expected, id);
      case 'scrypt':
        final settings = _parseScryptParams(parts[2]);
        if (settings == null) break;
        final derived = _scrypt(
          password,
          PasswordHashParams(
            scryptN: settings.n,
            scryptR: settings.r,
            scryptP: settings.p,
            salt: _b64(salt),
          ),
        );
        return _compare(derived, expected, id);
      case 'argon2d':
      case 'argon2i':
      case 'argon2id':
        final settings = _parseArgon2Params(parts.sublist(2, parts.length - 2));
        if (settings == null) break;
        final derived = _argon2(
          password,
          PasswordHashParams(
            iterations: settings.t,
            memoryKiB: settings.m,
            lanes: settings.p,
            salt: _b64(salt),
          ),
          PasswordHashAlgorithm.values.firstWhere((a) => a.phcPrefix == id),
        );
        return _compare(derived, expected, id);
    }
    return VerifyOutcome(
      matched: false,
      algorithm: id,
      message: 'Unsupported hash algorithm "$id".',
    );
  } on ArgumentError {
    return const VerifyOutcome(
      matched: false,
      message: 'Malformed hash: missing or unreadable parameters.',
    );
  } catch (error) {
    return VerifyOutcome(
      matched: false,
      message: 'Could not verify: ${_message(error)}',
    );
  }
}

String _bcrypt(String password, PasswordHashParams params) {
  if (params.rounds < 4 || params.rounds > 31) {
    throw ArgumentError('bcrypt cost must be between 4 and 31');
  }
  final salt = params.salt ?? BCrypt.gensalt(logRounds: params.rounds);
  return BCrypt.hashpw(password, salt);
}

String _pbkdf2(
  String password,
  PasswordHashParams params,
  Digest digest,
  String phcPrefix,
) {
  if (params.iterations < 1) {
    throw ArgumentError('iteration count must be at least 1');
  }
  final salt = _resolveSalt(params, minimumLength: 1);
  final saltBytes = _decodeSalt(salt);
  // HMac's second argument is the HMAC *block length* in bytes (64 for
  // SHA-256, 128 for SHA-512), not the digest size; using the wrong one
  // silently yields non-standard PBKDF2 output.
  final derivator = PBKDF2KeyDerivator(HMac(digest, digest.byteLength))
    ..init(Pbkdf2Parameters(saltBytes, params.iterations, 32));
  final key = derivator.process(Uint8List.fromList(utf8.encode(password)));
  return '\$$phcPrefix\$${params.iterations}\$$salt\$${_b64(key)}';
}

String _scrypt(String password, PasswordHashParams params) {
  final n = params.scryptN;
  if (n < 2 || (n & (n - 1)) != 0) {
    throw ArgumentError('scrypt N must be a power of 2 greater than 1');
  }
  if (params.scryptR < 1 || params.scryptP < 1) {
    throw ArgumentError('scrypt r and p must be at least 1');
  }
  final salt = _resolveSalt(params, minimumLength: 1);
  final derivator = Scrypt()
    ..init(ScryptParameters(n, params.scryptR, params.scryptP, 32, _decodeSalt(salt)));
  final key = derivator.process(Uint8List.fromList(utf8.encode(password)));
  return '\$scrypt\$ln=1,n=$n,r=${params.scryptR},p=${params.scryptP}\$'
      '$salt\$${_b64(key)}';
}

String _argon2(
  String password,
  PasswordHashParams params,
  PasswordHashAlgorithm algorithm,
) {
  if (params.iterations < 1) throw ArgumentError('iterations must be at least 1');
  if (params.memoryKiB < 8) throw ArgumentError('memory must be at least 8 KiB');
  if (params.lanes < 1) throw ArgumentError('parallelism must be at least 1');
  final salt = _resolveSalt(params, minimumLength: 8);
  final type = switch (algorithm) {
    PasswordHashAlgorithm.argon2d => Argon2Parameters.ARGON2_d,
    PasswordHashAlgorithm.argon2i => Argon2Parameters.ARGON2_i,
    _ => Argon2Parameters.ARGON2_id,
  };
  final derived = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        type,
        _decodeSalt(salt),
        desiredKeyLength: 32,
        memory: params.memoryKiB,
        iterations: params.iterations,
        lanes: params.lanes,
      ),
    );
  final key = derived.process(Uint8List.fromList(utf8.encode(password)));
  return '\$${algorithm.phcPrefix}\$v=19'
      '\$m=${params.memoryKiB},t=${params.iterations},p=${params.lanes}'
      '\$$salt\$${_b64(key)}';
}

/// Returns the user-supplied salt, or a freshly generated one.
///
/// An explicit salt lets a user reproduce a hash they created elsewhere,
/// which is the whole point of the tool when auditing stored credentials.
String _resolveSalt(PasswordHashParams params, {required int minimumLength}) {
  final provided = params.salt?.trim() ?? '';
  if (provided.isEmpty) {
    final random = Random.secure();
    return _b64(
      Uint8List.fromList(
        List<int>.generate(16, (_) => random.nextInt(256)),
      ),
    );
  }
  final decoded = _decodeSalt(provided);
  if (decoded.length < minimumLength) {
    throw ArgumentError('salt must decode to at least $minimumLength bytes');
  }
  return _stripPadding(_stripPadding(base64Encode(decoded)));
}

/// Unpadded standard base64, as used by the PHC string format.
String _b64(List<int> bytes) => _stripPadding(base64Encode(bytes));

String _stripPadding(String value) => value.replaceAll('=', '');

Uint8List _decodeSalt(String value) {
  final cleaned = value.trim().replaceAll(RegExp(r'\s'), '');
  var padded = cleaned;
  final remainder = padded.length % 4;
  if (remainder == 2) padded += '==';
  if (remainder == 3) padded += '=';
  return base64Decode(padded);
}

({int n, int r, int p})? _parseScryptParams(String field) {
  // e.g. "ln=1,n=16384,r=8,p=1"
  final values = <String, int>{};
  for (final pair in field.split(',')) {
    final parts = pair.split('=');
    if (parts.length != 2 || parts[0] != 'ln' && parts[0] != 'n' &&
        parts[0] != 'r' && parts[0] != 'p') {
      // Unknown keys are tolerated; unparseable ones are not.
      continue;
    }
    final value = int.tryParse(parts[1]);
    if (value == null) return null;
    values[parts[0]] = value;
  }
  final n = values['n'];
  final r = values['r'];
  final p = values['p'];
  if (n == null || r == null || p == null) return null;
  return (n: n, r: r, p: p);
}

({int m, int t, int p})? _parseArgon2Params(List<String> fields) {
  int? version;
  int? memory;
  int? iterations;
  int? lanes;
  // Argon2 PHC strings pack m/t/p into a single comma-separated field, e.g.
  // "v=19" then "m=19456,t=2,p=1", so pairs are split on ',' first.
  for (final field in fields) {
    for (final pair in field.split(',')) {
      final parts = pair.split('=');
      if (parts.length != 2) continue;
      final value = int.tryParse(parts[1]);
      if (value == null) continue;
      switch (parts[0]) {
        case 'v':
          version = value;
        case 'm':
          memory = value;
        case 't':
          iterations = value;
        case 'p':
          lanes = value;
      }
    }
  }
  if (version != 19 || memory == null || iterations == null || lanes == null) {
    return null;
  }
  return (m: memory, t: iterations, p: lanes);
}

VerifyOutcome _compare(String derivedEncoded, Uint8List expected, String id) {
  final derived = _decodeSalt(derivedEncoded.split(r'$').last);
  // Compare every byte so the timing does not leak where the mismatch is.
  var difference = derived.length ^ expected.length;
  final length = min(derived.length, expected.length);
  for (var i = 0; i < length; i++) {
    difference |= derived[i] ^ expected[i];
  }
  final matched = difference == 0;
  return VerifyOutcome(
    matched: matched,
    algorithm: id,
    message: matched ? 'Password matches.' : 'Password does not match.',
  );
}

/// Flags cost factors that are fine for a lab but weak in production.
String? _costWarning(PasswordHashAlgorithm algorithm, PasswordHashParams params) {
  if (algorithm == PasswordHashAlgorithm.bcrypt && params.rounds < 10) {
    return 'bcrypt cost ${params.rounds} is below the current recommendation of 10.';
  }
  if (algorithm.phcPrefix.startsWith('argon2') && params.memoryKiB < 19456) {
    return 'Argon2 memory ${params.memoryKiB} KiB is below the recommended 19456 KiB.';
  }
  if (algorithm == PasswordHashAlgorithm.pbkdf2Sha256 && params.iterations < 600000) {
    return 'PBKDF2-SHA256 at ${params.iterations} iterations is below the recommended 600000.';
  }
  return null;
}

String _message(Object error) {
  if (error is ArgumentError) return error.message?.toString() ?? 'bad argument';
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}