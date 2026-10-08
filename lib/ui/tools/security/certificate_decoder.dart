/// X.509 certificate decoder tool view.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';

class _Asn1Node {
  _Asn1Node(this.tag, this.content, this.children);
  final int tag;
  final Uint8List content;
  final List<_Asn1Node> children;
}

class _DerParser {
  _DerParser(this.bytes);
  final Uint8List bytes;
  int _pos = 0;

  _Asn1Node parse() => _parseNode();

  _Asn1Node _parseNode() {
    if (_pos + 2 > bytes.length) {
      throw const FormatException('Truncated DER data');
    }
    final tag = bytes[_pos++];
    var length = bytes[_pos++];
    if ((length & 0x80) != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4) {
        throw const FormatException('Unsupported DER length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[_pos++];
      }
    }
    final contentStart = _pos;
    final contentEnd = contentStart + length;
    if (contentEnd > bytes.length) {
      throw const FormatException('DER length exceeds data');
    }
    final content = Uint8List.sublistView(bytes, contentStart, contentEnd);
    final children = <_Asn1Node>[];
    final constructed = (tag & 0x20) != 0;
    if (constructed) {
      while (_pos < contentEnd) {
        children.add(_parseNode());
      }
    } else {
      _pos = contentEnd;
    }
    return _Asn1Node(tag, content, children);
  }
}

const _x509Oids = <String, String>{
  '2.5.4.3': 'CN',
  '2.5.4.4': 'SN',
  '2.5.4.5': 'serialNumber',
  '2.5.4.6': 'C',
  '2.5.4.7': 'L',
  '2.5.4.8': 'ST',
  '2.5.4.9': 'street',
  '2.5.4.10': 'O',
  '2.5.4.11': 'OU',
  '1.2.840.113549.1.9.1': 'email',
  '1.2.840.113549.1.1.1': 'RSA',
  '1.2.840.113549.1.1.5': 'sha1WithRSA',
  '1.2.840.113549.1.1.11': 'sha256WithRSA',
  '1.2.840.113549.1.1.12': 'sha384WithRSA',
  '1.2.840.113549.1.1.13': 'sha512WithRSA',
  '1.2.840.10045.2.1': 'EC',
  '1.2.840.10045.4.3.2': 'ecdsa-with-SHA256',
  '1.2.840.10045.4.3.3': 'ecdsa-with-SHA384',
  '1.2.840.10045.3.1.7': 'P-256',
  '1.3.132.0.34': 'P-384',
  '1.3.132.0.35': 'P-521',
  '2.5.29.14': 'Subject Key Identifier',
  '2.5.29.15': 'Key Usage',
  '2.5.29.17': 'Subject Alternative Name',
  '2.5.29.19': 'Basic Constraints',
  '2.5.29.31': 'CRL Distribution Points',
  '2.5.29.32': 'Certificate Policies',
  '2.5.29.35': 'Authority Key Identifier',
  '2.5.29.37': 'Extended Key Usage',
  '1.3.6.1.5.5.7.1.1': 'Authority Information Access',
};

