/// Compression codecs shared by the compress/decompress tool view.
///
/// Everything here is synchronous and isolate-safe: the top-level
/// [compressWorker]/[decompressWorker] entry points are what the tool view
/// hands to `compute`, so this file must not touch Flutter or plugin APIs.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The compression formats the tool exposes, in menu order.
enum CompressionCodec {
  gzip('GZip', '1f 8b'),
  zlib('Zlib', '78 xx'),
  rawDeflate('Raw Deflate', 'none'),
  bzip2('BZip2', '42 5a 68'),
  zip('Zip', '50 4b 03 04'),
  tar('Tar', '75 73 74 61 72');

  const CompressionCodec(this.label, this.magicHint);

  final String label;

  /// Expected leading bytes, shown in error messages so a user pasting the
  /// wrong payload knows what was expected instead of just "failed".
  final String magicHint;

  /// Container formats hold named files rather than a single byte stream, so
  /// the tool summarises their entries instead of concatenating them.
  bool get isContainer => this == CompressionCodec.zip || this == CompressionCodec.tar;
}

/// One file entry recovered from a Zip/Tar archive.
class ArchiveEntry {
  const ArchiveEntry(this.name, this.size, this.preview);

  final String name;
  final int size;

  /// First bytes of the entry, used to flag binary content.
  final Uint8List preview;
}

/// Result of a single compress or decompress run.
class CompressionOutcome {
  const CompressionOutcome.success({
    required this.output,
    required this.summary,
    this.binary = false,
    this.entries = const [],
  }) : error = null;

  const CompressionOutcome.failure(this.error) : output = '', summary = '', binary = false, entries = const [];

  /// Payload rendered for the output editor.
  final String output;

  /// Short human-readable status shown above the output pane.
  final String summary;

  /// Non-null when the run failed; already phrased for display.
  final String? error;

  /// True when [output] holds hex rather than decoded text.
  final bool binary;

  /// Populated for Zip/Tar so the view can list what was inside.
  final List<ArchiveEntry> entries;
}

/// Top-level so it can run inside an isolate via `compute`.
CompressionOutcome compressWorker((String, int) args) {
  return compressSync(args.$1, CompressionCodec.values[args.$2]);
}

/// Top-level so it can run inside an isolate via `compute`.
CompressionOutcome decompressWorker((String, int) args) {
  return decompressPayload(args.$1, CompressionCodec.values[args.$2]);
}

/// Compresses UTF-8 [text] and returns it Base64 encoded.
///
/// Base64 rather than raw bytes because the output pane is a text editor and
/// compressed payloads are not valid UTF-8.
CompressionOutcome compressSync(String text, CompressionCodec codec) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const CompressionOutcome.failure('Enter data to compress.');
  }
  final input = Uint8List.fromList(utf8.encode(trimmed));
  try {
    final encoded = _encodeBytes(input, codec);
    final summary =
        '${codec.label} · ${humanBytes(input.length)} → ${humanBytes(encoded.length)} · '
        '${_ratio(input.length, encoded.length)}';
    return CompressionOutcome.success(
      output: base64Encode(encoded),
      summary: summary,
    );
  } on _CompressionFailure catch (error) {
    return CompressionOutcome.failure(error.message);
  } catch (error) {
    return CompressionOutcome.failure('Compression failed: ${_describe(error)}');
  }
}

/// Decompresses [input], which may be Base64 or hex, using [codec].
///
/// This is the entry point the tool view calls; [decompressSync] is the
/// byte-level core underneath it.
CompressionOutcome decompressPayload(String input, CompressionCodec codec) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const CompressionOutcome.failure(
      'Paste Base64 or hex archive data to decompress.',
    );
  }
  try {
    return decompressSync(decodePayload(trimmed), codec);
  } on FormatException catch (error) {
    return CompressionOutcome.failure(
      'Could not read input as Base64 or hex: ${error.message}',
    );
  }
}

/// Decompresses already-decoded [input] bytes.
CompressionOutcome decompressSync(Uint8List input, CompressionCodec codec) {
  if (input.isEmpty) {
    return const CompressionOutcome.failure(
      'Paste Base64 or hex archive data to decompress.',
    );
  }
  // Validate the header before handing bytes to a codec. Several archive
  // codecs accept foreign data without raising: ZLibDecoder returns GZip
  // bytes verbatim, and BZip2Decoder yields an empty result. A wrong-codec
  // paste must fail loudly rather than emit plausible-looking garbage.
  final magicError = _magicMismatch(codec, input);
  if (magicError != null) return CompressionOutcome.failure(magicError);
  if (codec.isContainer) {
    return _decompressContainer(input, codec);
  }
  try {
    final output = _decodeBytes(input, codec);
    return _textOutcome(output, codec, input.length);
  } on _CompressionFailure catch (error) {
    return CompressionOutcome.failure(error.message);
  } catch (error) {
    return CompressionOutcome.failure(
      'Not valid ${codec.label} data (expected ${codec.magicHint}): ${_describe(error)}',
    );
  }
}

