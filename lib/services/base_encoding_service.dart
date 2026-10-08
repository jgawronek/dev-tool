/// Base-N encodings beyond base64: base32, base58, base62, base85, bech32.
///
/// Isolate-safe and synchronous, following `compression_service.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The alphabets the tool exposes.
enum BaseEncoding {
  base32('Base32', 'RFC 4648'),
  base58('Base58', 'Bitcoin'),
  base62('Base62', 'Alphanumeric'),
  base85('Base85', 'Ascii85'),
  bech32('Bech32', 'Segwit addresses');

  const BaseEncoding(this.label, this.note);

  final String label;
  final String note;

  /// bech32 encodes a witness program under a human-readable prefix rather
  /// than arbitrary bytes, so it needs extra input and output fields.
  bool get isBech32 => this == BaseEncoding.bech32;
}

/// A decoded bech32 string broken into its address parts.
class Bech32Parts {
  const Bech32Parts({
    required this.hrp,
    required this.program,
    required this.witnessVersion,
  });

  /// Human-readable part, e.g. `bc` for mainnet addresses.
  final String hrp;

  /// Witness program as hex.
  final String program;

  /// Witness version, or null for a plain bech32 (non-segwit) string.
  final int? witnessVersion;
}

/// Result of one encode or decode run.
class BaseEncodingOutcome {
  const BaseEncodingOutcome.success({
    required this.output,
    required this.summary,
    this.parts,
  }) : error = null;

  const BaseEncodingOutcome.failure(this.error)
    : output = '',
      summary = '',
      parts = null;

  final String output;
  final String summary;
  final String? error;

  /// Populated when decoding bech32.
  final Bech32Parts? parts;
}

/// Encodes UTF-8 [text] using [encoding].
BaseEncodingOutcome encodeBaseSync(String text, BaseEncoding encoding) {
  if (text.isEmpty) {
    return const BaseEncodingOutcome.failure('Enter text to encode.');
  }
  final bytes = Uint8List.fromList(utf8.encode(text));
  if (encoding.isBech32) {
    final data = _convertBits(bytes, 8, 5, true);
    if (data == null) {
      return const BaseEncodingOutcome.failure(
        'Input is too long for a bech32 string (limit is 90 bytes).',
      );
    }
    // Bech32 carries a witness version in the first 5-bit group. Emitting an
    // explicit v0 keeps the structure spec-valid and means the decoder reads
    // the payload back the same way rather than guessing at a version byte.
    return _bech32Build('dev', [0, ...data], bytes);
  }
  try {
    final encoded = switch (encoding) {
      BaseEncoding.base32 => _base32Encode(bytes),
      BaseEncoding.base58 => _base58Encode(bytes),
      BaseEncoding.base62 => _base62Encode(bytes),
      BaseEncoding.base85 => _base85Encode(bytes),
      BaseEncoding.bech32 => throw StateError('handled above'),
    };
    return BaseEncodingOutcome.success(
      output: encoded,
      summary: '${encoding.label} · ${humanBytes(bytes.length)} bytes',
    );
  } on FormatException catch (error) {
    return BaseEncodingOutcome.failure(error.message);
  } catch (error) {
    return BaseEncodingOutcome.failure(
      'Encoding failed: ${_describe(error)}',
    );
  }
}

/// Decodes [input] using [encoding].
BaseEncodingOutcome decodeBaseSync(String input, BaseEncoding encoding) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const BaseEncodingOutcome.failure('Paste encoded text to decode.');
  }
  try {
    if (encoding == BaseEncoding.bech32) {
      return _bech32Decode(trimmed);
    }
    final bytes = switch (encoding) {
      BaseEncoding.base32 => _base32Decode(trimmed),
      BaseEncoding.base58 => _base58Decode(trimmed),
      BaseEncoding.base62 => _base62Decode(trimmed),
      BaseEncoding.base85 => _base85Decode(trimmed),
      BaseEncoding.bech32 => throw StateError('unreachable'),
    };
    final text = _tryDecodeText(bytes);
    if (text == null) {
      return BaseEncodingOutcome.success(
        output: bytesToHexString(bytes),
        summary: '${encoding.label} · ${humanBytes(bytes.length)} bytes · binary',
      );
    }
    return BaseEncodingOutcome.success(
      output: text,
      summary: '${encoding.label} · ${humanBytes(bytes.length)} bytes · text',
    );
  } on FormatException catch (error) {
    return BaseEncodingOutcome.failure(error.message);
  } catch (error) {
    return BaseEncodingOutcome.failure(
      'Not valid ${encoding.label}: ${_describe(error)}',
    );
  }
}

