/// File checksum generation and verification.
///
/// Digests are computed by streaming the file in chunks, so a multi-gigabyte
/// download never has to fit in memory. Safe to run in an isolate.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Digests offered by the tool.
enum ChecksumAlgorithm {
  md5('MD5', 'md5sum'),
  sha1('SHA-1', 'sha1sum'),
  sha256('SHA-256', 'sha256sum'),
  sha512('SHA-512', 'sha512sum');

  const ChecksumAlgorithm(this.label, this.command);

  final String label;

  /// Name of the coreutils tool that produces the same output.
  final String command;

  /// Expected digest length in hex characters, used to guess which algorithm
  /// a pasted checksum belongs to.
  int get hexLength => switch (this) {
    ChecksumAlgorithm.md5 => 32,
    ChecksumAlgorithm.sha1 => 40,
    ChecksumAlgorithm.sha256 => 64,
    ChecksumAlgorithm.sha512 => 128,
  };
}

/// One computed digest for a file.
class FileChecksum {
  const FileChecksum(this.algorithm, this.digest);

  final ChecksumAlgorithm algorithm;

  /// Lowercase hex digest.
  final String digest;

  /// The line `sha256sum` would print for this file.
  String toShasumLine(String fileName) => '$digest  $fileName';
}

/// Result of hashing, and optionally verifying, a file.
class FileChecksumOutcome {
  const FileChecksumOutcome.success({
    required this.checksums,
    required this.fileName,
    required this.sizeBytes,
    this.match,
    this.checkedAlgorithm,
  }) : error = null;

  const FileChecksumOutcome.failure(this.error)
    : checksums = const [],
      fileName = '',
      sizeBytes = 0,
      match = null,
      checkedAlgorithm = null;

  final List<FileChecksum> checksums;
  final String fileName;
  final int sizeBytes;
  final String? error;

  /// Null unless an expected digest was supplied.
  final bool? match;

  /// Which algorithm the expected digest matched, when it matched.
  final ChecksumAlgorithm? checkedAlgorithm;

  /// The `<digest>  <file>` line for [algorithm], or null when absent.
  FileChecksum? forAlgorithm(ChecksumAlgorithm algorithm) {
    for (final checksum in checksums) {
      if (checksum.algorithm == algorithm) return checksum;
    }
    return null;
  }

  /// Ready-to-paste manifest, one `<digest>  <file>` line per algorithm.
  String toManifest() =>
      checksums.map((c) => c.toShasumLine(fileName)).join('\n');
}

/// Top-level so it can run inside an isolate via `compute`.
Future<FileChecksumOutcome> checksumFileWorker((String, String?) args) =>
    checksumFile(args.$1, expectedDigest: args.$2);

/// Hashes [path] with every algorithm, optionally comparing [expectedDigest].
///
/// When [expectedDigest] is a bare hex string it is matched against all four
/// digests, so the algorithm does not have to be chosen by hand.
Future<FileChecksumOutcome> checksumFile(
  String path, {
  String? expectedDigest,
}) async {
  final file = File(path);
  final name = fileName(path);
  if (!file.existsSync()) {
    return FileChecksumOutcome.failure('File not found: $name');
  }

  final sinks = <ChecksumAlgorithm, _DigestCollector>{};
  final feeds = <ChecksumAlgorithm, ByteConversionSink>{};
  for (final algorithm in ChecksumAlgorithm.values) {
    final sink = _DigestCollector();
    sinks[algorithm] = sink;
    feeds[algorithm] = _hashFor(algorithm).startChunkedConversion(sink);
  }

  try {
    await for (final chunk in file.openRead()) {
      for (final feed in feeds.values) {
        feed.add(chunk);
      }
    }
    for (final feed in feeds.values) {
      feed.close();
    }
  } on FileSystemException catch (error) {
    return FileChecksumOutcome.failure('Could not read $name: ${error.message}');
  } on ArgumentError catch (error) {
    return FileChecksumOutcome.failure('Could not read $name: ${error.message}');
  }

  final checksums = <FileChecksum>[
    for (final algorithm in ChecksumAlgorithm.values)
      FileChecksum(algorithm, sinks[algorithm]!.value.toString()),
  ];

  final expected = bareDigest(expectedDigest ?? '');
  if (expected == null) {
    return FileChecksumOutcome.success(
      checksums: checksums,
      fileName: name,
      sizeBytes: _lengthOf(file),
    );
  }

  FileChecksum? hit;
  for (final checksum in checksums) {
    if (checksum.digest == expected) {
      hit = checksum;
      break;
    }
  }
  return FileChecksumOutcome.success(
    checksums: checksums,
    fileName: name,
    sizeBytes: _lengthOf(file),
    match: hit != null,
    checkedAlgorithm: hit?.algorithm,
  );
}

/// Collects the single [Digest] a chunked hash conversion emits.
///
/// `crypto` does not export its own digest sink, and the conversion only
/// calls `add` once at `close`.
class _DigestCollector implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest value) => _value = value;

  @override
  void close() {}
}

Hash _hashFor(ChecksumAlgorithm algorithm) => switch (algorithm) {
  ChecksumAlgorithm.md5 => md5,
  ChecksumAlgorithm.sha1 => sha1,
  ChecksumAlgorithm.sha256 => sha256,
  ChecksumAlgorithm.sha512 => sha512,
};

int _lengthOf(File file) {
  try {
    return file.lengthSync();
  } on FileSystemException {
    return 0;
  }
}

String fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

/// Parses a `shasum`/`md5sum` manifest into filename-to-digest pairs.
///
/// Accepts the binary-mode `*` marker and a bare digest with no filename,
/// which is what most download pages show.
Map<String, String> parseChecksumManifest(String input) {
  final result = <String, String>{};
  for (final raw in const LineSplitter().convert(input)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = RegExp(
      r'^([0-9a-fA-F]{32,128})(?:\s+[*]?(.+))?$',
    ).firstMatch(line);
    if (match == null) continue;
    final name = match.group(2)?.trim();
    result[name == null || name.isEmpty ? '' : name] =
        match.group(1)!.toLowerCase();
  }
  return result;
}

/// Returns the digest from a single bare checksum, or null if there is none.
String? bareDigest(String input) {
  final trimmed = input.trim().toLowerCase();
  return RegExp(r'^[0-9a-f]{32,128}$').hasMatch(trimmed) ? trimmed : null;
}