CompressionOutcome _decompressContainer(Uint8List input, CompressionCodec codec) {
  late final Archive archive;
  try {
    archive = codec == CompressionCodec.zip
        ? ZipDecoder().decodeBytes(input)
        : TarDecoder().decodeBytes(input);
  } catch (error) {
    final message = _describe(error).toLowerCase();
    if (message.contains('password') || message.contains('encrypt')) {
      return const CompressionOutcome.failure(
        'Encrypted archives are not supported.',
      );
    }
    return CompressionOutcome.failure(
      'Not valid ${codec.label} data (expected ${codec.magicHint}): ${_describe(error)}',
    );
  }

  final entries = <ArchiveEntry>[];
  final parts = <String>[];
  var totalSize = 0;
  var sawBinary = false;
  for (final file in archive) {
    if (file.isDirectory) continue;
    Uint8List? content;
    try {
      content = file.readBytes();
    } catch (error) {
      if (_describe(error).toLowerCase().contains('password')) {
        return const CompressionOutcome.failure(
          'Encrypted archives are not supported.',
        );
      }
      rethrow;
    }
    if (content == null) continue;
    entries.add(ArchiveEntry(file.name, content.length, content));
    totalSize += content.length;
    final decoded = _tryDecodeText(content);
    final name = humanBytes(content.length);
    if (decoded == null) {
      sawBinary = true;
      parts.add(
        '--- ${file.name} ($name, binary) ---\n${bytesToHexString(content)}',
      );
    } else {
      parts.add('--- ${file.name} ($name) ---\n$decoded');
    }
  }

  if (entries.isEmpty) {
    return const CompressionOutcome.failure('Archive contains no files.');
  }
  return CompressionOutcome.success(
    output: parts.join('\n\n'),
    summary:
        '${codec.label} · ${humanBytes(input.length)} → ${humanBytes(totalSize)} · '
        '${entries.length} file${entries.length == 1 ? '' : 's'}'
        '${sawBinary ? ' · binary' : ''}',
    binary: sawBinary,
    entries: entries,
  );
}

CompressionOutcome _textOutcome(Uint8List output, CompressionCodec codec, int inputSize) {
  final text = _tryDecodeText(output);
  if (text == null) {
    return CompressionOutcome.success(
      output: bytesToHexString(output),
      summary:
          '${codec.label} · ${humanBytes(inputSize)} → ${humanBytes(output.length)} · binary',
      binary: true,
    );
  }
  return CompressionOutcome.success(
    output: text,
    summary:
        '${codec.label} · ${humanBytes(inputSize)} → ${humanBytes(output.length)} · text',
  );
}

Uint8List _encodeBytes(Uint8List input, CompressionCodec codec) {
  switch (codec) {
    case CompressionCodec.gzip:
      return const GZipEncoder().encodeBytes(input);
    case CompressionCodec.zlib:
      return const ZLibEncoder().encodeBytes(input);
    case CompressionCodec.rawDeflate:
      // ZLibEncoder's public API drops its `raw` flag, so headerless deflate
      // goes through Deflate directly. Same wire format as raw inflate.
      return Deflate(input).getBytes();
    case CompressionCodec.bzip2:
      return BZip2Encoder().encodeBytes(input);
    case CompressionCodec.zip:
      return ZipEncoder().encodeBytes(_singleEntryArchive(input));
    case CompressionCodec.tar:
      return TarEncoder().encodeBytes(_singleEntryArchive(input));
  }
}

/// Returns a display-ready error when [input] does not start with [codec]'s
/// signature, or null when the header looks right (or cannot be checked).
///
/// Raw deflate is headerless, so it has no signature and is never rejected
/// here; a genuine failure surfaces from the decoder instead.
String? _magicMismatch(CompressionCodec codec, Uint8List input) {
  String? mismatch(String expected) =>
      'Not valid ${codec.label} data (expected $expected).';

  switch (codec) {
    case CompressionCodec.gzip:
      return input.length >= 2 && input[0] == 0x1f && input[1] == 0x8b
          ? null
          : mismatch(codec.magicHint);
    case CompressionCodec.zlib:
      if (input.length < 2) return mismatch(codec.magicHint);
      final cmf = input[0];
      final flg = input[1];
      final method = cmf & 0x0f;
      final windowBits = (cmf >> 4) & 0x0f;
      final checksumOk = ((cmf << 8) | flg) % 31 == 0;
      return method == 8 && windowBits <= 7 && checksumOk
          ? null
          : mismatch('zlib header (78 xx)');
    case CompressionCodec.bzip2:
      return input.length >= 3 &&
              input[0] == 0x42 &&
              input[1] == 0x5a &&
              input[2] == 0x68
          ? null
          : mismatch(codec.magicHint);
    case CompressionCodec.zip:
      if (input.length < 4 || input[0] != 0x50 || input[1] != 0x4b) {
        return mismatch(codec.magicHint);
      }
      final third = input[2];
      final fourth = input[3];
      // Local header, end-of-central-directory, or spanning marker.
      final isArchive =
          (third == 0x03 && fourth == 0x04) ||
          (third == 0x05 && fourth == 0x06) ||
          (third == 0x07 && fourth == 0x08);
      return isArchive ? null : mismatch(codec.magicHint);
    case CompressionCodec.tar:
      return _validTar(input) ? null : mismatch(codec.magicHint);
    case CompressionCodec.rawDeflate:
      return null;
  }
}