const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String _base32Encode(Uint8List bytes) {
  final buffer = StringBuffer();
  var bufferValue = 0;
  var bitsLeft = 0;
  for (final byte in bytes) {
    bufferValue = (bufferValue << 8) | byte;
    bitsLeft += 8;
    while (bitsLeft >= 5) {
      bitsLeft -= 5;
      buffer.write(_base32Alphabet[(bufferValue >> bitsLeft) & 31]);
    }
  }
  if (bitsLeft > 0) {
    buffer.write(_base32Alphabet[(bufferValue << (5 - bitsLeft)) & 31]);
  }
  // RFC 4648 base32 pads to a multiple of 8 characters.
  while (buffer.length % 8 != 0) {
    buffer.write('=');
  }
  return buffer.toString();
}

Uint8List _base32Decode(String input) {
  final cleaned = input.toUpperCase().replaceAll('=', '').replaceAll(' ', '');
  var bufferValue = 0;
  var bitsLeft = 0;
  final out = <int>[];
  for (final char in cleaned.codeUnits) {
    final value = _base32Alphabet.indexOf(String.fromCharCode(char));
    if (value < 0) {
      throw FormatException('invalid base32 character "${String.fromCharCode(char)}"');
    }
    bufferValue = (bufferValue << 5) | value;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      bitsLeft -= 8;
      out.add((bufferValue >> bitsLeft) & 0xff);
    }
  }
  return Uint8List.fromList(out);
}

const _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

const _base62Alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

String _base58Encode(Uint8List bytes) => _bigRadixEncode(bytes, _base58Alphabet);

Uint8List _base58Decode(String input) =>
    _bigRadixDecode(input, _base58Alphabet, 'base58');

String _base62Encode(Uint8List bytes) => _bigRadixEncode(bytes, _base62Alphabet);

Uint8List _base62Decode(String input) =>
    _bigRadixDecode(input, _base62Alphabet, 'base62');

/// Encodes bytes as a big-endian integer written in [alphabet].
///
/// Base58/Base62 treat the payload as one large number, so they need
/// arbitrary-precision arithmetic. Digits are held as base-256 limbs, which
/// keeps this exact without a bignum dependency.
String _bigRadixEncode(Uint8List bytes, String alphabet) {
  final base = alphabet.length;
  final zeroChar = alphabet[0];
  // Leading zero bytes carry no numeric value but must be preserved, so each
  // becomes a leading zero-alphabet character.
  final leadingZeros = _leadingZeroCount(bytes);
  if (leadingZeros == bytes.length) return zeroChar;

  // Repeated long division of the big-endian byte limbs by `base`. Each pass
  // yields the next least-significant digit in `carry` and the base-256
  // quotient becomes the new value, staying exact without a bignum dependency.
  final digits = <int>[];
  var value = <int>[
    for (var i = leadingZeros; i < bytes.length; i++) bytes[i],
  ];
  while (value.isNotEmpty) {
    final quotient = List<int>.filled(value.length, 0);
    var carry = 0;
    for (var i = 0; i < value.length; i++) {
      final accumulator = carry * 256 + value[i];
      quotient[i] = accumulator ~/ base;
      carry = accumulator % base;
    }
    digits.add(carry);
    // Strip the quotient's leading zeros; an empty quotient means we are done.
    var first = 0;
    while (first < quotient.length && quotient[first] == 0) {
      first++;
    }
    value = quotient.sublist(first);
  }

  final builder = StringBuffer();
  for (var i = 0; i < leadingZeros; i++) {
    builder.write(zeroChar);
  }
  for (var i = digits.length - 1; i >= 0; i--) {
    builder.write(alphabet[digits[i]]);
  }
  return builder.toString();
}