String _decodeAsn1Oid(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  final parts = <int>[bytes[0] ~/ 40, bytes[0] % 40];
  var value = 0;
  for (var i = 1; i < bytes.length; i++) {
    value = (value << 7) | (bytes[i] & 0x7f);
    if ((bytes[i] & 0x80) == 0) {
      parts.add(value);
      value = 0;
    }
  }
  return parts.join('.');
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

String _hexColons(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');

String _decodeAsn1Name(_Asn1Node name) {
  final parts = <String>[];
  for (final rdn in name.children) {
    for (final atv in rdn.children) {
      if (atv.children.length >= 2) {
        final oid = _decodeAsn1Oid(atv.children[0].content);
        final key = _x509Oids[oid] ?? oid;
        final value = _decodeAsn1String(atv.children[1]);
        parts.add('$key=$value');
      }
    }
  }
  return parts.isEmpty ? '(none)' : parts.join(', ');
}

String _decodeAsn1String(_Asn1Node node) {
  try {
    return utf8.decode(node.content);
  } catch (_) {
    return latin1.decode(node.content);
  }
}

String _decodeAsn1Time(_Asn1Node node) {
  final raw = ascii.decode(node.content);
  try {
    if (node.tag == 0x17) {
      // UTCTime: YYMMDDHHMMSSZ
      final yy = int.parse(raw.substring(0, 2));
      final year = yy >= 50 ? 1900 + yy : 2000 + yy;
      return '$year-${raw.substring(2, 4)}-${raw.substring(4, 6)} '
          '${raw.substring(6, 8)}:${raw.substring(8, 10)}:${raw.substring(10, 12)} UTC';
    }
    // GeneralizedTime: YYYYMMDDHHMMSSZ
    return '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)} '
        '${raw.substring(8, 10)}:${raw.substring(10, 12)}:${raw.substring(12, 14)} UTC';
  } catch (_) {
    return raw;
  }
}

String _decodeX509Certificate(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'-----(BEGIN|END)[^-]*-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) {
    throw const FormatException('No certificate data found');
  }
  final der = base64.decode(cleaned);
  final root = _DerParser(Uint8List.fromList(der)).parse();
  if (root.children.length < 3) {
    throw const FormatException('Not a valid X.509 certificate structure');
  }
  final tbs = root.children[0];
  final signatureAlgorithm = root.children[1];

  var index = 0;
  var version = 1;
  if (tbs.children.isNotEmpty && (tbs.children[0].tag & 0xff) == 0xA0) {
    final versionNode = tbs.children[0].children.isNotEmpty
        ? tbs.children[0].children[0]
        : null;
    if (versionNode != null) {
      version = _bytesToBigInt(versionNode.content).toInt() + 1;
    }
    index = 1;
  }

  final serial = tbs.children[index++];
  index++; // inner signature algorithm (same as outer)
  final issuer = tbs.children[index++];
  final validity = tbs.children[index++];
  final subject = tbs.children[index++];
  final spki = tbs.children[index++];

  _Asn1Node? extensionsNode;
  for (var i = index; i < tbs.children.length; i++) {
    if ((tbs.children[i].tag & 0xff) == 0xA3) {
      extensionsNode = tbs.children[i];
    }
  }

  final sigOid = _decodeAsn1Oid(signatureAlgorithm.children.first.content);
  final notBefore = validity.children.isNotEmpty
      ? _decodeAsn1Time(validity.children[0])
      : '?';
  final notAfter = validity.children.length > 1
      ? _decodeAsn1Time(validity.children[1])
      : '?';

  final buffer = StringBuffer();
  buffer.writeln('Version: v$version');
  buffer.writeln('Serial Number: ${_hexColons(serial.content)}');
  buffer.writeln('Signature Algorithm: ${_x509Oids[sigOid] ?? sigOid}');
  buffer.writeln();
  buffer.writeln('Issuer: ${_decodeAsn1Name(issuer)}');
  buffer.writeln('Subject: ${_decodeAsn1Name(subject)}');
  buffer.writeln();
  buffer.writeln('Not Before: $notBefore');
  buffer.writeln('Not After:  $notAfter');
  buffer.writeln();
  buffer.writeln('Public Key: ${_describePublicKey(spki)}');

  if (extensionsNode != null && extensionsNode.children.isNotEmpty) {
    final extensionList = extensionsNode.children[0];
    final sans = <String>[];
    final names = <String>[];
    for (final ext in extensionList.children) {
      if (ext.children.isEmpty) continue;
      final oid = _decodeAsn1Oid(ext.children[0].content);
      names.add(_x509Oids[oid] ?? oid);
      if (oid == '2.5.29.17') {
        try {
          final inner = _DerParser(
            Uint8List.fromList(ext.children.last.content),
          ).parse();
          for (final generalName in inner.children) {
            if ((generalName.tag & 0x1f) == 2) {
              sans.add(ascii.decode(generalName.content));
            }
          }
        } catch (_) {
          // Ignore malformed SAN.
        }
      }
    }
    buffer.writeln();
    if (sans.isNotEmpty) {
      buffer.writeln('Subject Alternative Names: ${sans.join(', ')}');
    }
    if (names.isNotEmpty) {
      buffer.writeln('Extensions: ${names.join(', ')}');
    }
  }

  return buffer.toString().trimRight();
}

String _describePublicKey(_Asn1Node spki) {
  if (spki.children.length < 2) return 'Unknown';
  final algorithm = spki.children[0];
  final algOid = _decodeAsn1Oid(algorithm.children.first.content);
  if (algOid == '1.2.840.113549.1.1.1') {
    try {
      final bitString = spki.children[1];
      final inner = _DerParser(
        Uint8List.fromList(bitString.content.sublist(1)),
      ).parse();
      if (inner.children.isNotEmpty) {
        final modulus = inner.children[0].content;
        var bits = modulus.length * 8;
        if (modulus.isNotEmpty && modulus[0] == 0) bits -= 8;
        return 'RSA $bits-bit';
      }
    } catch (_) {
      // fall through
    }
    return 'RSA';
  }
  if (algOid == '1.2.840.10045.2.1') {
    if (algorithm.children.length > 1 && algorithm.children[1].tag == 0x06) {
      final curveOid = _decodeAsn1Oid(algorithm.children[1].content);
      return 'EC (${_x509Oids[curveOid] ?? curveOid})';
    }
    return 'EC';
  }
  return _x509Oids[algOid] ?? algOid;
}

class _CertificateDecoderView extends StatefulWidget {
  const _CertificateDecoderView();

  @override
  State<_CertificateDecoderView> createState() =>
      _CertificateDecoderViewState();
}

class _CertificateDecoderViewState extends State<_CertificateDecoderView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _output.clear());
      return;
    }
    try {
      _output.text = _decodeX509Certificate(text);
    } catch (error) {
      _output.text = 'Could not decode certificate: $error';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(
          label: 'Clipboard',
          onPressed: () async {
            final text = await readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = _sampleCertificate);
            _run();
          },
        ),
        ToolButton(
          label: 'Clear',
          onPressed: () {
            setState(() => _input.clear());
            _output.clear();
          },
        ),
      ],
      outputActions: [
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
      onInputChanged: (_) => _run(),
      inputPlaceholder:
          'Paste a PEM certificate (-----BEGIN CERTIFICATE-----)...',
      outputPlaceholder: 'Decoded certificate details...',
    );
  }
}

