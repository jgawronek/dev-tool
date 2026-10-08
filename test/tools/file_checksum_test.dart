import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/file_checksum_service.dart';
import 'package:dev_tool/ui/widgets.dart';

import '../helpers/tool_harness.dart';

void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body,
) {
  testWidgets(description, (tester) async {
    final h = ToolHarness(tester);
    await h.open(toolId, surface: const Size(1600, 1200));
    await body(h);
  });
}

void main() {
  late Directory tempDir;
  late File sample;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('devutils_checksum');
    sample = File('${tempDir.path}/sample.txt');
    sample.writeAsStringSync('The quick brown fox jumps over the lazy dog');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('digests', () {
    test('match the well-known published checksums', () async {
      final outcome = await checksumFile(sample.path);
      expect(outcome.error, isNull, reason: outcome.error);
      expect(
        outcome.forAlgorithm(ChecksumAlgorithm.md5)!.digest,
        '9e107d9d372bb6826bd81d3542a419d6',
      );
      expect(
        outcome.forAlgorithm(ChecksumAlgorithm.sha1)!.digest,
        '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12',
      );
      expect(
        outcome.forAlgorithm(ChecksumAlgorithm.sha256)!.digest,
        'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592',
      );
    });

    test('a zero-byte file still hashes', () async {
      final empty = File('${tempDir.path}/empty.bin')
        ..writeAsBytesSync(const []);
      final outcome = await checksumFile(empty.path);
      expect(outcome.error, isNull);
      expect(outcome.sizeBytes, 0);
      expect(
        outcome.forAlgorithm(ChecksumAlgorithm.sha256)!.digest,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('digest is independent of chunk boundaries', () async {
      // A file larger than one read buffer must hash identically to a
      // whole-file digest, proving the streaming path is correct.
      final bytes = List<int>.generate(200000, (i) => (i * 31) % 256);
      final big = File('${tempDir.path}/big.bin')..writeAsBytesSync(bytes);
      final outcome = await checksumFile(big.path);
      expect(outcome.error, isNull);
      expect(outcome.sizeBytes, 200000);
      expect(
        outcome.forAlgorithm(ChecksumAlgorithm.sha256)!.digest,
        _sha256Hex(bytes),
      );
    });

    test('a missing file reports instead of throwing', () async {
      final outcome = await checksumFile('${tempDir.path}/nope.bin');
      expect(outcome.error, contains('File not found'));
      expect(outcome.checksums, isEmpty);
    });

    test('a directory path is reported, not hashed', () async {
      final outcome = await checksumFile(tempDir.path);
      expect(outcome.error, isNotNull);
    });
  });

  group('manifests', () {
    test('renders one shasum line per algorithm', () async {
      final outcome = await checksumFile(sample.path);
      final manifest = outcome.toManifest();
      expect(manifest.split('\n'), hasLength(4));
      expect(manifest, contains('9e107d9d372bb6826bd81d3542a419d6  sample.txt'));
    });

    test('parses a standard manifest', () {
      final parsed = parseChecksumManifest(
        'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592  app.zip\n'
        '9e107d9d372bb6826bd81d3542a419d6 *binary.bin\n'
        '# a comment\n'
        '\n',
      );
      expect(parsed['app.zip'], startsWith('d7a8fbb3'));
      expect(parsed['binary.bin'], '9e107d9d372bb6826bd81d3542a419d6');
      expect(parsed, hasLength(2));
    });

    test('parses a bare digest with no filename', () {
      final parsed = parseChecksumManifest(
        'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592',
      );
      expect(parsed.values.single, startsWith('d7a8fbb3'));
    });

    test('ignores lines that are not checksums', () {
      expect(parseChecksumManifest('hello world\nnot a hash'), isEmpty);
    });

    test('bareDigest only accepts hex of digest length', () {
      expect(
        bareDigest('d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592'),
        isNotNull,
      );
      expect(bareDigest('9e107d9d372bb6826bd81d3542a419d6'), isNotNull);
      expect(bareDigest('short'), isNull);
      expect(bareDigest('zzzz'), isNull);
      expect(bareDigest(''), isNull);
    });
  });

  group('verification', () {
    test('a matching digest verifies and reports the algorithm', () async {
      final expected =
          'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592';
      final outcome = await checksumFile(sample.path, expectedDigest: expected);
      expect(outcome.match, isTrue);
      expect(outcome.checkedAlgorithm, ChecksumAlgorithm.sha256);
    });

    test('a mismatched digest reports false rather than throwing', () async {
      final outcome = await checksumFile(
        sample.path,
        expectedDigest: '0000000000000000000000000000000000000000000000000000000000000000',
      );
      expect(outcome.match, isFalse);
      expect(outcome.checkedAlgorithm, isNull);
    });

    test('no expected digest leaves match unset', () async {
      final outcome = await checksumFile(sample.path);
      expect(outcome.match, isNull);
    });

    test('unparseable expected text is ignored rather than failing', () async {
      final outcome = await checksumFile(
        sample.path,
        expectedDigest: 'I do not know',
      );
      expect(outcome.error, isNull);
      expect(outcome.match, isNull);
      expect(outcome.checksums, isNotEmpty);
    });

    test('a short MD5 digest still verifies against the right algorithm', () async {
      final outcome = await checksumFile(
        sample.path,
        expectedDigest: '9e107d9d372bb6826bd81d3542a419d6',
      );
      expect(outcome.match, isTrue);
      expect(outcome.checkedAlgorithm, ChecksumAlgorithm.md5);
    });
  });
  group('tool view', () {
    // Selecting a file goes through the native dialog, which returns null in
    // the test environment, so the reachable UI surface is exercised here and
    // the hashing itself is covered by the service tests above.
    toolTest('prompts for a file on open', 'file_checksum', (h) async {
      expect(
        find.textContaining('Choose a file or drop one onto the panel'),
        findsOneWidget,
      );
      expect(find.text('No file selected'), findsOneWidget);
    });

    toolTest('renders the controls', 'file_checksum', (h) async {
      expect(find.text('Choose file...'), findsOneWidget);
      expect(find.text('Copy manifest'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
    });

    toolTest('tapping choose file without a plugin is harmless',
        'file_checksum', (h) async {
      await h.tap('Choose file...');
      await h.settle();
      expect(h.tester.takeException(), isNull);
      expect(find.text('No file selected'), findsOneWidget);
    });

    toolTest('clear resets the panel', 'file_checksum', (h) async {
      await setExpected(h, 'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592');
      await h.tap('Clear');
      await h.settle();
      expect(find.text('No file selected'), findsOneWidget);
    });

    toolTest('verify stays disabled until a file is chosen', 'file_checksum',
        (h) async {
      final button = h.tester
          .widgetList<ToolButton>(find.byType(ToolButton))
          .firstWhere((b) => b.label == 'Verify');
      expect(button.onPressed, isNull);
    });
  });
}

/// Sets the optional "expected digest" field.
Future<void> setExpected(ToolHarness h, String value) async {
  final field = h.tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((f) => f.decoration?.hintText == 'Paste a checksum to verify');
  field.controller!.text = value;
  await h.settle();
}

/// Independent reference so the test does not depend on the code under test.
String _sha256Hex(List<int> bytes) {
  var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
  final message = <int>[...bytes];
  final bitLength = bytes.length * 8;
  message.add(0x80);
  while (message.length % 64 != 56) {
    message.add(0);
  }
  for (var i = 7; i >= 0; i--) {
    message.add((bitLength >> (8 * i)) & 0xff);
  }
  final k = _k256;
  final w = List<int>.filled(64, 0);
  for (var chunk = 0; chunk < message.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      final o = chunk + i * 4;
      w[i] = (message[o] << 24) | (message[o + 1] << 16) |
          (message[o + 2] << 8) | message[o + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;
      h = g; g = f; f = e;
      e = (d + temp1) & 0xffffffff;
      d = c; c = b; b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    h0 = (h0 + a) & 0xffffffff; h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff; h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff; h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff; h7 = (h7 + h) & 0xffffffff;
  }
  return [h0, h1, h2, h3, h4, h5, h6, h7]
      .map((v) => v.toRadixString(16).padLeft(8, '0'))
      .join();
}

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

const _k256 = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];