Uint8List _bigRadixDecode(String input, String alphabet, String name) {
  if (input.isEmpty) return Uint8List(0);
  final base = alphabet.length;
  final zeroValue = alphabet.codeUnitAt(0);
  // Only the *leading* run of zero-valued characters stands for leading zero
  // bytes. A zero digit in the middle contributes nothing to the number and
  // must not be counted, or the decoded byte length comes out wrong.
  var leadingZeros = 0;
  while (leadingZeros < input.length &&
      input.codeUnitAt(leadingZeros) == zeroValue) {
    leadingZeros++;
  }
  final values = <int>[];
  for (var index = leadingZeros; index < input.length; index++) {
    final char = input.codeUnitAt(index);
    final digit = alphabet.indexOf(String.fromCharCode(char));
    if (digit < 0) {
      throw FormatException(
        'invalid $name character "${String.fromCharCode(char)}"',
      );
    }
    var carry = digit;
    for (var i = 0; i < values.length; i++) {
      final accumulator = values[i] * base + carry;
      values[i] = accumulator & 0xff;
      carry = accumulator >> 8;
    }
    while (carry > 0) {
      values.add(carry & 0xff);
      carry >>= 8;
    }
  }
  final out = <int>[];
  for (var i = 0; i < leadingZeros; i++) {
    out.add(0);
  }
  for (var i = values.length - 1; i >= 0; i--) {
    out.add(values[i]);
  }
  return Uint8List.fromList(out);
}

/// Counts leading zero bytes, which map to leading zero-alphabet characters.
int _leadingZeroCount(Uint8List bytes) {
  var i = 0;
  while (i < bytes.length && bytes[i] == 0) {
    i++;
  }
  return i;
}

String _base85Encode(Uint8List bytes) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < bytes.length) {
    final chunk = <int>[];
    for (var i = 0; i < 4; i++) {
      chunk.add(index + i < bytes.length ? bytes[index + i] : 0);
    }
    final value =
        (chunk[0] << 24) | (chunk[1] << 16) | (chunk[2] << 8) | chunk[3];
    // A full 4-byte group never encodes as "z"; only padding runs do.
    final isPadding = index + 4 > bytes.length;
    final digits = <int>[0, 0, 0, 0, 0];
    var remainder = value;
    for (var i = 4; i >= 0; i--) {
      digits[i] = remainder % 85;
      remainder ~/= 85;
    }
    final count = isPadding ? bytes.length - index + 1 : 5;
    for (var i = 0; i < count; i++) {
      buffer.write(String.fromCharCode(33 + digits[i]));
    }
    index += 4;
  }
  return buffer.toString();
}

Uint8List _base85Decode(String input) {
  var value = input.trim();
  if (value.startsWith('<~')) {
    value = value.substring(2);
  }
  if (value.endsWith('~>')) {
    value = value.substring(0, value.length - 2);
  } else if (value.endsWith('~')) {
    value = value.substring(0, value.length - 1);
  }
  value = value.replaceAll(RegExp(r'\s'), '');
  if (value.isEmpty) return Uint8List(0);
  final out = <int>[];
  var group = <int>[];
  for (final char in value.codeUnits) {
    if (char == 33) {
      group = List<int>.filled(4, 0);
      out.addAll(group);
      continue;
    }
    if (char < 33 || char > 117) {
      throw FormatException(
        'invalid base85 character "${String.fromCharCode(char)}"',
      );
    }
    group.add(char - 33);
    if (group.length == 5) {
      var accumulator = 0;
      for (final digit in group) {
        accumulator = accumulator * 85 + digit;
      }
      if (accumulator > 0xffffffff) {
        throw const FormatException('base85 group overflows 32 bits');
      }
      out.add((accumulator >> 24) & 0xff);
      out.add((accumulator >> 16) & 0xff);
      out.add((accumulator >> 8) & 0xff);
      out.add(accumulator & 0xff);
      group = <int>[];
    }
  }
  if (group.isNotEmpty) {
    if (group.length == 1) {
      throw const FormatException('base85 has a truncated final group');
    }
    final padded = List<int>.from(group);
    while (padded.length < 5) {
      padded.add(84);
    }
    var accumulator = 0;
    for (final digit in padded) {
      accumulator = accumulator * 85 + digit;
    }
    if (accumulator > 0xffffffff) {
      throw const FormatException('base85 group overflows 32 bits');
    }
    final full = <int>[
      (accumulator >> 24) & 0xff,
      (accumulator >> 16) & 0xff,
      (accumulator >> 8) & 0xff,
      accumulator & 0xff,
    ];
    out.addAll(full.sublist(0, group.length - 1));
  }
  return Uint8List.fromList(out);
}

const _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

