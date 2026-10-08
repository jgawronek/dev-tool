/// Session and token decoding for web application cookies.
///
/// Offline structural decoding only: Flask's signed-cookie payload and JWE
/// compact serialisations are parsed and described, but no signature or
/// ciphertext is verified or decrypted, because that would require the
/// application's secret key.
library;

import 'dart:convert';

import 'package:archive/archive.dart';

/// The cookie/session formats the tool recognises.
enum SessionFormat {
  flask('Flask session cookie'),
  jwe('JWE (compact)'),
  jwt('JWT'),
  phpSerialized('PHP serialized'),
  rails('Rails message cookie'),
  dotnet('ASP.NET / .NET data protector'),
  unknown('Unrecognised');

  const SessionFormat(this.label);

  final String label;
}

/// One decoded part of a cookie or token.
class SessionPart {
  const SessionPart({
    required this.name,
    required this.value,
    this.note = '',
  });

  final String name;
  final String value;
  final String note;
}

/// Result of decoding a cookie or token.
class SessionOutcome {
  const SessionOutcome({
    required this.format,
    required this.parts,
    this.error,
    this.warnings = const [],
  });

  final SessionFormat format;
  final List<SessionPart> parts;
  final String? error;

  /// Caveats the user should see, e.g. that nothing was verified.
  final List<String> warnings;

  String toReport() {
    final buffer = StringBuffer()
      ..writeln('Format   ${format.label}')
      ..writeln();
    for (final part in parts) {
      buffer.writeln(part.name);
      buffer.writeln(part.value);
      if (part.note.isNotEmpty) {
        buffer.writeln('(${part.note})');
      }
      buffer.writeln();
    }
    if (warnings.isNotEmpty) {
      buffer.writeln('Notes');
      for (final warning in warnings) {
        buffer.writeln('  - $warning');
      }
    }
    return buffer.toString().trimRight();
  }
}

/// Decodes [input], which may be a raw cookie value or a `name=value` pair.
SessionOutcome decodeSession(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const SessionOutcome(
      format: SessionFormat.unknown,
      parts: [],
      error: 'Paste a cookie or token to decode.',
    );
  }

  // A pasted `Cookie:` header may carry several pairs; use the first
  // recognisable one rather than the whole header.
  var value = trimmed;
  final named = RegExp(
    r'(?:session|sessionid|connect\.sid|PHPSESSID|token|jwt|auth)=([^;,\s]+)',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (named != null) value = named.group(1)!;

  final unwrapped = value.startsWith('"') && value.endsWith('"') && value.length > 1
      ? value.substring(1, value.length - 1)
      : value;

  // A JWE has five segments and a JWT or Flask cookie has three. They are
  // told apart by the first segment: a JWT header is always a JSON object
  // carrying `alg`, while a Flask payload is session data.
  final segments = unwrapped.split('.');
  if (segments.length == 5) return _decodeJwe(unwrapped);
  if (segments.length == 3) {
    final header = _b64UrlText(segments[0]);
    return _looksLikeJwtHeader(header) ? _decodeJwt(unwrapped) : _decodeFlask(unwrapped);
  }
  return _decodeOther(unwrapped);
}

/// True when [header] is a JWT protected header rather than session data.
bool _looksLikeJwtHeader(String? header) {
  if (header == null) return false;
  try {
    final json = jsonDecode(header);
    if (json is! Map<String, dynamic>) return false;
    return json.containsKey('alg') || json.containsKey('typ');
  } catch (_) {
    return false;
  }
}

/// JWTs are already covered by the JWT debugger, but detecting them here keeps
/// the report honest about what the user pasted.
SessionOutcome _decodeJwt(String value) {
  final segments = value.split('.');
  final header = _b64UrlText(segments[0]);
  final payload = _b64UrlText(segments[1]);
  return SessionOutcome(
    format: SessionFormat.jwt,
    parts: [
      if (header != null)
        SessionPart(
          name: 'Header',
          value: _prettyJsonOrRaw(header),
          note: 'decoded from Base64URL',
        ),
      if (payload != null)
        SessionPart(
          name: 'Payload',
          value: _prettyJsonOrRaw(payload),
          note: 'decoded from Base64URL',
        ),
      SessionPart(
        name: 'Signature',
        value: segments[2],
        note: 'not verified offline',
      ),
    ],
    warnings: const [
      'Signatures are not verified; use the JWT Debugger to check one.',
    ],
  );
}

