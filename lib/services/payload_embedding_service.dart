import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';

enum PayloadCarrierFormat {
  png('PNG', 'PNG ancillary chunk'),
  jpeg('JPEG', 'JPEG APP15 segments'),
  pdf('PDF', 'PDF comment block');

  const PayloadCarrierFormat(this.label, this.method);

  final String label;
  final String method;
}

class PayloadEmbedResult {
  const PayloadEmbedResult({required this.bytes, required this.info});

  final Uint8List bytes;
  final EmbeddedPayloadInfo info;
}

class EmbeddedPayloadInfo {
  const EmbeddedPayloadInfo({
    required this.format,
    required this.method,
    required this.envelopeSize,
    required this.carrierSize,
    required this.segmentCount,
    required this.iterations,
  });

  final PayloadCarrierFormat format;
  final String method;
  final int envelopeSize;
  final int carrierSize;
  final int segmentCount;
  final int iterations;

  String get summary =>
      '${format.label} · $method · encrypted payload · ${_formatBytes(envelopeSize)}';
}

class DecodedEmbeddedPayload {
  const DecodedEmbeddedPayload({
    required this.fileName,
    required this.bytes,
    required this.embeddedAt,
    required this.originalSize,
  });

  final String fileName;
  final Uint8List bytes;
  final DateTime? embeddedAt;
  final int originalSize;
}

class PayloadEmbeddingService {
  PayloadEmbeddingService._();

  static const defaultIterations = 60000;
  static const _macLength = 32;