BaseEncodingOutcome _bech32Build(String hrp, List<int> data, List<int> program) {
  final checksum = _bech32Polymod([..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0]) ^ 1;
  final checksumChars = <int>[];
  for (var i = 0; i < 6; i++) {
    checksumChars.add((checksum >> (5 * (5 - i))) & 31);
  }
  final all = [...data, ...checksumChars];
  final buffer = StringBuffer('${hrp}1');
  for (final value in all) {
    buffer.write(_bech32Charset[value]);
  }
  final address = buffer.toString();
  return BaseEncodingOutcome.success(
    output: address,
    summary: 'Bech32 · hrp "$hrp" · ${humanBytes(program.length)}',
    parts: Bech32Parts(
      hrp: hrp,
      program: bytesToHexString(program),
      witnessVersion: null,
    ),
  );
}

BaseEncodingOutcome _bech32Decode(String input) {
  var value = input.toLowerCase().trim();
  // Bech32m uses '1' as separator; some producers emit an all-caps form.
  final separator = value.lastIndexOf('1');
  if (separator < 1 || separator + 7 > value.length) {
    return const BaseEncodingOutcome.failure(
      'Not a valid bech32 string: expected an "1" separator with a prefix and checksum.',
    );
  }
  final hrp = value.substring(0, separator);
  final data = <int>[];
  for (final char in value.substring(separator + 1).codeUnits) {
    final index = _bech32Charset.codeUnits.indexOf(char);
    if (index < 0) {
      return BaseEncodingOutcome.failure(
        'Invalid bech32 character "${String.fromCharCode(char)}".',
      );
    }
    data.add(index);
  }
  final polymod = _bech32Polymod([..._hrpExpand(hrp), ...data]);
  final expected = polymod == 1 ? 'bech32' : (polymod == 0x2bc830a3 ? 'bech32m' : null);
  if (expected == null) {
    return const BaseEncodingOutcome.failure(
      'Bad bech32 checksum. Check for typos or a wrong prefix.',
    );
  }

  final payload = data.sublist(0, data.length - 6);
  final isWitness = payload.isNotEmpty && payload.first <= 16;
  final witnessVersion = isWitness ? payload.first : null;
  final program = _convertBits(
    isWitness ? payload.sublist(1) : payload,
    5,
    8,
    false,
  );
  if (program == null) {
    return const BaseEncodingOutcome.failure(
      'Invalid bech32 padding in the data part.',
    );
  }
  final text = _tryDecodeText(program);
  return BaseEncodingOutcome.success(
    output: text ?? bytesToHexString(program),
    summary:
        'Bech32 · $expected · hrp "$hrp"'
        '${witnessVersion != null ? ' · witness v$witnessVersion' : ''}'
        ' · ${humanBytes(program.length)}'
        '${text == null ? ' · binary' : ' · text'}',
    parts: Bech32Parts(
      hrp: hrp,
      program: bytesToHexString(program),
      witnessVersion: witnessVersion,
    ),
  );
}

List<int> _hrpExpand(String hrp) {
  final out = <int>[];
  for (final code in hrp.codeUnits) {
    out.add(code >> 5);
  }
  out.add(0);
  for (final code in hrp.codeUnits) {
    out.add(code & 31);
  }
  return out;
}

int _bech32Polymod(List<int> values) {
  const generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  var checksum = 1;
  for (final value in values) {
    final top = checksum >> 25;
    checksum = ((checksum & 0x1ffffff) << 5) ^ value;
    for (var i = 0; i < 5; i++) {
      if ((top >> i) & 1 == 1) {
        checksum ^= generator[i];
      }
    }
  }
  return checksum;
}

/// Regroups bits from [fromBits] per element to [toBits], or null on failure.
List<int>? _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
  var accumulator = 0;
  var bits = 0;
  final out = <int>[];
  final maxValue = (1 << toBits) - 1;
  final maxAccumulator = (1 << (fromBits + toBits - 1)) - 1;
  for (final value in data) {
    if (value < 0 || (value >> fromBits) != 0) return null;
    accumulator = ((accumulator << fromBits) | value) & maxAccumulator;
    bits += fromBits;
    while (bits >= toBits) {
      bits -= toBits;
      out.add((accumulator >> bits) & maxValue);
    }
  }
  if (pad) {
    if (bits > 0) {
      out.add((accumulator << (toBits - bits)) & maxValue);
    }
  } else if (bits >= fromBits) {
    // More leftover bits than a single input element: malformed.
    return null;
  } else if ((accumulator & ((1 << bits) - 1)) != 0) {
    // Leftover bits must be zero padding, nothing else.
    return null;
  }
  return out;
}

String? _tryDecodeText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

String bytesToHexString(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String _describe(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}