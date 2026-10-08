/// ASN.1 (DER/BER) and generic TLV structure decoding.
///
/// The X.509 tool carries a minimal DER reader for its own use; this is the
/// generalised version: full tag classes, high-tag-number forms, indefinite
/// lengths, recursive descent, and interpretation of the common universal
/// types. It also reads bare BER-TLV as used by ISO 7816 / EMV / NFC payloads,
/// which is not ASN.1 at all but shares the tag-length-value shape.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The tag classes defined by X.690.
enum Asn1Class {
  universal('Universal'),
  application('Application'),
  contextSpecific('Context-specific'),
  private('Private');

  const Asn1Class(this.label);

  final String label;
}

/// Universal tag numbers with a defined meaning.
enum Asn1UniversalTag {
  boolean(1, 'BOOLEAN'),
  integer(2, 'INTEGER'),
  bitString(3, 'BIT STRING'),
  octetString(4, 'OCTET STRING'),
  nullValue(5, 'NULL'),
  objectIdentifier(6, 'OBJECT IDENTIFIER'),
  utf8String(12, 'UTF8String'),
  sequence(16, 'SEQUENCE'),
  set(17, 'SET'),
  printableString(19, 'PrintableString'),
  t61String(20, 'T61String'),
  ia5String(22, 'IA5String'),
  utcTime(23, 'UTCTime'),
  generalizedTime(24, 'GeneralizedTime'),
  visibleString(26, 'VisibleString'),
  universalString(28, 'UniversalString'),
  bmpString(30, 'BMPString');

  const Asn1UniversalTag(this.number, this.label);

  final int number;
  final String label;
}

/// One decoded tag-length-value node.
class Asn1Node {
  const Asn1Node({
    required this.tagClass,
    required this.tagNumber,
    required this.constructed,
    required this.content,
    required this.offset,
    required this.headerLength,
    required this.indefinite,
    this.children = const [],
    this.truncated = false,
  });

  final Asn1Class tagClass;
  final int tagNumber;
  final bool constructed;

  /// The value octets.
  final List<int> content;

  /// Byte offset where this node starts.
  final int offset;

  /// Bytes consumed by the identifier and length octets, excluding the value.
  final int headerLength;

  /// True when the length used the BER indefinite form.
  final bool indefinite;

  final List<Asn1Node> children;

  /// True when some content could not be decoded as child nodes.
  final bool truncated;

  /// The identifier octet, which is what generic TLV traces show.
  int get identifierByte => tagNumber <= 0xFF ? tagNumber : 0;

  int get totalLength => headerLength + content.length;

  /// Universal type name, or null for non-universal tags.
  String? get universalLabel {
    if (tagClass != Asn1Class.universal) return null;
    for (final tag in Asn1UniversalTag.values) {
      if (tag.number == tagNumber) return tag.label;
    }
    return null;
  }

  /// The identifier octet in hex, which is what protocol traces show.
  String get identifierHex => tagNumber < 31 && tagNumber == tagNumber
      ? _hex([_tagByte])
      : _hex([_tagByte]);

  int get _tagByte {
    var byte = tagClass.index << 6;
    if (constructed) byte |= 0x20;
    // High-tag-number form uses 0x1f in the low five bits.
    byte |= tagNumber > 30 ? 0x1f : tagNumber;
    return byte;
  }

  /// A human-readable rendering of the value.
  String get value => decodeAsn1Value(this);

  /// One-line summary used by the tree renderer.
  String get summary {
    final label = universalLabel;
    final head = label ?? '${tagClass.label}[$tagNumber]';
    if (!constructed && children.isEmpty) {
      final decoded = decodeAsn1Value(this);
      return decoded.length > 60 ? '${decoded.substring(0, 57)}...' : decoded;
    }
    return head;
  }
}

/// Result of a decode run.
class Asn1Outcome {
  const Asn1Outcome.success({
    required this.roots,
    required this.totalBytes,
    required this.nodeCount,
    required this.mode,
    this.warning,
  }) : error = null;

  const Asn1Outcome.failure(this.error)
    : roots = const [],
      totalBytes = 0,
      nodeCount = 0,
      mode = Asn1DecodeMode.der,
      warning = null;

  final List<Asn1Node> roots;
  final int totalBytes;
  final int nodeCount;
  final Asn1DecodeMode mode;
  final String? error;

  /// Set when parsing stopped early but usable nodes were recovered.
  final String? warning;
}