  static final Uint8List _envelopeMagic = Uint8List.fromList(
    ascii.encode('DVTGv001'),
  );
  static final Uint8List _plainMagic = Uint8List.fromList(
    ascii.encode('DVTPv001'),
  );
  static final Uint8List _pngSignature = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);
  static final Uint8List _pngPayloadChunk = Uint8List.fromList(
    ascii.encode('dvUt'),
  );
  static final Uint8List _jpegSegmentMagic = Uint8List.fromList(
    ascii.encode('DVUTJ1'),
  );
  static const _jpegPayloadMarker = 0xEF; // APP15
  static const _pdfBeginMarker = '%DVUT-PAYLOAD-BEGIN';
  static const _pdfEndMarker = '%DVUT-PAYLOAD-END';

  static PayloadCarrierFormat detectFormat(Uint8List bytes) {
    if (_startsWith(bytes, _pngSignature)) {
      return PayloadCarrierFormat.png;
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return PayloadCarrierFormat.jpeg;
    }
    final probeLength = min(bytes.length, 1024);
    final probe = latin1.decode(bytes.sublist(0, probeLength));
    if (probe.contains('%PDF-')) {
      return PayloadCarrierFormat.pdf;
    }
    throw const FormatException(
      'Supported carrier formats are PNG, JPG, and PDF.',
    );
  }

  static PayloadEmbedResult embed({
    required Uint8List carrier,
    required Uint8List payload,
    required String payloadFileName,
    required String passphrase,
    int iterations = defaultIterations,
  }) {
    if (passphrase.isEmpty) {
      throw ArgumentError(
        'Passphrase is required to encrypt the embedded file.',
      );
    }
    if (payloadFileName.trim().isEmpty) {
      throw ArgumentError('Payload filename is required.');
    }
    final format = detectFormat(carrier);
    final envelope = _buildEnvelope(
      payload: payload,
      fileName: payloadFileName,
      passphrase: passphrase,
      iterations: iterations,
    );

    final embedded = switch (format) {
      PayloadCarrierFormat.png => _embedPng(carrier, envelope),
      PayloadCarrierFormat.jpeg => _embedJpeg(carrier, envelope),
      PayloadCarrierFormat.pdf => _embedPdf(carrier, envelope),
    };

    final info =
        inspect(embedded) ??
        EmbeddedPayloadInfo(
          format: format,
          method: format.method,
          envelopeSize: envelope.length,
          carrierSize: embedded.length,
          segmentCount: 1,
          iterations: iterations,
        );
    return PayloadEmbedResult(bytes: embedded, info: info);
  }

  static EmbeddedPayloadInfo? inspect(Uint8List carrier) {
    final format = detectFormat(carrier);
    final extraction = switch (format) {
      PayloadCarrierFormat.png => _extractPngEnvelope(carrier),
      PayloadCarrierFormat.jpeg => _extractJpegEnvelope(carrier),
      PayloadCarrierFormat.pdf => _extractPdfEnvelope(carrier),
    };
    if (extraction == null) return null;
    final envelope = _parseEnvelope(extraction.bytes);
    return EmbeddedPayloadInfo(
      format: format,
      method: format.method,
      envelopeSize: extraction.bytes.length,
      carrierSize: carrier.length,
      segmentCount: extraction.segmentCount,
      iterations: envelope.iterations,
    );
  }

  static DecodedEmbeddedPayload extract({
    required Uint8List carrier,
    required String passphrase,
  }) {
    if (passphrase.isEmpty) {
      throw ArgumentError(
        'Passphrase is required to decode the embedded file.',
      );
    }
    final format = detectFormat(carrier);
    final extraction = switch (format) {
      PayloadCarrierFormat.png => _extractPngEnvelope(carrier),
      PayloadCarrierFormat.jpeg => _extractJpegEnvelope(carrier),
      PayloadCarrierFormat.pdf => _extractPdfEnvelope(carrier),
    };
    if (extraction == null) {
      throw const FormatException('No DevUtils encrypted payload was found.');
    }
    return _decryptEnvelope(extraction.bytes, passphrase);
  }

  static Uint8List _buildEnvelope({
    required Uint8List payload,
    required String fileName,
    required String passphrase,
    required int iterations,
  }) {
    if (iterations < 1000) {
      throw ArgumentError('PBKDF2 iterations must be at least 1000.');
    }

    final metadata = <String, Object>{
      'fileName': fileName,
      'size': payload.length,
      'embeddedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final metadataBytes = Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
    final plainBuilder = BytesBuilder(copy: false)
      ..add(_plainMagic)
      ..add(_uint32(metadataBytes.length))
      ..add(metadataBytes)
      ..add(payload);
    final plain = plainBuilder.toBytes();

    final salt = _secureRandomBytes(16);
    final iv = _secureRandomBytes(16);
    final keys = _pbkdf2Sha256(
      Uint8List.fromList(utf8.encode(passphrase)),
      salt,
      iterations,
      64,
    );
    final encryptionKey = Uint8List.fromList(keys.sublist(0, 32));
    final macKey = Uint8List.fromList(keys.sublist(32, 64));
    final ciphertext = _aesCbcCrypt(
      _pkcs7Pad(plain, 16),
      encryptionKey,
      iv,
      encrypt: true,
    );

    final header = BytesBuilder(copy: false)
      ..add(_envelopeMagic)
      ..add(_uint32(iterations))
      ..addByte(salt.length)
      ..addByte(iv.length)
      ..add(_uint32(ciphertext.length))
      ..add(salt)
      ..add(iv)
      ..add(ciphertext);
    final headerBytes = header.toBytes();
    final mac = _hmacSha256(macKey, headerBytes);
    return Uint8List.fromList([...headerBytes, ...mac]);
  }

  static DecodedEmbeddedPayload _decryptEnvelope(
    Uint8List envelope,
    String passphrase,
  ) {
    final parsed = _parseEnvelope(envelope);
    final keys = _pbkdf2Sha256(
      Uint8List.fromList(utf8.encode(passphrase)),
      parsed.salt,
      parsed.iterations,
      64,
    );
    final encryptionKey = Uint8List.fromList(keys.sublist(0, 32));
    final macKey = Uint8List.fromList(keys.sublist(32, 64));
    final expectedMac = _hmacSha256(macKey, parsed.authenticatedBytes);
    if (!_constantTimeEquals(expectedMac, parsed.mac)) {
      throw const FormatException(
        'Wrong passphrase or corrupted embedded payload.',
      );
    }

    final decrypted = _pkcs7Unpad(
      _aesCbcCrypt(parsed.ciphertext, encryptionKey, parsed.iv, encrypt: false),
    );
    if (!_startsWith(decrypted, _plainMagic) || decrypted.length < 12) {
      throw const FormatException('Decoded payload envelope is invalid.');
    }
    final metadataLength = _readUint32(decrypted, _plainMagic.length);
    final metadataStart = _plainMagic.length + 4;
    final metadataEnd = metadataStart + metadataLength;
    if (metadataEnd > decrypted.length) {
      throw const FormatException('Decoded payload metadata is truncated.');
    }
    final metadata =
        jsonDecode(utf8.decode(decrypted.sublist(metadataStart, metadataEnd)))
            as Map<String, dynamic>;
    final payload = Uint8List.fromList(decrypted.sublist(metadataEnd));
    final fileName = (metadata['fileName'] as String?)?.trim();
    final embeddedAtRaw = metadata['embeddedAt'] as String?;
    return DecodedEmbeddedPayload(
      fileName: fileName == null || fileName.isEmpty ? 'payload.bin' : fileName,
      bytes: payload,
      embeddedAt: embeddedAtRaw == null
          ? null
          : DateTime.tryParse(embeddedAtRaw),
      originalSize: metadata['size'] as int? ?? payload.length,
    );
  }

  static _ParsedEnvelope _parseEnvelope(Uint8List envelope) {
    const fixedHeaderLength = 8 + 4 + 1 + 1 + 4;
    if (envelope.length < fixedHeaderLength + _macLength ||
        !_startsWith(envelope, _envelopeMagic)) {
      throw const FormatException(
        'No DevUtils encrypted payload envelope found.',
      );
    }
    var offset = _envelopeMagic.length;
    final iterations = _readUint32(envelope, offset);
    offset += 4;
    final saltLength = envelope[offset++];
    final ivLength = envelope[offset++];
    final cipherLength = _readUint32(envelope, offset);
    offset += 4;

    final expectedLength =
        offset + saltLength + ivLength + cipherLength + _macLength;
    if (saltLength < 8 ||
        ivLength != 16 ||
        iterations < 1000 ||
        expectedLength != envelope.length) {
      throw const FormatException('Embedded payload envelope is malformed.');
    }

    final salt = Uint8List.fromList(
      envelope.sublist(offset, offset + saltLength),
    );
    offset += saltLength;
    final iv = Uint8List.fromList(envelope.sublist(offset, offset + ivLength));
    offset += ivLength;
    final ciphertext = Uint8List.fromList(
      envelope.sublist(offset, offset + cipherLength),
    );
    offset += cipherLength;
    final mac = Uint8List.fromList(
      envelope.sublist(offset, offset + _macLength),
    );
    final authenticatedBytes = Uint8List.fromList(
      envelope.sublist(0, envelope.length - _macLength),
    );
    return _ParsedEnvelope(
      iterations: iterations,
      salt: salt,
      iv: iv,
      ciphertext: ciphertext,
      mac: mac,
      authenticatedBytes: authenticatedBytes,
    );
  }

  static Uint8List _embedPng(Uint8List carrier, Uint8List envelope) {
    if (!_startsWith(carrier, _pngSignature)) {
      throw const FormatException('Invalid PNG signature.');
    }
    final out = BytesBuilder(copy: false)..add(_pngSignature);
    var offset = _pngSignature.length;
    var inserted = false;
    while (offset < carrier.length) {
      if (offset + 12 > carrier.length) {
        throw const FormatException('PNG chunk table is truncated.');
      }
      final chunkStart = offset;
      final length = _readUint32(carrier, offset);
      offset += 4;
      final type = carrier.sublist(offset, offset + 4);
      offset += 4;
      final dataEnd = offset + length;
      final chunkEnd = dataEnd + 4;
      if (chunkEnd > carrier.length) {
        throw const FormatException('PNG chunk length exceeds file size.');
      }

      final isPayloadChunk = _listEquals(type, _pngPayloadChunk);
      if (!isPayloadChunk) {
        out.add(carrier.sublist(chunkStart, chunkEnd));
      }
      offset = chunkEnd;

      if (!inserted && _asciiEquals(type, 'IHDR')) {
        out.add(_pngChunk(_pngPayloadChunk, envelope));
        inserted = true;
      }
    }
    if (!inserted) {
      throw const FormatException('PNG IHDR chunk was not found.');
    }
    return out.toBytes();
  }

  static _EnvelopeExtraction? _extractPngEnvelope(Uint8List carrier) {
    if (!_startsWith(carrier, _pngSignature)) {
      throw const FormatException('Invalid PNG signature.');
    }
    var offset = _pngSignature.length;
    var count = 0;
    Uint8List? envelope;
    while (offset < carrier.length) {
      if (offset + 12 > carrier.length) {
        throw const FormatException('PNG chunk table is truncated.');
      }
      final length = _readUint32(carrier, offset);
      offset += 4;
      final type = carrier.sublist(offset, offset + 4);
      offset += 4;
      final dataEnd = offset + length;
      final chunkEnd = dataEnd + 4;
      if (chunkEnd > carrier.length) {
        throw const FormatException('PNG chunk length exceeds file size.');
      }
      if (_listEquals(type, _pngPayloadChunk)) {
        envelope ??= Uint8List.fromList(carrier.sublist(offset, dataEnd));
        count++;
      }
      offset = chunkEnd;
    }
    if (envelope == null) return null;
    return _EnvelopeExtraction(bytes: envelope, segmentCount: count);
  }

  static Uint8List _embedJpeg(Uint8List carrier, Uint8List envelope) {
    if (carrier.length < 2 || carrier[0] != 0xFF || carrier[1] != 0xD8) {
      throw const FormatException('Invalid JPEG signature.');
    }
    final stripped = _stripJpegPayloadSegments(carrier);
    final out = BytesBuilder(copy: false)
      ..add(stripped.sublist(0, 2))
      ..add(_buildJpegPayloadSegments(envelope))
      ..add(stripped.sublist(2));
    return out.toBytes();
  }

  static _EnvelopeExtraction? _extractJpegEnvelope(Uint8List carrier) {
    final segments = <_JpegPayloadSegment>[];
    _walkJpegSegments(
      carrier,
      onPayload: (index, total, bytes) {
        segments.add(
          _JpegPayloadSegment(index: index, total: total, bytes: bytes),
        );
      },
    );
    if (segments.isEmpty) return null;
    segments.sort((a, b) => a.index.compareTo(b.index));
    final total = segments.first.total;
    if (segments.length != total ||
        segments.any((segment) => segment.total != total)) {
      throw const FormatException(
        'JPEG embedded payload segments are incomplete.',
      );
    }
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < total; i++) {
      final segment = segments[i];
      if (segment.index != i) {
        throw const FormatException(
          'JPEG embedded payload segment order is invalid.',
        );
      }
      builder.add(segment.bytes);
    }
    return _EnvelopeExtraction(bytes: builder.toBytes(), segmentCount: total);
  }

  static Uint8List _stripJpegPayloadSegments(Uint8List carrier) {
    final out = BytesBuilder(copy: false);
    if (carrier.length < 2 || carrier[0] != 0xFF || carrier[1] != 0xD8) {
      throw const FormatException('Invalid JPEG signature.');
    }
    out.add(carrier.sublist(0, 2));
    var copiedTail = false;
    _walkJpegSegments(
      carrier,
      onSegment: (start, end, marker, isPayload) {
        if (!isPayload) out.add(carrier.sublist(start, end));
        if (marker == 0xDA) {
          out.add(carrier.sublist(end));
          copiedTail = true;
        }
      },
    );
    if (!copiedTail) {
      final consumed = _jpegParsedLength(carrier);
      if (consumed < carrier.length) out.add(carrier.sublist(consumed));
    }
    return out.toBytes();
  }

  static int _jpegParsedLength(Uint8List carrier) {
    var lastEnd = 2;
    _walkJpegSegments(
      carrier,
      onSegment: (start, end, marker, isPayload) {
        lastEnd = end;
      },
    );
    return lastEnd;
  }

  static Uint8List _buildJpegPayloadSegments(Uint8List envelope) {
    const headerLength = 6 + 2 + 2;
    const maxSegmentData = 65533;
    const maxChunk = maxSegmentData - headerLength;
    final total = (envelope.length / maxChunk).ceil();
    if (total > 0xFFFF) {
      throw const FormatException(
        'Payload is too large for JPEG APP15 storage.',
      );
    }
    final out = BytesBuilder(copy: false);
    for (var index = 0; index < total; index++) {
      final start = index * maxChunk;
      final end = min(start + maxChunk, envelope.length);
      final data = BytesBuilder(copy: false)
        ..add(_jpegSegmentMagic)
        ..add(_uint16(index))
        ..add(_uint16(total))
        ..add(envelope.sublist(start, end));
      final payload = data.toBytes();
      out.add([0xFF, _jpegPayloadMarker]);
      out.add(_uint16(payload.length + 2));
      out.add(payload);
    }
    return out.toBytes();
  }

  static void _walkJpegSegments(
    Uint8List carrier, {
    void Function(int index, int total, Uint8List bytes)? onPayload,
    void Function(int start, int end, int marker, bool isPayload)? onSegment,
  }) {
    if (carrier.length < 2 || carrier[0] != 0xFF || carrier[1] != 0xD8) {
      throw const FormatException('Invalid JPEG signature.');
    }
    var offset = 2;
    while (offset < carrier.length) {
      final markerStart = offset;
      if (carrier[offset] != 0xFF) {
        return;
      }
      while (offset < carrier.length && carrier[offset] == 0xFF) {
        offset++;
      }
      if (offset >= carrier.length) return;
      final marker = carrier[offset++];
      if (_isStandaloneJpegMarker(marker)) {
        onSegment?.call(markerStart, offset, marker, false);
        if (marker == 0xD9) return;
        continue;
      }
      if (offset + 2 > carrier.length) {
        throw const FormatException('JPEG segment length is truncated.');
      }
      final length = _readUint16(carrier, offset);
      if (length < 2) {
        throw const FormatException('JPEG segment length is invalid.');
      }
      final dataStart = offset + 2;
      final segmentEnd = offset + length;
      if (segmentEnd > carrier.length) {
        throw const FormatException('JPEG segment exceeds file size.');
      }
      var isPayload = false;
      if (marker == _jpegPayloadMarker &&
          segmentEnd - dataStart >= _jpegSegmentMagic.length + 4 &&
          _startsWithAt(carrier, _jpegSegmentMagic, dataStart)) {
        isPayload = true;
        final index = _readUint16(
          carrier,
          dataStart + _jpegSegmentMagic.length,
        );
        final total = _readUint16(
          carrier,
          dataStart + _jpegSegmentMagic.length + 2,
        );
        onPayload?.call(
          index,
          total,
          Uint8List.fromList(
            carrier.sublist(
              dataStart + _jpegSegmentMagic.length + 4,
              segmentEnd,
            ),
          ),
        );
      }
      onSegment?.call(markerStart, segmentEnd, marker, isPayload);
      offset = segmentEnd;
      if (marker == 0xDA) return;
    }
  }

  static bool _isStandaloneJpegMarker(int marker) =>
      marker == 0x01 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7);

  static Uint8List _embedPdf(Uint8List carrier, Uint8List envelope) {
    final text = _stripPdfPayloadBlocks(latin1.decode(carrier));
    final encoded = base64Encode(envelope);
    final lines = <String>[];
    for (var i = 0; i < encoded.length; i += 76) {
      lines.add('%${encoded.substring(i, min(i + 76, encoded.length))}');
    }
    final block = '\n$_pdfBeginMarker\n${lines.join('\n')}\n$_pdfEndMarker\n';
    final eofIndex = text.lastIndexOf('%%EOF');
    final output = eofIndex == -1
        ? '$text$block'
        : '${text.substring(0, eofIndex)}$block${text.substring(eofIndex)}';
    return Uint8List.fromList(latin1.encode(output));
  }

  static _EnvelopeExtraction? _extractPdfEnvelope(Uint8List carrier) {
    final text = latin1.decode(carrier);
    final begin = text.lastIndexOf(_pdfBeginMarker);
    if (begin == -1) return null;
    final end = text.indexOf(_pdfEndMarker, begin);
    if (end == -1) {
      throw const FormatException('PDF embedded payload block is incomplete.');
    }
    final block = text.substring(begin + _pdfBeginMarker.length, end);
    final base64Text = block
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.startsWith('%') ? line.substring(1) : line)
        .join();
    return _EnvelopeExtraction(
      bytes: Uint8List.fromList(base64Decode(base64Text)),
      segmentCount: 1,
    );
  }

  static String _stripPdfPayloadBlocks(String text) {
    var result = text;
    while (true) {
      final begin = result.indexOf(_pdfBeginMarker);
      if (begin == -1) return result;
      final end = result.indexOf(_pdfEndMarker, begin);
      if (end == -1) return result;
      var removeStart = begin;
      if (removeStart > 0 && result.codeUnitAt(removeStart - 1) == 0x0A) {
        removeStart--;
      }
      var removeEnd = end + _pdfEndMarker.length;
      if (removeEnd < result.length && result.codeUnitAt(removeEnd) == 0x0D) {
        removeEnd++;
      }
      if (removeEnd < result.length && result.codeUnitAt(removeEnd) == 0x0A) {
        removeEnd++;
      }
      result = result.replaceRange(removeStart, removeEnd, '');
    }
  }

  static Uint8List _pngChunk(Uint8List type, Uint8List data) {
    final crcInput = Uint8List.fromList([...type, ...data]);
    return Uint8List.fromList([
      ..._uint32(data.length),
      ...type,
      ...data,
      ..._uint32(_crc32(crcInput)),
    ]);
  }

  static int _crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static Uint8List _aesCbcCrypt(
    Uint8List input,
    Uint8List key,
    Uint8List iv, {
    required bool encrypt,
  }) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(encrypt, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    final output = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += cipher.blockSize) {
      cipher.processBlock(input, offset, output, offset);
    }
    return output;
  }

  static Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padLength = blockSize - (data.length % blockSize);
    return Uint8List.fromList([
      ...data,
      ...List<int>.filled(padLength, padLength),
    ]);
  }

  static Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) {
      throw const FormatException('Decrypted payload is empty.');
    }
    final padLength = data.last;
    if (padLength == 0 || padLength > 16 || padLength > data.length) {
      throw const FormatException('Decrypted payload padding is invalid.');
    }
    for (var i = data.length - padLength; i < data.length; i++) {
      if (data[i] != padLength) {
        throw const FormatException('Decrypted payload padding is invalid.');
      }
    }
    return Uint8List.fromList(data.sublist(0, data.length - padLength));
  }

  static Uint8List _pbkdf2Sha256(
    Uint8List password,
    Uint8List salt,
    int iterations,
    int length,
  ) {
    const hashLength = 32;
    final blockCount = (length / hashLength).ceil();
    final output = BytesBuilder(copy: false);
    for (var block = 1; block <= blockCount; block++) {
      var u = _hmacSha256(
        password,
        Uint8List.fromList([...salt, ..._uint32(block)]),
      );
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = _hmacSha256(password, u);
        for (var j = 0; j < hashLength; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
    }
    return Uint8List.fromList(output.toBytes().sublist(0, length));
  }

  static Uint8List _hmacSha256(List<int> key, List<int> data) {
    return Uint8List.fromList(
      crypto.Hmac(crypto.sha256, key).convert(data).bytes,
    );
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _uint16(int value) {
    final data = ByteData(2)..setUint16(0, value);
    return data.buffer.asUint8List();
  }

  static Uint8List _uint32(int value) {
    final data = ByteData(4)..setUint32(0, value);
    return data.buffer.asUint8List();
  }

  static int _readUint16(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes, offset, offset + 2).getUint16(0);

  static int _readUint32(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);

  static bool _startsWith(Uint8List bytes, Uint8List prefix) =>
      bytes.length >= prefix.length && _startsWithAt(bytes, prefix, 0);

  static bool _startsWithAt(Uint8List bytes, Uint8List prefix, int offset) {
    if (offset + prefix.length > bytes.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[offset + i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var diff = 0;
    for (var i = 0; i < left.length; i++) {
      diff |= left[i] ^ right[i];
    }
    return diff == 0;
  }

  static bool _asciiEquals(List<int> bytes, String value) =>
      _listEquals(bytes, ascii.encode(value));
}

class _ParsedEnvelope {
  const _ParsedEnvelope({
    required this.iterations,
    required this.salt,
    required this.iv,
    required this.ciphertext,
    required this.mac,
    required this.authenticatedBytes,
  });

  final int iterations;
  final Uint8List salt;
  final Uint8List iv;
  final Uint8List ciphertext;
  final Uint8List mac;
  final Uint8List authenticatedBytes;
}

class _EnvelopeExtraction {
  const _EnvelopeExtraction({required this.bytes, required this.segmentCount});

  final Uint8List bytes;
  final int segmentCount;
}

class _JpegPayloadSegment {
  const _JpegPayloadSegment({
    required this.index,
    required this.total,
    required this.bytes,
  });

  final int index;
  final int total;
  final Uint8List bytes;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
