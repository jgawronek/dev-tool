/// Number Base Converter tool view.
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _NumberBaseConverterView extends StatefulWidget {
  const _NumberBaseConverterView();

  @override
  State<_NumberBaseConverterView> createState() =>
      _NumberBaseConverterViewState();
}

class _NumberBaseConverterViewState extends State<_NumberBaseConverterView> {
  final TextEditingController _input = TextEditingController(
    text: '0xDEADBEEF',
  );
  String _customBase = '36';
  String _inputBase = 'Auto';
  String _width = '32';
  String _interpretation = 'Unsigned';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  _ParsedNumber? _parseCurrent() {
    try {
      return _parseBigIntInput(
        _input.text,
        selectedBase: _inputBase,
        customBase: int.tryParse(_customBase) ?? 10,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parseCurrent();
    final customBase = int.tryParse(_customBase) ?? 36;
    final outputs = parsed == null
        ? const <_BaseConversionOutput>[]
        : _buildBaseOutputs(parsed.value, customBase);
    final widthBits = int.tryParse(_width);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNumberInput(context),
          const SizedBox(height: 10),
          if (parsed == null)
            Text(
              'Enter a valid value for the selected base.',
              style: errorToolTextStyle(context),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _numberPill(context, 'Detected', 'Base ${parsed.detectedBase}'),
                _numberPill(
                  context,
                  'Digits',
                  _digitCount(parsed.value).toString(),
                ),
                _numberPill(
                  context,
                  'Bits',
                  _bitLength(parsed.value).toString(),
                ),
                _numberPill(
                  context,
                  'Bytes',
                  _byteLength(parsed.value).toString(),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Expanded(
            child: ResizableSplit(
              horizontal: true,
              initialRatio: 0.62,
              minFirstExtent: 420,
              minSecondExtent: 300,
              first: Container(
                decoration: toolSurfaceDecoration(context),
                child: parsed == null
                    ? Center(
                        child: Text(
                          'Converted bases will appear here',
                          style: mutedToolTextStyle(context),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: outputs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _BaseOutputRow(output: outputs[index]);
                        },
                      ),
              ),
              second: Container(
                decoration: toolSurfaceDecoration(context),
                padding: const EdgeInsets.all(12),
                child: parsed == null
                    ? Center(
                        child: Text(
                          'Inspector details will appear here',
                          style: mutedToolTextStyle(context),
                        ),
                      )
                    : _NumberInspector(
                        value: parsed.value,
                        widthBits: widthBits,
                        interpretation: _interpretation,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberInput(BuildContext context) {
    final appColors = context.appColors;
    final baseOptions = const [
      'Auto',
      'Binary',
      'Octal',
      'Decimal',
      'Hex',
      'Custom',
    ];
    final customBaseOptions = List<String>.generate(
      35,
      (index) => (index + 2).toString(),
    );
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Input',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SmallDropdown(
                key: ValueKey('number-input-base-$_inputBase'),
                items: baseOptions,
                initialValue: _inputBase,
                width: 120,
                onChanged: (value) => setState(() => _inputBase = value),
              ),
              if (_inputBase == 'Custom')
                SmallDropdown(
                  key: ValueKey('number-custom-base-$_customBase'),
                  items: customBaseOptions,
                  initialValue: _customBase,
                  width: 82,
                  onChanged: (value) => setState(() => _customBase = value),
                ),
              SmallDropdown(
                key: ValueKey('number-width-$_width'),
                items: const ['Auto', '8', '16', '32', '64', '128', '256'],
                initialValue: _width,
                width: 104,
                onChanged: (value) => setState(() => _width = value),
              ),
              SmallDropdown(
                key: ValueKey('number-interpretation-$_interpretation'),
                items: const ['Unsigned', 'Signed'],
                initialValue: _interpretation,
                width: 118,
                onChanged: (value) => setState(() => _interpretation = value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              key: const ValueKey('number-base-input'),
              controller: _input,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: '0b1010, 0o755, 123456, 0xDEADBEEF',
                hintStyle: TextStyle(color: appColors.mutedText),
              ),
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: 'Menlo',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberPill(BuildContext context, String label, String value) {
    return Container(
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: mutedToolTextStyle(context, fontSize: 12)),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _BaseConversionOutput {
  const _BaseConversionOutput({
    required this.label,
    required this.base,
    required this.prefix,
    required this.value,
    required this.groupedValue,
  });

  final String label;
  final int base;
  final String prefix;
  final String value;
  final String groupedValue;
}

class _ParsedNumber {
  const _ParsedNumber({required this.value, required this.detectedBase});

  final BigInt value;
  final int detectedBase;
}

class _BaseOutputRow extends StatelessWidget {
  const _BaseOutputRow({required this.output});

  final _BaseConversionOutput output;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final prefixed = '${output.prefix}${output.value}';
    return Listener(
      onPointerDown: (event) {
        if ((event.buttons & kSecondaryMouseButton) != 0) {
          _showBaseValueMenu(context, event.position, output);
        }
      },
      child: Container(
        decoration: toolSurfaceDecoration(context, radius: 6),
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    output.label,
                    style: TextStyle(
                      color: appColors.editorText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'base ${output.base}',
                    style: mutedToolTextStyle(context, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      prefixed,
                      style: TextStyle(
                        color: appColors.editorText,
                        fontFamily: 'Menlo',
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  if (output.groupedValue != output.value) ...[
                    const SizedBox(height: 5),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        output.groupedValue,
                        style: TextStyle(
                          color: appColors.mutedText,
                          fontFamily: 'Menlo',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBaseValueMenu(
    BuildContext context,
    Offset position,
    _BaseConversionOutput output,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      color: context.appColors.panelElevated,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'value', child: Text('Copy value')),
        PopupMenuItem(value: 'prefix', child: Text('Copy with prefix')),
        PopupMenuItem(value: 'grouped', child: Text('Copy grouped')),
      ],
    );
    switch (selected) {
      case 'value':
        await Clipboard.setData(ClipboardData(text: output.value));
        break;
      case 'prefix':
        await Clipboard.setData(
          ClipboardData(text: '${output.prefix}${output.value}'),
        );
        break;
      case 'grouped':
        await Clipboard.setData(ClipboardData(text: output.groupedValue));
        break;
    }
  }
}

class _NumberInspector extends StatelessWidget {
  const _NumberInspector({
    required this.value,
    required this.widthBits,
    required this.interpretation,
  });

  final BigInt value;
  final int? widthBits;
  final String interpretation;

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = widthBits ?? _minimumByteAlignedBits(value);
    final unsigned = _unsignedWithinWidth(value, effectiveWidth);
    final signed = _signedWithinWidth(unsigned, effectiveWidth);
    final hex = unsigned.toRadixString(16).padLeft(effectiveWidth ~/ 4, '0');
    final bytes = _hexToBytePairs(hex);
    final ascii = _asciiPreview(unsigned, effectiveWidth);

    return ListView(
      children: [
        _inspectorRow(context, 'Mode', interpretation),
        _inspectorRow(context, 'Width', '$effectiveWidth bits'),
        _inspectorRow(context, 'Bit length', _bitLength(value).toString()),
        _inspectorRow(context, 'Byte length', _byteLength(value).toString()),
        _inspectorRow(context, 'Unsigned', unsigned.toString()),
        _inspectorRow(context, 'Signed', signed.toString()),
        _inspectorRow(context, 'Two\'s complement', '0x$hex'),
        _inspectorRow(context, 'Big endian bytes', bytes.join(' ')),
        _inspectorRow(context, 'Little endian bytes', bytes.reversed.join(' ')),
        _inspectorRow(
          context,
          'ASCII',
          ascii.isEmpty ? 'Not printable' : ascii,
        ),
      ],
    );
  }

  Widget _inspectorRow(BuildContext context, String label, String value) {
    final appColors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: appColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: value.length > 18 ? 'Menlo' : null,
                fontSize: value.length > 18 ? 11.5 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

_ParsedNumber _parseBigIntInput(
  String raw, {
  required String selectedBase,
  required int customBase,
}) {
  var text = raw.trim();
  if (text.isEmpty) throw const FormatException('Enter a number.');
  var negative = false;
  if (text.startsWith('-')) {
    negative = true;
    text = text.substring(1).trimLeft();
  } else if (text.startsWith('+')) {
    text = text.substring(1).trimLeft();
  }

  var base = switch (selectedBase) {
    'Binary' => 2,
    'Octal' => 8,
    'Decimal' => 10,
    'Hex' => 16,
    'Custom' => customBase,
    _ => 0,
  };

  final lower = text.toLowerCase();
  if (lower.startsWith('0b')) {
    base = base == 0 ? 2 : base;
    text = text.substring(2);
  } else if (lower.startsWith('0o')) {
    base = base == 0 ? 8 : base;
    text = text.substring(2);
  } else if (lower.startsWith('0x')) {
    base = base == 0 ? 16 : base;
    text = text.substring(2);
  } else if (base == 0) {
    base = RegExp(r'[a-z]', caseSensitive: false).hasMatch(text) ? 16 : 10;
  }

  if (base < 2 || base > 36) {
    throw const FormatException('Base must be between 2 and 36.');
  }

  final normalized = text.replaceAll(RegExp(r'[\s_]+'), '');
  if (normalized.isEmpty) throw const FormatException('Enter a number.');
  final validChars = '0123456789abcdefghijklmnopqrstuvwxyz'.substring(0, base);
  for (final codeUnit in normalized.toLowerCase().codeUnits) {
    if (!validChars.contains(String.fromCharCode(codeUnit))) {
      throw FormatException('Invalid digit for base $base.');
    }
  }

  var value = BigInt.parse(normalized, radix: base);
  if (negative) value = -value;
  return _ParsedNumber(value: value, detectedBase: base);
}

List<_BaseConversionOutput> _buildBaseOutputs(BigInt value, int customBase) {
  final rows = <_BaseConversionOutput>[
    _baseOutput('Binary', 2, '0b', value),
    _baseOutput('Octal', 8, '0o', value),
    _baseOutput('Decimal', 10, '', value),
    _baseOutput('Hex', 16, '0x', value),
    _baseOutput('Base 32', 32, '', value),
    _baseOutput('Base 36', 36, '', value),
  ];
  if (!const {2, 8, 10, 16, 32, 36}.contains(customBase)) {
    rows.add(_baseOutput('Custom', customBase, '', value));
  }
  return rows;
}

_BaseConversionOutput _baseOutput(
  String label,
  int base,
  String prefix,
  BigInt value,
) {
  final raw = value.toRadixString(base).toUpperCase();
  return _BaseConversionOutput(
    label: label,
    base: base,
    prefix: value.isNegative && prefix.isNotEmpty ? '-$prefix' : prefix,
    value: value.isNegative && prefix.isNotEmpty ? raw.substring(1) : raw,
    groupedValue: _groupBaseValue(raw, base),
  );
}

String _groupBaseValue(String value, int base) {
  final negative = value.startsWith('-');
  final body = negative ? value.substring(1) : value;
  final size = switch (base) {
    2 => 4,
    8 => 3,
    10 => 3,
    16 => 2,
    _ => 4,
  };
  final groups = <String>[];
  for (var index = body.length; index > 0; index -= size) {
    final start = max(0, index - size);
    groups.insert(0, body.substring(start, index));
  }
  final grouped = groups.join(' ');
  return negative ? '-$grouped' : grouped;
}

int _bitLength(BigInt value) {
  if (value == BigInt.zero) return 0;
  return value.abs().bitLength;
}

int _byteLength(BigInt value) {
  final bits = _bitLength(value);
  return bits == 0 ? 0 : ((bits + 7) ~/ 8);
}

int _digitCount(BigInt value) {
  final text = value.abs().toString();
  return text == '0' ? 1 : text.length;
}

int _minimumByteAlignedBits(BigInt value) {
  final bits = max(1, _bitLength(value));
  return ((bits + 7) ~/ 8) * 8;
}

BigInt _unsignedWithinWidth(BigInt value, int widthBits) {
  final modulus = BigInt.one << widthBits;
  final remainder = value % modulus;
  return remainder.isNegative ? remainder + modulus : remainder;
}

BigInt _signedWithinWidth(BigInt unsigned, int widthBits) {
  final signBit = BigInt.one << (widthBits - 1);
  final modulus = BigInt.one << widthBits;
  return unsigned >= signBit ? unsigned - modulus : unsigned;
}

List<String> _hexToBytePairs(String hex) {
  final padded = hex.length.isOdd ? '0$hex' : hex;
  final bytes = <String>[];
  for (var index = 0; index < padded.length; index += 2) {
    bytes.add(padded.substring(index, index + 2).toUpperCase());
  }
  return bytes;
}

String _asciiPreview(BigInt value, int widthBits) {
  final unsigned = _unsignedWithinWidth(value, widthBits);
  final hex = unsigned.toRadixString(16).padLeft(widthBits ~/ 4, '0');
  final buffer = StringBuffer();
  for (final pair in _hexToBytePairs(hex)) {
    final byte = int.parse(pair, radix: 16);
    if (byte < 32 || byte > 126) return '';
    buffer.writeCharCode(byte);
  }
  return buffer.toString();
}

Widget buildNumberBaseConverter() {
  return const _NumberBaseConverterView();
}