/// How to interpret the input.
enum Asn1DecodeMode {
  der('ASN.1 (DER)'),
  berTlv('Generic TLV (BER-TLV)');

  const Asn1DecodeMode(this.label);

  final String label;
}

/// Parses [bytes] as ASN.1 or generic TLV.
Asn1Outcome decodeAsn1(
  List<int> bytes, {
  Asn1DecodeMode mode = Asn1DecodeMode.der,
}) {
  if (bytes.isEmpty) {
    return const Asn1Outcome.failure('No data to decode.');
  }
  final data = Uint8List.fromList(bytes);
  final roots = <Asn1Node>[];
  var offset = 0;
  var nodeCount = 0;
  String? warning;

  while (offset < data.length) {
    try {
      final node = _parseNode(
        data,
        offset,
        depth: 0,
        highTagNumbers: mode != Asn1DecodeMode.berTlv,
      );
      roots.add(node);
      offset += node.totalLength;
      nodeCount += _countNodes(node);
    } on FormatException catch (error) {
      // Keep whatever parsed cleanly so a partially valid blob still shows
      // something useful, but say plainly that it was truncated.
      if (roots.isEmpty) {
        return Asn1Outcome.failure(error.message);
      }
      warning = 'Stopped after ${roots.length} node(s) at offset $offset: '
          '${error.message}';
      break;
    }
  }

  if (roots.isEmpty) {
    return const Asn1Outcome.failure('Nothing could be parsed.');
  }
  return Asn1Outcome.success(
    roots: roots,
    totalBytes: data.length,
    nodeCount: nodeCount,
    mode: mode,
    warning: warning,
  );
}

const _maxDepth = 64;

Asn1Node _parseNode(
  Uint8List bytes,
  int start, {
  required int depth,
  required bool highTagNumbers,
}) {
  if (depth > _maxDepth) {
    throw const FormatException('Nesting deeper than $_maxDepth levels');
  }
  if (start + 2 > bytes.length) {
    throw const FormatException('Truncated: no room for tag and length');
  }

  var offset = start;
  final identifier = bytes[offset++];
  final tagClass = Asn1Class.values[(identifier >> 6) & 0x03];
  // ISO 7816-4 marks constructed values with b6, but EMV tags its templates
  // (0x5F, 0x6F, 0x70, 0x9F, ...) with b6 clear even though they hold nested
  // TLV. In generic TLV mode a low-nibble of 0xF therefore means template.
  final constructed = (identifier & 0x20) != 0 ||
      (!highTagNumbers && (identifier & 0x0f) == 0x0f);
  // Generic TLV identifies elements by the whole byte (ISO 7816-4), so the
  // class and tag bits stay packed together there.
  var tagNumber = highTagNumbers ? identifier & 0x1f : identifier;

  // High-tag-number form: low five bits all set, real number follows.
  if (highTagNumbers && tagNumber == 0x1f) {
    tagNumber = 0;
    var byte = 0;
    do {
      if (offset >= bytes.length) {
        throw const FormatException('Truncated high-tag-number form');
      }
      byte = bytes[offset++];
      tagNumber = (tagNumber << 7) | (byte & 0x7f);
      if (tagNumber > 0xffffff) {
        throw const FormatException('Tag number too large');
      }
    } while ((byte & 0x80) != 0);
  }

  if (offset >= bytes.length) {
    throw const FormatException('Truncated: no length octet');
  }
  var lengthByte = bytes[offset++];
  var length = 0;
  var indefinite = false;
  if ((lengthByte & 0x80) == 0) {
    length = lengthByte;
  } else if (lengthByte == 0x80) {
    // BER indefinite length: terminated by two zero octets.
    indefinite = true;
    length = -1;
  } else {
    final count = lengthByte & 0x7f;
    if (count > 4) {
      throw const FormatException('Length field longer than 4 bytes');
    }
    if (offset + count > bytes.length) {
      throw const FormatException('Truncated long-form length');
    }
    for (var i = 0; i < count; i++) {
      length = (length << 8) | bytes[offset++];
    }
    if (length < 0) {
      throw const FormatException('Length overflows 32 bits');
    }
  }

  final contentStart = offset;
  int contentEnd;
  if (indefinite) {
    contentEnd = _findIndefiniteEnd(bytes, contentStart);
  } else {
    contentEnd = contentStart + length;
    if (contentEnd > bytes.length) {
      throw FormatException('Length $length runs past the end of the data');
    }
  }

  final content = Uint8List.sublistView(bytes, contentStart, contentEnd);
  final children = <Asn1Node>[];
  var truncated = false;
  if (constructed) {
    var childOffset = contentStart;
    while (indefinite ? childOffset < contentEnd - 1 : childOffset < contentEnd) {
      try {
        final child = _parseNode(
          bytes,
          childOffset,
          depth: depth + 1,
          highTagNumbers: highTagNumbers,
        );
        children.add(child);
        childOffset += child.totalLength;
      } on FormatException {
        // Keep the children that did parse and flag the rest as unreadable.
        truncated = true;
        break;
      }
      if (indefinite &&
          childOffset + 1 < contentEnd &&
          bytes[childOffset] == 0x00 &&
          bytes[childOffset + 1] == 0x00) {
        break;
      }
    }
  }

  return Asn1Node(
    tagClass: tagClass,
    tagNumber: tagNumber,
    constructed: constructed,
    content: content,
    offset: start,
    headerLength: contentStart - start,
    indefinite: indefinite,
    children: children,
    truncated: truncated,
  );
}