const _sampleCertificate = '''-----BEGIN CERTIFICATE-----
MIIB7DCCAZOgAwIBAgIUXz0eZsNS2P7FbZ0PzYs/goWMXTIwCgYIKoZIzj0EAwIw
ODEWMBQGA1UEAwwNRGV2VXRpbHMgRGVtbzERMA8GA1UECgwIRGV2VXRpbHMxCzAJ
BgNVBAYTAlVTMB4XDTI2MTAwODEwNDUxM1oXDTM2MTAwNTEwNDUxM1owODEWMBQG
A1UEAwwNRGV2VXRpbHMgRGVtbzERMA8GA1UECgwIRGV2VXRpbHMxCzAJBgNVBAYT
AlVTMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEaNiU5wrEOh/LS0sV04TNzKJA
Scar+ts5fPV3XIopvvklHyBbsQrn2g/sYTKdMgYRaG31a67lapoVy+k0dwhd6qN7
MHkwHQYDVR0OBBYEFC2hlqwJzlOPtDqMVQUBvcGhySjgMB8GA1UdIwQYMBaAFC2h
lqwJzlOPtDqMVQUBvcGhySjgMA8GA1UdEwEB/wQFMAMBAf8wJgYDVR0RBB8wHYIO
ZGV2dXRpbHMubG9jYWyCC2V4YW1wbGUuY29tMAoGCCqGSM49BAMCA0cAMEQCIDI+
K06p2IAFqR1XJi2JV8yPBGgKKEG4U2VjHuGL8FlYAiBVYwDaOdrvC8r9EuF0o0m5
OPB4kKiuf2pbeafouebiHg==
-----END CERTIFICATE-----''';

Widget buildCertificateDecoder() {
  return const _CertificateDecoderView();
}
