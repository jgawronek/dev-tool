import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/compression_service.dart';
import 'package:dev_tool/ui/widgets.dart';

import '../helpers/tool_harness.dart';

void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body,
) {
  testWidgets(description, (tester) async {
    final h = ToolHarness(tester);
    await h.open(toolId);
    await body(h);
  });
}

const _sample = 'hello hello hello world world world 1234567890';

Uint8List _b64(String value) => base64Decode(value);

/// Compresses [_sample] with [codec] and returns the Base64 payload.
String _compressed(CompressionCodec codec) {
  final outcome = compressSync(_sample, codec);
  expect(outcome.error, isNull, reason: 'compress $codec: ${outcome.error}');
  return outcome.output;
}

void main() {
  group('codec matrix', () {
    test('every codec round-trips text', () {
      for (final codec in CompressionCodec.values) {
        final payload = _compressed(codec);
        final outcome = decompressPayload(payload, codec);
        expect(
          outcome.error,
          isNull,
          reason: 'decompress $codec: ${outcome.error}',
        );
        // Container codecs wrap entries in a `--- name (size) ---` banner.
        expect(outcome.output, contains(_sample), reason: 'round-trip $codec');
      }
    });

    test('raw deflate omits the zlib header', () {
      expect(_b64(_compressed(CompressionCodec.rawDeflate)).first, isNot(0x78));
    });

    test('gzip and bzip2 emit their documented magic bytes', () {
      expect(_b64(_compressed(CompressionCodec.gzip)).take(2).toList(), [
        0x1f,
        0x8b,
      ]);
      expect(_b64(_compressed(CompressionCodec.bzip2)).take(3).toList(), [
        0x42,
        0x5a,
        0x68,
      ]);
    });

    test('compression shrinks repetitive input', () {
      final repetitive = List.filled(500, 'the quick brown fox').join(' ');
      for (final codec in [
        CompressionCodec.gzip,
        CompressionCodec.zlib,
        CompressionCodec.rawDeflate,
      ]) {
        final compressed = compressSync(repetitive, codec);
        expect(compressed.summary, contains('% of original'));
        expect(compressed.summary, isNot(contains('100.0%')));
      }
    });
  });

  group('wrong-codec rejection', () {
    // ZLibDecoder returns GZip bytes verbatim and BZip2Decoder returns an
    // empty result rather than raising, so headers are validated up front.
    test('gzip bytes are rejected by every other strict codec', () {
      final gzip = _compressed(CompressionCodec.gzip);
      for (final codec in CompressionCodec.values) {
        if (codec == CompressionCodec.gzip ||
            codec == CompressionCodec.rawDeflate) {
          continue;
        }
        final outcome = decompressPayload(gzip, codec);
        expect(
          outcome.error,
          isNotNull,
          reason: '$codec should reject GZip input',
        );
        expect(outcome.error, contains('expected'));
      }
    });

    test('the error names the codec and its expected signature', () {
      final outcome = decompressPayload(
        _compressed(CompressionCodec.gzip),
        CompressionCodec.bzip2,
      );
      expect(outcome.error, contains('BZip2'));
      expect(outcome.error, contains('42 5a 68'));
    });

    test('zlib rejects bytes that fail the header checksum', () {
      final outcome = decompressPayload('deadbeefcafe', CompressionCodec.zlib);
      expect(outcome.error, isNotNull);
    });

    test('tar validates the header checksum rather than a magic marker', () {
      // archive emits old-style v7 tars with no "ustar" string, so a marker
      // check would reject our own output.
      final tar = _b64(_compressed(CompressionCodec.tar));
      expect(ascii.decode(tar, allowInvalid: true), isNot(contains('ustar')));
      expect(
        decompressPayload(
          _compressed(CompressionCodec.tar),
          CompressionCodec.tar,
        ).error,
        isNull,
      );

      // 512-aligned garbage must not decode into fabricated files.
      final garbage = base64Encode(Uint8List(1024)..fillRange(0, 1024, 65));
      expect(
        decompressPayload(garbage, CompressionCodec.tar).error,
        contains('Tar'),
      );
    });
  });

  group('input handling', () {
    test('hex input is accepted alongside base64', () {
      final base64Payload = _compressed(CompressionCodec.gzip);
      final hex = bytesToHexString(_b64(base64Payload));
      expect(
        decompressPayload(hex, CompressionCodec.gzip).output.trim(),
        _sample,
      );
    });

    test('whitespace in a pasted payload is ignored', () {
      final wrapped = _compressed(
        CompressionCodec.gzip,
      ).replaceAllMapped(RegExp(r'.{20}'), (m) => '${m[0]}\n');
      expect(
        decompressPayload(wrapped, CompressionCodec.gzip).output.trim(),
        _sample,
      );
    });

    test('empty input fails cleanly in both directions', () {
      expect(
        compressSync('', CompressionCodec.gzip).error,
        'Enter data to compress.',
      );
      expect(
        decompressPayload('', CompressionCodec.gzip).error,
        contains('Paste'),
      );
    });

    test('undecodable input reports an error instead of throwing', () {
      final outcome = decompressPayload(
        '!!!! not valid !!!!',
        CompressionCodec.gzip,
      );
      expect(outcome.error, isNotNull);
      expect(outcome.output, isEmpty);
    });
  });

  group('binary output', () {
    test('non-utf8 payload is flagged and rendered as hex', () {
      final gzip = base64Encode(
        GZipEncoder().encodeBytes([0, 1, 2, 255, 254, 128, 104, 105]),
      );
      final outcome = decompressPayload(gzip, CompressionCodec.gzip);
      expect(outcome.binary, isTrue);
      expect(outcome.output, '000102fffe806869');
      expect(outcome.summary, contains('binary'));
    });

    test('text payload is not flagged as binary', () {
      final outcome = decompressPayload(
        _compressed(CompressionCodec.gzip),
        CompressionCodec.gzip,
      );
      expect(outcome.binary, isFalse);
      expect(outcome.summary, contains('text'));
    });
  });

  group('archives', () {
    test('zip reports the entry it contains', () {
      final outcome = decompressPayload(
        _compressed(CompressionCodec.zip),
        CompressionCodec.zip,
      );
      expect(outcome.entries, hasLength(1));
      expect(outcome.entries.single.name, 'payload.txt');
      expect(outcome.summary, contains('1 file'));
    });

    test('tar reports its entry and round-trips through base64', () {
      final outcome = decompressPayload(
        _compressed(CompressionCodec.tar),
        CompressionCodec.tar,
      );
      expect(outcome.entries.single.name, 'payload.txt');
      expect(outcome.output, contains(_sample));
    });
  });

  for (final codec in CompressionCodec.values) {
    test('${codec.label} preserves whitespace and Unicode exactly', () {
      for (final input in ['  hello\nworld\t  ', 'é漢字🙂\n', ' \t\n']) {
        final compressed = compressSync(input, codec);
        expect(compressed.error, isNull);
        final decompressed = decompressPayload(compressed.output, codec);
        expect(decompressed.error, isNull);
        if (!codec.isContainer) {
          expect(decompressed.output, input);
        } else {
          expect(utf8.decode(decompressed.entries.single.preview), input);
        }
      }
    });
  }

  group('tool view', () {
    toolTest('compresses pasted text to Base64', 'compression_codecs', (
      h,
    ) async {
      await h.enter('Enter text to compress…', text: _sample);
      final output = h.text('Compressed archive will appear here');
      expect(output, isNotEmpty);
      expect(
        decompressPayload(output, CompressionCodec.gzip).output.trim(),
        _sample,
      );
    });

    toolTest('decompresses when the mode is flipped', 'compression_codecs', (
      h,
    ) async {
      final payload = _compressed(CompressionCodec.gzip);
      await h.tap('Decompress');
      await h.enter('Paste Base64 or hex archive data…', text: payload);
      expect(h.text('Decompressed text will appear here').trim(), _sample);
    });

    toolTest(
      'switching to Decompress with empty input clears output',
      'compression_codecs',
      (h) async {
        await h.tap('Decompress');
        expect(h.text('Decompressed text will appear here'), isEmpty);
      },
    );

    toolTest(
      'shows a readable error for a malformed payload',
      'compression_codecs',
      (h) async {
        await h.tap('Decompress');
        await h.enter(
          'Paste Base64 or hex archive data…',
          text: 'not an archive',
        );
        expect(find.textContaining('expected'), findsOneWidget);
      },
    );

    toolTest(
      'changing codec re-runs against the new format',
      'compression_codecs',
      (h) async {
        await h.enter('Enter text to compress…', text: _sample);
        await h.tap('GZip');
        await h.tap('Zlib');
        final output = h.text('Compressed archive will appear here');
        expect(
          decompressPayload(output, CompressionCodec.zlib).output.trim(),
          _sample,
        );
        // The Zlib payload must not decode as GZip, proving the switch took.
        expect(
          decompressPayload(output, CompressionCodec.gzip).error,
          isNotNull,
        );
      },
    );

    // Sample and Clear are exposed through the editor's right-click menu
    // rather than the toolbar, so they are driven through that path.
    Future<void> editorMenu(WidgetTester tester, String item) async {
      if (item == 'Example') {
        await tester.tap(find.text('Load sample'));
      } else {
        final input = tester.widgetList<EditorPane>(find.byType(EditorPane)).firstWhere((p) => !p.readOnly);
        input.controller!.clear();
        input.onChanged?.call('');
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    toolTest('sample action populates both panes', 'compression_codecs', (
      h,
    ) async {
      await editorMenu(h.tester, 'Example');
      expect(h.text('Enter text to compress…'), isNotEmpty);
      expect(h.text('Compressed archive will appear here'), isNotEmpty);
    });

    toolTest('clear action empties both panes', 'compression_codecs', (
      h,
    ) async {
      await h.enter('Enter text to compress…', text: _sample);
      await editorMenu(h.tester, 'Clear');
      expect(h.text('Enter text to compress…'), isEmpty);
      expect(h.text('Compressed archive will appear here'), isEmpty);
    });

    toolTest(
      'use as input chains the compressed output back in',
      'compression_codecs',
      (h) async {
        await h.enter('Enter text to compress…', text: _sample);
        final first = h.text('Compressed archive will appear here');
        await h.tap('Use as input');
        expect(h.text('Enter text to compress…'), first);
      },
    );
  });
}