/// JWE compact serialisation is `header.encrypted_key.iv.ciphertext.tag`.
/// Only the header is readable without the key.
SessionOutcome _decodeJwe(String value) {
  final segments = value.split('.');
  final header = _b64UrlText(segments[0]);
  final parts = <SessionPart>[
    if (header != null)
      SessionPart(
        name: 'Protected header',
        value: _prettyJsonOrRaw(header),
        note: 'decoded from Base64URL',
      ),
    SessionPart(
      name: 'Encrypted key',
      value: segments[1].isEmpty ? '(none)' : segments[1],
    ),
    SessionPart(
      name: 'Initialisation vector',
      value: segments[2].isEmpty ? '(none)' : segments[2],
    ),
    SessionPart(
      name: 'Ciphertext',
      value: '${segments[3].length} Base64URL characters'
          '${_cipherNote(header)}',
    ),
    SessionPart(name: 'Auth tag', value: segments[4]),
  ];
  return SessionOutcome(
    format: SessionFormat.jwe,
    parts: parts,
    warnings: const [
      'The payload is encrypted and cannot be read without the key.',
      'The alg header shows how, not whether, it can be decrypted.',
    ],
  );
}

String _cipherNote(String? header) {
  if (header == null) return '';
  try {
    final json = jsonDecode(header) as Map<String, dynamic>;
    final enc = json['enc'];
    return enc == null ? '' : ' (enc: $enc)';
  } catch (_) {
    return '';
  }
}

/// Flask's session cookie is `payload.timestamp.signature`, where the payload
/// is zlib-compressed when it carries enough keys.
/// Reads Flask's timestamp segment, which itsdangerous encodes as a big-endian
/// integer rather than as text.
String? _flaskTimestamp(String segment) {
  final bytes = _b64UrlBytes(segment);
  if (bytes == null) return null;
  if (bytes.length == 4 || bytes.length == 8) {
    var seconds = 0;
    for (final byte in bytes) {
      seconds = (seconds << 8) | byte;
    }
    if (seconds > 946684800 && seconds < 4102444800) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
          .toIso8601String();
    }
  }
  return _tryDecodeText(bytes);
}

/// True when [payload] looks like Flask session data rather than, say, a
/// bcrypt hash that merely happens to contain two dots.
bool _looksLikeFlaskPayload(String? payload) {
  if (payload == null) return false;
  final candidate = _inflateIfNeeded(payload).trimLeft();
  return candidate.startsWith('{') && candidate.endsWith('}');
}

SessionOutcome _decodeFlask(String value) {
  final segments = value.split('.');
  if (segments.length != 3) return _decodeOther(value);
  final payload = _b64UrlText(segments[0]);
  if (!_looksLikeFlaskPayload(payload)) return _decodeOther(value);
  final timestamp = _flaskTimestamp(segments[1]);

  final parts = <SessionPart>[];
  if (payload != null) {
    parts.add(
      SessionPart(
        name: 'Payload',
        value: _prettyJsonOrRaw(_inflateIfNeeded(payload)),
        note: 'signed by the server; zlib-compressed when large',
      ),
    );
  }
  if (timestamp != null) {
    parts.add(SessionPart(name: 'Issued at', value: timestamp));
  }
  parts.add(
    SessionPart(
      name: 'Signature',
      value: segments[2],
      note: 'HMAC; not verified offline',
    ),
  );
  return SessionOutcome(
    format: SessionFormat.flask,
    parts: parts,
    warnings: const [
      'Flask signatures require the app SECRET_KEY, so this is unverified.',
      'An attacker can forge the payload here; never trust its contents.',
    ],
  );
}

/// Handles the formats that are a single opaque value.
SessionOutcome _decodeOther(String value) {
  if (value.startsWith('{') && value.trimLeft().startsWith('a:')) {
    return _php(value);
  }
  if (_looksLikeDotNet(value)) {
    return SessionOutcome(
      format: SessionFormat.dotnet,
      parts: [
        const SessionPart(
          name: 'Payload',
          value: 'ASP.NET data-protection blob',
          note: 'structure only',
        ),
        SessionPart(name: 'Length', value: '${value.length} characters'),
        SessionPart(
          name: 'Prefix',
          value: '${value.substring(0, value.length.clamp(0, 24))}...',
          note: 'format version and purpose',
        ),
      ],
      warnings: const [
        'Encrypted by ASP.NET Core; cannot be read without the application keys.',
      ],
    );
  }
  if (_looksLikeRails(value)) {
    return _rails(value);
  }

  // Last resort: try Base64 on the whole thing, which catches many custom
  // cookies and reveals whether the value is text or binary.
  final bytes = _b64UrlBytes(value) ?? _stdBase64Bytes(value);
  if (bytes == null) {
    return SessionOutcome(
      format: SessionFormat.unknown,
      parts: [
        SessionPart(
          name: 'Raw value',
          value: value,
          note: 'not recognised as a known session format',
        ),
      ],
    );
  }
  final text = _tryDecodeText(bytes);
  return SessionOutcome(
    format: SessionFormat.unknown,
    parts: [
      SessionPart(
        name: 'Decoded',
        value: text ?? bytesToHexString(bytes),
        note: text == null ? 'binary payload shown as hex' : 'Base64 decoded',
      ),
      if (text != null && text.trimLeft().startsWith('a:'))
        const SessionPart(
          name: 'Note',
          value: 'Looks like a PHP serialized payload.',
        ),
    ],
    warnings: const [
      'Not a recognised session format; shown as a generic Base64 value.',
    ],
  );
}