/// Walks forward to the end-of-contents octets for an indefinite length.
int _findIndefiniteEnd(Uint8List bytes, int start) {
  for (var i = start; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0x00 && bytes[i + 1] == 0x00) {
      return i + 2;
    }
  }
  throw const FormatException('Unterminated indefinite length');
}

int _countNodes(Asn1Node node) =>
    1 + node.children.fold(0, (sum, child) => sum + _countNodes(child));

/// Interprets the value octets according to the node's universal tag.
String decodeAsn1Value(Asn1Node node) {
  final label = node.universalLabel;
  final content = node.content;
  if (content.isEmpty && label != null) return '(empty)';

  switch (label) {
    case 'BOOLEAN':
      return content.first == 0 ? 'FALSE' : 'TRUE';
    case 'INTEGER':
      return _decodeInteger(content);
    case 'BIT STRING':
      if (content.isEmpty) return '(empty)';
      final unused = content.first;
      final bits = _hex(content.sublist(1));
      return '$bits ($unused unused bit(s))';
    case 'OCTET STRING':
      return _tryText(content) ?? _hex(content);
    case 'NULL':
      return '(no value)';
    case 'OBJECT IDENTIFIER':
      return decodeOid(content);
    case 'UTF8String':
    case 'PrintableString':
    case 'IA5String':
    case 'VisibleString':
    case 'T61String':
    case 'UniversalString':
    case 'BMPString':
      return _tryText(content) ?? _hex(content);
    case 'UTCTime':
      final text = _tryText(content);
      final parsed = text == null ? null : _parseAsn1Time('UTCTime', text);
      return parsed == null ? (text ?? _hex(content)) : '$text  ($parsed)';
    case 'GeneralizedTime':
      final text = _tryText(content);
      final parsed = text == null ? null : _parseAsn1Time('GeneralizedTime', text);
      return parsed == null ? (text ?? _hex(content)) : '$text  ($parsed)';
    default:
      if (node.constructed) return '${node.children.length} element(s)';
      return _tryText(content) ?? _hex(content);
  }
}

/// Signed two's-complement INTEGER, so a negative serial number is readable.
String _decodeInteger(List<int> content) {
  if (content.isEmpty) return '(empty)';
  var value = BigInt.zero;
  final negative = (content.first & 0x80) != 0;
  for (final byte in content) {
    value = (value << 8) | BigInt.from(byte);
  }
  if (negative) {
    value -= BigInt.one << (8 * content.length);
  }
  return value.toString();
}

/// Decodes an OBJECT IDENTIFIER to dotted form.
String decodeOid(List<int> content) {
  if (content.isEmpty) return '';
  final parts = <String>['${content[0] ~/ 40}', '${content[0] % 40}'];
  var value = BigInt.zero;
  var started = false;
  for (final byte in content.skip(1)) {
    value = (value << 7) | BigInt.from(byte & 0x7f);
    started = true;
    if ((byte & 0x80) == 0) {
      parts.add(value.toString());
      value = BigInt.zero;
      started = false;
    }
  }
  if (started) parts.add(value.toString());
  return parts.join('.');
}