/// Validates a tar by checking its first header block against the POSIX
/// checksum stored at offset 148.
///
/// Neither signal is reliable on its own: `archive`'s TarEncoder emits
/// old-style v7 headers with no `ustar` marker, and its decoder happily
/// returns fabricated files for arbitrary 512-aligned garbage. The checksum
/// is the one field every tar writer is required to get right.
bool _validTar(Uint8List input) {
  const blockSize = 512;
  const checksumOffset = 148;
  const checksumLength = 8;
  if (input.length < blockSize || input.length % blockSize != 0) return false;

  var unsignedSum = 0;
  var signedSum = 0;
  for (var i = 0; i < blockSize; i++) {
    final byte = input[i];
    final counted = (i >= checksumOffset && i < checksumOffset + checksumLength)
        ? 0x20
        : byte;
    unsignedSum += counted;
    signedSum += counted > 127 ? counted - 256 : counted;
  }
  final stored = _parseOctal(input, checksumOffset, checksumLength);
  if (stored == null) return false;
  return stored == unsignedSum || stored == signedSum;
}

/// Reads a NUL-terminated octal field as used by tar headers.
int? _parseOctal(Uint8List bytes, int start, int length) {
  var value = 0;
  var sawDigit = false;
  for (var i = start; i < start + length; i++) {
    final byte = bytes[i];
    if (byte == 0 || byte == 0x20) break;
    if (byte < 0x30 || byte > 0x37) return null;
    value = value * 8 + (byte - 0x30);
    sawDigit = true;
  }
  return sawDigit ? value : null;
}

Archive _singleEntryArchive(Uint8List input) {
  return Archive()..add(ArchiveFile.string('payload.txt', utf8.decode(input)));
}

Uint8List _decodeBytes(Uint8List input, CompressionCodec codec) {
  switch (codec) {
    case CompressionCodec.gzip:
      return const GZipDecoder().decodeBytes(input);
    case CompressionCodec.zlib:
      return const ZLibDecoder().decodeBytes(input);
    case CompressionCodec.rawDeflate:
      return const ZLibDecoder().decodeBytes(input, raw: true);
    case CompressionCodec.bzip2:
      return BZip2Decoder().decodeBytes(input);
    case CompressionCodec.zip:
    case CompressionCodec.tar:
      throw _CompressionFailure('Use the archive path for container formats.');
  }
}

/// Accepts Base64 or hex on input, since compressed payloads are usually
/// pasted from one or the other depending on where they came from.
Uint8List decodePayload(String input) {
  final trimmed = input.trim().replaceAll(RegExp(r'\s+'), '');
  if (trimmed.isEmpty) return Uint8List(0);

  if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed) && trimmed.length.isEven) {
    // Ambiguous by design: a short hex string is also valid Base64, so only
    // treat it as hex when it is long enough to clearly be a byte dump.
    if (trimmed.length > 16) return hexToBytes(trimmed);
  }

  try {
    var value = trimmed.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = value.length % 4;
    if (remainder == 2) {
      value += '==';
    } else if (remainder == 3) {
      value += '=';
    } else if (remainder == 1) {
      throw const FormatException('Invalid Base64 length');
    }
    return base64Decode(value);
  } on FormatException {
    return hexToBytes(trimmed);
  }
}

String? _tryDecodeText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

String bytesToHexString(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List hexToBytes(String hex) {
  final cleaned = hex.replaceAll(RegExp(r'[\s:]'), '');
  final length = cleaned.length.isOdd ? cleaned.length - 1 : cleaned.length;
  final bytes = Uint8List(length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final byte = int.tryParse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) {
      throw const FormatException('Invalid hex pair');
    }
    bytes[i] = byte;
  }
  return bytes;
}

String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String _ratio(int input, int output) {
  if (input == 0) return '0.0% of original';
  return '${(output / input * 100).toStringAsFixed(1)}% of original';
}

String _describe(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

/// Carries a display-ready message out of the codec layer.
class _CompressionFailure implements Exception {
  const _CompressionFailure(this.message);

  final String message;
}