bool _looksLikeDotNet(String value) =>
    value.length > 40 && RegExp(r'^[A-Za-z09\-_]+$').hasMatch(value);

bool _looksLikeRails(String value) =>
    value.contains('BAh7') || value.contains('CG9y');

SessionOutcome _rails(String value) {
  final decoded = _stdBase64Bytes(value) ?? _b64UrlBytes(value);
  if (decoded == null) {
    return const SessionOutcome(
      format: SessionFormat.rails,
      parts: [],
      error: 'Not valid Rails Base64.',
    );
  }
  return SessionOutcome(
    format: SessionFormat.rails,
    parts: [
      SessionPart(
        name: 'Decoded',
        value: _escapeControlBytes(decoded),
        note: 'Rails MessageEncryptor/Verifier output',
      ),
    ],
    warnings: const [
      'Signed and encrypted with the app secret; not verified offline.',
    ],
  );
}

SessionOutcome _php(String value) {
  return SessionOutcome(
    format: SessionFormat.phpSerialized,
    parts: [
      SessionPart(
        name: 'Payload',
        value: value,
        note: 'use the PHP Serializer tool for the field-by-field view',
      ),
    ],
    warnings: const ['Object injection risk: never unserialize untrusted data.'],
  );
}

/// zlib-wraps the payload when it is large enough to be worth compressing.
String _inflateIfNeeded(String payload) {
  final bytes = latin1.encode(payload);
  if (bytes.length < 2) return payload;
  try {
    final inflated = const ZLibDecoder().decodeBytes(bytes);
    return utf8.decode(inflated, allowMalformed: true);
  } catch (_) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// Decodes Base64URL to raw bytes, or null if [value] is not valid Base64.
List<int>? _b64UrlBytes(String value) {
  try {
    return base64Decode(_pad(value.replaceAll('-', '+').replaceAll('_', '/')));
  } catch (_) {
    return null;
  }
}

/// Decodes standard Base64 to raw bytes, or null.
List<int>? _stdBase64Bytes(String value) {
  try {
    return base64Decode(_pad(value));
  } catch (_) {
    return null;
  }
}

/// Decodes Base64URL straight to text, which is what every caller here wants.
String? _b64UrlText(String value) {
  final bytes = _b64UrlBytes(value);
  return bytes == null ? null : _tryDecodeText(bytes);
}

String _pad(String value) {
  final remainder = value.length % 4;
  if (remainder == 0) return value;
  if (remainder == 1) return '';
  return value.padRight(value.length + (4 - remainder), '=');
}

String? _tryDecodeText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

String _prettyJsonOrRaw(String text) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
  } catch (_) {
    return text;
  }
}

/// Makes invisible bytes visible so binary payloads can be read.
String _escapeControlBytes(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    if (byte == 0x0a) {
      buffer.write('\n');
    } else if (byte == 0x0d) {
      buffer.write('\n');
    } else if (byte < 0x20 || byte > 0x7e) {
      buffer.write('\\x${byte.toRadixString(16).padLeft(2, '0')}');
    } else {
      buffer.writeCharCode(byte);
    }
  }
  return buffer.toString();
}

String bytesToHexString(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Renders a decoded session cookie as a readable report.
String renderSessionReport(SessionOutcome outcome) {
  if (outcome.error != null) return outcome.error!;
  final buffer = StringBuffer()..writeln('Detected: ${outcome.format.label}');
  if (outcome.parts.isEmpty) {
    buffer.writeln('\nNothing readable in this value.');
  }
  for (final part in outcome.parts) {
    buffer
      ..writeln()
      ..writeln(part.name.toUpperCase());
    for (final line in part.value.split('\n')) {
      buffer.writeln('  $line');
    }
    if (part.note.isNotEmpty) {
      buffer.writeln('  (${part.note})');
    }
  }
  if (outcome.warnings.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Keep in mind');
    for (final warning in outcome.warnings) {
      buffer.writeln('  - $warning');
    }
  }
  return buffer.toString().trimRight();
}
