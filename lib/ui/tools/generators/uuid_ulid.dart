/// UUID/ULID generate/decode tool view.
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _UuidUlidView extends StatefulWidget {
  const _UuidUlidView();

  @override
  State<_UuidUlidView> createState() => _UuidUlidViewState();
}

class _UuidUlidViewState extends State<_UuidUlidView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _standard = TextEditingController();
  final TextEditingController _raw = TextEditingController();
  final TextEditingController _version = TextEditingController();
  final TextEditingController _variant = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final TextEditingController _clock = TextEditingController();
  final TextEditingController _node = TextEditingController();
  final TextEditingController _count = TextEditingController(text: '1');
  final TextEditingController _generated = TextEditingController();
  String _type = 'UUID v4';
  bool _lowercase = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _standard.dispose();
    _raw.dispose();
    _version.dispose();
    _variant.dispose();
    _time.dispose();
    _clock.dispose();
    _node.dispose();
    _count.dispose();
    _generated.dispose();
    super.dispose();
  }

  void _decode() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _clearDecodedFields();
      setState(() => _error = null);
      return;
    }

    final uuid = _normalizeUuid(text);
    if (uuid != null) {
      _applyUuid(uuid);
      setState(() => _error = null);
      return;
    }

    final ulid = _normalizeUlid(text);
    if (ulid != null) {
      _applyUlid(ulid);
      setState(() => _error = null);
      return;
    }

    _clearDecodedFields();
    setState(() => _error = 'Not a valid UUID or ULID.');
  }

  void _clearDecodedFields() {
    _standard.clear();
    _raw.clear();
    _version.clear();
    _variant.clear();
    _time.clear();
    _clock.clear();
    _node.clear();
  }

  String? _normalizeUuid(String text) {
    final compact = text.replaceAll('-', '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(compact)) return null;
    return '${compact.substring(0, 8)}-${compact.substring(8, 12)}-'
        '${compact.substring(12, 16)}-${compact.substring(16, 20)}-'
        '${compact.substring(20)}';
  }

  String? _normalizeUlid(String text) {
    final normalized = text.trim().toUpperCase();
    if (RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$').hasMatch(normalized)) {
      return normalized;
    }
    return null;
  }

  void _applyUuid(String uuid) {
    final raw = uuid.replaceAll('-', '');
    final version = raw[12];
    final variantNibble = int.parse(raw[16], radix: 16);
    _standard.text = uuid;
    _raw.text = raw;
    _version.text = 'UUID v$version';
    _variant.text = variantNibble >= 8 && variantNibble <= 11
        ? 'RFC 4122'
        : 'Reserved';

    if (version == '1') {
      final timeLow = int.parse(raw.substring(0, 8), radix: 16);
      final timeMid = int.parse(raw.substring(8, 12), radix: 16);
      final timeHigh = int.parse(raw.substring(12, 16), radix: 16) & 0x0fff;
      final timestamp = (timeHigh << 48) | (timeMid << 32) | timeLow;
      const uuidEpochOffset = 0x01B21DD213814000;
      final microsSinceUnix = (timestamp - uuidEpochOffset) ~/ 10;
      _time.text = DateTime.fromMicrosecondsSinceEpoch(
        microsSinceUnix,
        isUtc: true,
      ).toIso8601String();
      final clockSequence =
          int.parse(raw.substring(16, 20), radix: 16) & 0x3fff;
      _clock.text = clockSequence.toRadixString(16).padLeft(4, '0');
      _node.text = raw
          .substring(20)
          .replaceAllMapped(RegExp(r'.{2}'), (match) => '${match.group(0)}:')
          .replaceFirst(RegExp(r':$'), '');
    } else {
      _time.text = version == '7' ? 'Embedded timestamp' : 'Not time based';
      _clock.clear();
      _node.clear();
    }
  }

  void _applyUlid(String ulid) {
    _standard.text = ulid;
    _raw.text = ulid;
    _version.text = 'ULID';
    _variant.text = 'Crockford Base32';
    final timestamp = _decodeUlidTimestamp(ulid);
    _time.text = timestamp == null
        ? ''
        : DateTime.fromMillisecondsSinceEpoch(
            timestamp,
            isUtc: true,
          ).toIso8601String();
    _clock.clear();
    _node.clear();
  }

  int? _decodeUlidTimestamp(String ulid) {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    var value = 0;
    for (final codeUnit in ulid.substring(0, 10).codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(codeUnit));
      if (index < 0) return null;
      value = value * 32 + index;
    }
    return value;
  }

  String _uuidV4() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytesToHex(bytes, lower: true);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _uuidV1() {
    final rand = Random.secure();
    final now = DateTime.now().toUtc();
    const uuidEpochOffset = 0x01B21DD213814000;
    final timestamp = now.microsecondsSinceEpoch * 10 + uuidEpochOffset;
    final timeLow = timestamp & 0xffffffff;
    final timeMid = (timestamp >> 32) & 0xffff;
    final timeHigh = ((timestamp >> 48) & 0x0fff) | 0x1000;
    final clockSeq = rand.nextInt(0x4000);
    final clockHi = ((clockSeq >> 8) & 0x3f) | 0x80;
    final clockLow = clockSeq & 0xff;
    final node = List<int>.generate(6, (_) => rand.nextInt(256));
    node[0] = node[0] | 0x01;
    final nodeHex = bytesToHex(node, lower: true);
    return '${timeLow.toRadixString(16).padLeft(8, '0')}-'
        '${timeMid.toRadixString(16).padLeft(4, '0')}-'
        '${timeHigh.toRadixString(16).padLeft(4, '0')}-'
        '${clockHi.toRadixString(16).padLeft(2, '0')}'
        '${clockLow.toRadixString(16).padLeft(2, '0')}-$nodeHex';
  }

  String _ulid() {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final rand = Random.secure();
    var timestamp = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    final timeChars = List<String>.filled(10, '0');
    for (var i = 9; i >= 0; i--) {
      timeChars[i] = alphabet[timestamp & 0x1f];
      timestamp >>= 5;
    }
    buffer.writeAll(timeChars);
    for (var i = 0; i < 16; i++) {
      buffer.write(alphabet[rand.nextInt(32)]);
    }
    return buffer.toString();
  }

  void _generate() {
    final count = (int.tryParse(_count.text) ?? 1).clamp(1, 100).toInt();
    final values = <String>[];
    for (var i = 0; i < count; i++) {
      switch (_type) {
        case 'UUID v1':
          values.add(_uuidV1());
          break;
        case 'ULID':
          values.add(_ulid());
          break;
        default:
          values.add(_uuidV4());
      }
    }
    var output = values.join('\n');
    if (!_lowercase && !_type.startsWith('ULID')) {
      output = output.toUpperCase();
    } else if (_lowercase) {
      output = output.toLowerCase();
    }
    setState(() => _generated.text = output);
  }

  Future<void> _copyGenerated() async {
    await Clipboard.setData(ClipboardData(text: _generated.text));
  }

  void _clearGenerated() {
    setState(() => _generated.clear());
  }

  @override
  Widget build(BuildContext context) {
    return ResizableSplit(
      horizontal: true,
      initialRatio: 0.5,
      minFirstExtent: 360,
      minSecondExtent: 380,
      first: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditorPane(
                label: 'Input',
                actions: [
                  ToolButton(
                    label: 'Clipboard',
                    onPressed: () async {
                      final text = await readClipboardText();
                      setState(() => _input.text = text);
                      _decode();
                    },
                  ),
                  ToolButton(
                    label: 'Sample',
                    onPressed: () {
                      setState(() => _input.text = _uuidV4());
                      _decode();
                    },
                  ),
                  ToolButton(
                    label: 'Clear',
                    onPressed: () {
                      setState(() => _input.clear());
                      _decode();
                    },
                  ),
                ],
                controller: _input,
                onChanged: (_) => _decode(),
                placeholder: '00000000-0000-0000-0000-000000000000',
                expand: false,
                fixedHeight: 104,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: errorToolTextStyle(context)),
              ],
              const SizedBox(height: 12),
              _IdDetailsPanel(
                rows: [
                  _IdDetailRowData('Standard', _standard.text),
                  _IdDetailRowData('Raw', _raw.text),
                  _IdDetailRowData('Type', _version.text),
                  _IdDetailRowData('Variant', _variant.text),
                  _IdDetailRowData('Time', _time.text),
                  _IdDetailRowData('Clock ID', _clock.text),
                  _IdDetailRowData('Node', _node.text),
                ],
              ),
            ],
          ),
        ),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: toolSurfaceDecoration(context, radius: 8),
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Generate',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SmallDropdown(
                  items: const ['UUID v4', 'UUID v1', 'ULID'],
                  initialValue: _type,
                  width: 128,
                  onChanged: (value) => setState(() => _type = value),
                ),
                InlineTextField(width: 56, hintText: '1', controller: _count),
                ToolButton(label: 'Generate', onPressed: _generate),
                Checkbox(
                  value: _lowercase,
                  onChanged: (value) =>
                      setState(() => _lowercase = value ?? false),
                ),
                const Text('lowercase'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Generated IDs',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              ToolButton(label: 'Reset output', onPressed: _clearGenerated),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EditorPane(
              label: '',
              actions: const [],
              controller: _generated,
              readOnly: true,
              placeholder: 'Generated IDs...',
              copyAction: _copyGenerated,
              showHeader: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdDetailRowData {
  const _IdDetailRowData(this.label, this.value);

  final String label;
  final String value;
}

class _IdDetailsPanel extends StatelessWidget {
  const _IdDetailsPanel({required this.rows});

  final List<_IdDetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final hasData = rows.any((row) => row.value.isNotEmpty);
    return Container(
      width: double.infinity,
      decoration: toolSurfaceDecoration(context, radius: 8),
      padding: const EdgeInsets.all(12),
      child: hasData
          ? Column(
              children: [
                for (final row in rows)
                  _IdDetailRow(label: row.label, value: row.value),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Paste a UUID or ULID to decode it.',
                  style: TextStyle(color: appColors.mutedText),
                ),
              ),
            ),
    );
  }
}

class _IdDetailRow extends StatelessWidget {
  const _IdDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                color: appColors.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: 'Menlo',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildUuidUlid() {
  return const _UuidUlidView();
}