/// Parses UTCTime and GeneralizedTime, returning an ISO 8601 UTC rendering.
/// Returns null when the text does not look like a valid ASN.1 time.
String? _parseAsn1Time(String label, String text) {
  // Peel off the trailing zone designator, if any.
  var digits = text;
  var zoneMinutes = 0;
  var zoneLabel = ' UTC';
  if (digits.endsWith('Z') || digits.endsWith('z')) {
    digits = digits.substring(0, digits.length - 1);
  } else {
    final offset = RegExp(r'([+-])(\d{2})(\d{2})$').firstMatch(digits);
    if (offset != null) {
      final hours = int.parse(offset.group(2)!);
      final minutes = int.parse(offset.group(3)!);
      zoneMinutes = (offset.group(1) == '-' ? -1 : 1) * (hours * 60 + minutes);
      zoneLabel = ' ${offset.group(1)}${offset.group(2)}:${offset.group(3)}';
      digits = digits.substring(0, digits.length - 6);
    }
  }

  final fraction = digits.contains('.')
      ? digits.substring(digits.indexOf('.') + 1)
      : '';
  digits = digits.contains('.')
      ? digits.substring(0, digits.indexOf('.'))
      : digits;

  try {
    final String year;
    final String rest;
    if (label == 'UTCTime') {
      if (digits.length != 10 && digits.length != 12) return null;
      // X.690: 50-99 means 19xx, 00-49 means 20xx.
      final twoDigit = digits.substring(0, 2);
      final prefix = int.parse(twoDigit) >= 50 ? '19' : '20';
      year = '$prefix$twoDigit';
      rest = digits.length == 12 ? digits.substring(2) : '${digits.substring(2)}00';
    } else {
      if (digits.length != 14) return null;
      year = digits.substring(0, 4);
      rest = digits.substring(4);
    }

    final local = '$year-${rest.substring(0, 2)}-${rest.substring(2, 4)}T'
        '${rest.substring(4, 6)}:${rest.substring(6, 8)}:${rest.substring(8, 10)}'
        '${fraction.isEmpty ? '' : '.$fraction'}';
    final utc = DateTime.parse(local).subtract(
      Duration(minutes: zoneMinutes),
    );
    final iso = fraction.isEmpty
        ? utc.toIso8601String().substring(0, 19)
        : utc.toIso8601String();
    return '$iso$zoneLabel';
  } catch (_) {
    return null;
  }
}

String? _tryText(List<int> bytes) {
  try {
    final text = utf8.decode(bytes);
    // Control characters mean this is binary, not text.
    for (final unit in text.codeUnits) {
      if (unit < 0x09 || (unit > 0x0d && unit < 0x20)) return null;
    }
    return text;
  } catch (_) {
    return null;
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

/// Renders the tree as indented text for the output pane.
String renderAsn1Report(Asn1Outcome outcome) {
  if (outcome.error != null) return outcome.error!;
  final buffer = StringBuffer()
    ..writeln('Parsed ${outcome.mode.label}')
    ..writeln('${outcome.totalBytes} byte(s), ${outcome.nodeCount} node(s)');
  if (outcome.warning != null) {
    buffer
      ..writeln()
      ..writeln('Warning: ${outcome.warning}');
  }
  for (final root in outcome.roots) {
    buffer
      ..writeln()
      ..writeln(_renderNode(root, 0, outcome.mode));
  }
  return buffer.toString().trimRight();
}

String _renderNode(Asn1Node node, int depth, Asn1DecodeMode mode) {
  final indent = '  ' * depth;
  final offset = node.offset.toRadixString(16).padLeft(4, '0');
  // Generic TLV is conventionally reported by raw tag byte, where ASN.1 uses
  // the class/type-name split.
  final tag = mode == Asn1DecodeMode.berTlv
      ? 'Tag 0x${node.identifierByte.toRadixString(16).padLeft(2, '0')}'
      : node.universalLabel ?? '${node.tagClass.label}[${node.tagNumber}]';
  final marker = node.constructed ? 'SEQUENCE OF' : '';
  final buffer = StringBuffer()
    ..writeln('$indent$offset  $tag  $marker'.trimRight());
  final value = node.value;
  if (!node.constructed || value.isNotEmpty && !value.endsWith('element(s)')) {
    if (value.isNotEmpty) {
      final indented = value.split('\n').map((l) => '$indent    $l').join('\n');
      buffer.writeln(indented);
    }
  }
  for (final child in node.children) {
    buffer.writeln(_renderNode(child, depth + 1, mode));
  }
  return buffer.toString().trimRight();
}
