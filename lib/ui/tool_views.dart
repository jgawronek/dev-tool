import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/digests/md2.dart';
import 'package:pointycastle/digests/md4.dart';
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha224.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha384.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/digests/ripemd128.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/ripemd320.dart';
import 'package:pointycastle/digests/tiger.dart';
import 'package:pointycastle/digests/whirlpool.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/block/modes/cfb.dart';
import 'package:pointycastle/block/modes/ofb.dart';
import 'package:pointycastle/stream/ctr.dart';
import 'package:pointycastle/stream/salsa20.dart';
import 'package:pointycastle/stream/chacha20.dart';
import 'package:pointycastle/stream/rc4_engine.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/block/rc2_engine.dart';
import 'package:pointycastle/api.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

import '../data/mime_types.dart';
import '../services/local_llm_service.dart';
import 'widgets.dart';

Widget buildSplitEditors({
  String inputLabel = 'Input',
  String outputLabel = 'Output',
  List<Widget> inputActions = const [],
  List<Widget> outputActions = const [],
  bool outputReadOnly = true,
  String inputPlaceholder = 'Enter text...',
  String outputPlaceholder = 'Output...',
  TextEditingController? inputController,
  TextEditingController? outputController,
  ValueChanged<String>? onInputChanged,
  bool horizontal = false,
  VoidCallback? onInputSubmit,
}) {
  final input = EditorPane(
    label: inputLabel,
    actions: inputActions,
    placeholder: inputPlaceholder,
    controller: inputController,
    onChanged: onInputChanged,
    onSubmit: onInputSubmit,
  );
  final output = EditorPane(
    label: outputLabel,
    actions: outputActions,
    placeholder: outputPlaceholder,
    readOnly: outputReadOnly,
    controller: outputController,
  );
  if (horizontal) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: input),
        const SizedBox(width: 16),
        Expanded(child: output),
      ],
    );
  }
  return Column(
    children: [
      Expanded(child: input),
      const SizedBox(height: 16),
      Expanded(child: output),
    ],
  );
}

Widget buildVerticalEditors({
  String inputLabel = 'Input',
  String outputLabel = 'Output',
  List<Widget> inputActions = const [],
  List<Widget> outputActions = const [],
  bool outputReadOnly = true,
  String inputPlaceholder = 'Enter text...',
  String outputPlaceholder = 'Output...',
  TextEditingController? inputController,
  TextEditingController? outputController,
  ValueChanged<String>? onInputChanged,
}) {
  return buildSplitEditors(
    inputLabel: inputLabel,
    outputLabel: outputLabel,
    inputActions: inputActions,
    outputActions: outputActions,
    outputReadOnly: outputReadOnly,
    inputPlaceholder: inputPlaceholder,
    outputPlaceholder: outputPlaceholder,
    inputController: inputController,
    outputController: outputController,
    onInputChanged: onInputChanged,
    horizontal: false,
  );
}

String _indentFor(String value) {
  switch (value) {
    case '4 spaces':
      return '    ';
    case 'Tabs':
      return '\t';
    default:
      return '  ';
  }
}

String _bytesToHex(List<int> bytes, {bool lower = false}) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    final hex = byte.toRadixString(16).padLeft(2, '0');
    buffer.write(lower ? hex : hex.toUpperCase());
  }
  return buffer.toString();
}

int _colorComponent(double value) {
  return (value * 255.0).round().clamp(0, 255).toInt();
}

Future<String> _readClipboardText() async {
  final data = await Clipboard.getData('text/plain');
  return data?.text ?? '';
}

String _base64UrlNoPad(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

Uint8List _base64UrlDecode(String input) {
  final normalized = base64Url.normalize(input);
  return Uint8List.fromList(base64Url.decode(normalized));
}

class _JsonFormatValidateView extends StatefulWidget {
  const _JsonFormatValidateView();

  @override
  State<_JsonFormatValidateView> createState() =>
      _JsonFormatValidateViewState();
}

class _JsonFormatValidateViewState extends State<_JsonFormatValidateView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _indent = '2 spaces';
  String? _error;
  _JsonValidationInfo? _info;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _runFormat() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
        _info = null;
      });
      return;
    }
    try {
      final validation = _validateJson(text, strict: true);
      if (!validation.isValid) {
        setState(() {
          _error = validation.error?.description ?? 'Invalid JSON';
          _info = null;
        });
        return;
      }
      final decoded = jsonDecode(text);
      final encoder = JsonEncoder.withIndent(_indentFor(_indent));
      _output.text = encoder.convert(decoded);
      setState(() {
        _error = null;
        _info = validation.info;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() {
      _input.text = text;
    });
  }

  void _setSample() {
    const sample = '{"name":"DevUtils","items":[1,2,3],"enabled":true}';
    setState(() {
      _input.text = sample;
    });
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
      _info = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _runFormat),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
              const SmallDropdown(items: ['JSON'], initialValue: 'JSON'),
            ],
            outputActions: [
              SmallDropdown(
                items: const ['2 spaces', '4 spaces', 'Tabs'],
                initialValue: _indent,
                onChanged: (value) {
                  setState(() => _indent = value);
                  _runFormat();
                },
              ),
              ToolButton(label: 'Copy', onPressed: _copyOutput),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: 'Paste JSON...',
            outputPlaceholder: 'Formatted JSON...',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ] else if (_info != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _info!.summary,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ],
    );
  }
}

class _JsonValidationResult {
  const _JsonValidationResult.valid(this.info) : error = null, isValid = true;
  const _JsonValidationResult.invalid(this.error)
    : info = null,
      isValid = false;

  final bool isValid;
  final _JsonValidationInfo? info;
  final _JsonValidationError? error;
}

class _JsonValidationInfo {
  const _JsonValidationInfo({
    required this.rootType,
    required this.keyCount,
    required this.elementCount,
    required this.depth,
    required this.size,
  });

  final String rootType;
  final int? keyCount;
  final int? elementCount;
  final int depth;
  final int size;

  String get summary {
    final parts = <String>[
      'Valid JSON',
      'root: $rootType',
      if (keyCount != null) 'keys: $keyCount',
      if (elementCount != null) 'elements: $elementCount',
      'depth: $depth',
      '$size bytes',
    ];
    return parts.join(' • ');
  }
}

class _JsonValidationError {
  const _JsonValidationError({
    required this.message,
    required this.line,
    required this.column,
    this.context,
  });

  final String message;
  final int line;
  final int column;
  final String? context;

  String get description {
    var desc = 'Line $line, Column $column: $message';
    if (context != null && context!.isNotEmpty) {
      desc += '\n  -> $context';
    }
    return desc;
  }
}

_JsonValidationResult _validateJson(String json, {bool strict = false}) {
  final trimmed = json.trim();
  if (trimmed.isEmpty) {
    return const _JsonValidationResult.invalid(
      _JsonValidationError(message: 'Empty input', line: 1, column: 1),
    );
  }

  if (strict) {
    final strictError = _checkStrictCompliance(trimmed);
    if (strictError != null) {
      return _JsonValidationResult.invalid(strictError);
    }
  }

  try {
    final decoded = jsonDecode(trimmed);
    final info = _analyzeJson(decoded, utf8.encode(trimmed).length);
    return _JsonValidationResult.valid(info);
  } on FormatException catch (e) {
    final offset = e.offset ?? 0;
    final position = _positionFromIndex(offset, trimmed);
    final context = _extractContext(position.line, position.column, trimmed);
    final message = e.message;
    return _JsonValidationResult.invalid(
      _JsonValidationError(
        message: message,
        line: position.line,
        column: position.column,
        context: context,
      ),
    );
  } catch (e) {
    return const _JsonValidationResult.invalid(
      _JsonValidationError(message: 'Invalid JSON', line: 1, column: 1),
    );
  }
}

_JsonValidationInfo _analyzeJson(dynamic value, int size) {
  final rootType = _jsonType(value);
  final depth = _jsonDepth(value);
  int? keyCount;
  int? elementCount;
  if (value is Map) {
    keyCount = value.length;
  } else if (value is List) {
    elementCount = value.length;
  }
  return _JsonValidationInfo(
    rootType: rootType,
    keyCount: keyCount,
    elementCount: elementCount,
    depth: depth,
    size: size,
  );
}

String _jsonType(dynamic value) {
  if (value is Map) return 'object';
  if (value is List) return 'array';
  if (value is String) return 'string';
  if (value is num) return 'number';
  if (value is bool) return 'boolean';
  if (value == null) return 'null';
  return 'string';
}

int _jsonDepth(dynamic value, [int current = 1]) {
  if (value is Map) {
    if (value.isEmpty) return current;
    final depths = value.values.map((entry) => _jsonDepth(entry, current + 1));
    return depths.reduce(max);
  }
  if (value is List) {
    if (value.isEmpty) return current;
    final depths = value.map((entry) => _jsonDepth(entry, current + 1));
    return depths.reduce(max);
  }
  return current;
}

({int line, int column}) _positionFromIndex(int index, String input) {
  var line = 1;
  var column = 1;
  var current = 0;
  for (final rune in input.runes) {
    if (current >= index) break;
    final char = String.fromCharCode(rune);
    if (char == '\n') {
      line += 1;
      column = 1;
    } else {
      column += 1;
    }
    current += 1;
  }
  return (line: line, column: column);
}

String? _extractContext(int line, int column, String json) {
  final lines = json.split('\n');
  if (line <= 0 || line > lines.length) return null;
  final errorLine = lines[line - 1].trim();
  if (errorLine.length <= 60) return errorLine;
  final start = max(0, column - 30);
  final end = min(errorLine.length, column + 30);
  var snippet = errorLine.substring(start, end);
  if (start > 0) snippet = '...$snippet';
  if (end < errorLine.length) snippet = '$snippet...';
  return snippet;
}

_JsonValidationError? _checkStrictCompliance(String json) {
  final chars = json.split('');
  var inString = false;
  var lastNonWhitespace = ' ';
  var line = 1;
  var column = 1;
  var i = 0;
  while (i < chars.length) {
    final char = chars[i];
    if (char == '\n') {
      line += 1;
      column = 1;
    } else {
      column += 1;
    }

    if (char == '"' && (i == 0 || chars[i - 1] != '\\')) {
      inString = !inString;
      lastNonWhitespace = char;
      i += 1;
      continue;
    }

    if (inString) {
      i += 1;
      continue;
    }

    if (char == '/' &&
        i + 1 < chars.length &&
        (chars[i + 1] == '/' || chars[i + 1] == '*')) {
      return _JsonValidationError(
        message: 'Comments are not allowed in JSON',
        line: line,
        column: column - 1,
      );
    }

    if ((char == '}' || char == ']') && lastNonWhitespace == ',') {
      return _JsonValidationError(
        message: 'Trailing commas are not allowed in JSON',
        line: line,
        column: column - 1,
      );
    }

    if (char == "'") {
      return _JsonValidationError(
        message: 'Single quotes are not allowed, use double quotes',
        line: line,
        column: column - 1,
      );
    }

    if (!RegExp(r'\s').hasMatch(char)) {
      lastNonWhitespace = char;
    }

    i += 1;
  }
  return null;
}

class _CsvToJsonView extends StatefulWidget {
  const _CsvToJsonView();

  @override
  State<_CsvToJsonView> createState() => _CsvToJsonViewState();
}

class _CsvToJsonViewState extends State<_CsvToJsonView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _indent = '2 spaces';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      final rows = _parseCsv(text);
      if (rows.isEmpty) {
        setState(() {
          _output.text = '[]';
          _error = null;
        });
        return;
      }
      final headers = rows.first;
      final data = <Map<String, String>>[];
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        final map = <String, String>{};
        for (var j = 0; j < headers.length; j++) {
          map[headers[j]] = j < row.length ? row[j] : '';
        }
        data.add(map);
      }
      final encoder = JsonEncoder.withIndent(_indentFor(_indent));
      _output.text = encoder.convert(data);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() {
      _input.text = text;
    });
  }

  void _setSample() {
    const sample =
        'id,name,note\n1,DevUtils,"Sample row"\n2,Example,"Escaped ""string"""';
    setState(() {
      _input.text = sample;
    });
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
            ],
            outputActions: [
              SmallDropdown(
                items: const ['2 spaces', '4 spaces', 'Tabs'],
                initialValue: _indent,
                onChanged: (value) {
                  setState(() => _indent = value);
                  _run();
                },
              ),
              ToolButton(label: 'Copy', onPressed: _copyOutput),
            ],
            inputPlaceholder: 'id,name,note',
            outputPlaceholder: '[]',
            inputController: _input,
            outputController: _output,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  final row = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (inQuotes) {
      if (char == '"') {
        final next = i + 1 < input.length ? input[i + 1] : '';
        if (next == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(char);
      }
    } else {
      if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        row.add(buffer.toString());
        buffer.clear();
      } else if (char == '\n') {
        row.add(buffer.toString());
        buffer.clear();
        rows.add(List<String>.from(row));
        row.clear();
      } else if (char == '\r') {
        if (i + 1 < input.length && input[i + 1] == '\n') {
          i++;
        }
        row.add(buffer.toString());
        buffer.clear();
        rows.add(List<String>.from(row));
        row.clear();
      } else {
        buffer.write(char);
      }
    }
  }

  if (buffer.isNotEmpty || row.isNotEmpty) {
    row.add(buffer.toString());
    rows.add(List<String>.from(row));
  }

  return rows;
}

class _HexToAsciiView extends StatefulWidget {
  const _HexToAsciiView();

  @override
  State<_HexToAsciiView> createState() => _HexToAsciiViewState();
}

class _HexToAsciiViewState extends State<_HexToAsciiView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      final bytes = <int>[];
      final parts = text.split(RegExp(r'\s+'));
      for (final part in parts) {
        if (part.trim().isEmpty) continue;
        var token = part.trim();
        if (token.startsWith('0x') || token.startsWith('0X')) {
          token = token.substring(2);
        }
        if (token.length.isOdd) {
          token = '0$token';
        }
        for (var i = 0; i < token.length; i += 2) {
          final hexPair = token.substring(i, i + 2);
          bytes.add(int.parse(hexPair, radix: 16));
        }
      }
      _output.text = String.fromCharCodes(bytes);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() {
      _input.text = text;
    });
  }

  void _setSample() {
    setState(() {
      _input.text = '48 65 6C 6C 6F 20 66 72 6F 6D 20 44 65 76 55 74 69 6C 73';
    });
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
            ],
            outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
            inputPlaceholder: '48 65 6C 6C 6F',
            outputPlaceholder: 'Hello',
            inputController: _input,
            outputController: _output,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

class _AsciiToHexView extends StatefulWidget {
  const _AsciiToHexView();

  @override
  State<_AsciiToHexView> createState() => _AsciiToHexViewState();
}

class _AsciiToHexViewState extends State<_AsciiToHexView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    if (text.isEmpty) {
      setState(() => _output.text = '');
      return;
    }
    final bytes = text.codeUnits;
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i > 0) buffer.write(' ');
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    setState(() => _output.text = buffer.toString());
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() {
      _input.text = text;
    });
  }

  void _setSample() {
    setState(() => _input.text = 'Hello from DevUtils');
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
      ],
      outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
      inputPlaceholder: 'Hello from DevUtils',
      outputPlaceholder: '48 65 6C 6C 6F',
      inputController: _input,
      outputController: _output,
    );
  }
}

class _Base64StringView extends StatefulWidget {
  const _Base64StringView();

  @override
  State<_Base64StringView> createState() => _Base64StringViewState();
}

class _Base64StringViewState extends State<_Base64StringView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  var _encode = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      if (_encode) {
        final bytes = utf8.encode(text);
        _output.text = base64Encode(bytes);
      } else {
        final bytes = base64Decode(text);
        _output.text = utf8.decode(bytes, allowMalformed: true);
      }
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(
      () => _input.text = _encode
          ? 'Hello from DevUtils'
          : 'SGVsbG8gZnJvbSBEZXZVdGlscw==',
    );
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _useAsInput() {
    setState(() => _input.text = _output.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildVerticalEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
              SegmentedToggle(
                options: const ['Encode', 'Decode'],
                initialIndex: _encode ? 0 : 1,
                onChanged: (index) {
                  setState(() => _encode = index == 0);
                  _run();
                },
              ),
            ],
            outputActions: [
              ToolButton(label: 'Copy', onPressed: _copyOutput),
              ToolButton(label: 'Use as input', onPressed: _useAsInput),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: _encode ? 'Hello from DevUtils' : 'SGVsbG8=',
            outputPlaceholder: _encode ? 'SGVsbG8=' : 'Hello',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

class _UrlEncodeDecodeView extends StatefulWidget {
  const _UrlEncodeDecodeView();

  @override
  State<_UrlEncodeDecodeView> createState() => _UrlEncodeDecodeViewState();
}

class _UrlEncodeDecodeViewState extends State<_UrlEncodeDecodeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  var _encode = true;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      _output.text = _encode
          ? Uri.encodeComponent(text)
          : Uri.decodeComponent(text);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(
      () => _input.text = _encode
          ? r'abc 0123 !@#$'
          : 'abc%200123%20%21%40%23%24',
    );
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _useAsInput() {
    setState(() => _input.text = _output.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildVerticalEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
              SegmentedToggle(
                options: const ['Encode', 'Decode'],
                initialIndex: _encode ? 0 : 1,
                onChanged: (index) {
                  setState(() => _encode = index == 0);
                  _run();
                },
              ),
            ],
            outputActions: [
              ToolButton(label: 'Copy', onPressed: _copyOutput),
              ToolButton(label: 'Use as input', onPressed: _useAsInput),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: _encode ? r'abc 0123 !@#$' : 'abc%200123',
            outputPlaceholder: _encode ? 'abc%200123' : 'abc 0123',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

class _BackslashEscapeView extends StatefulWidget {
  const _BackslashEscapeView();

  @override
  State<_BackslashEscapeView> createState() => _BackslashEscapeViewState();
}

class _BackslashEscapeViewState extends State<_BackslashEscapeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  var _escape = false;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    setState(() {
      _output.text = _escape
          ? _escapeBackslashes(text)
          : _unescapeBackslashes(text);
    });
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(
      () => _input.text = _escape ? 'Line 1\nLine 2' : 'Line 1\\nLine 2',
    );
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _useAsInput() {
    setState(() => _input.text = _output.text);
  }

  @override
  Widget build(BuildContext context) {
    return buildVerticalEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
        SegmentedToggle(
          options: const ['Escape', 'Unescape'],
          initialIndex: _escape ? 0 : 1,
          onChanged: (index) {
            setState(() => _escape = index == 0);
            _run();
          },
        ),
      ],
      outputActions: [
        ToolButton(label: 'Copy', onPressed: _copyOutput),
        ToolButton(label: 'Use as input', onPressed: _useAsInput),
      ],
      inputController: _input,
      outputController: _output,
      inputPlaceholder: 'Line 1\\nLine 2',
      outputPlaceholder: 'Line 1\nLine 2',
    );
  }
}

String _escapeBackslashes(String input) {
  return input
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t')
      .replaceAll('"', r'\"');
}

String _unescapeBackslashes(String input) {
  return input
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', '\\');
}

class _LineSortDedupeView extends StatefulWidget {
  const _LineSortDedupeView();

  @override
  State<_LineSortDedupeView> createState() => _LineSortDedupeViewState();
}

class _LineSortDedupeViewState extends State<_LineSortDedupeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _sort = 'A -> Z (Text)';
  String _dupes = 'With Duplicates';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final lines = _input.text.split(RegExp(r'\r?\n'));
    final cleaned = _dupes == 'With Duplicates'
        ? lines
        : lines.toSet().toList();
    cleaned.sort((a, b) => a.compareTo(b));
    if (_sort.startsWith('Z')) {
      cleaned.setAll(0, cleaned.reversed);
    }
    _output.text = cleaned.join('\n');
    setState(() {});
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(() => _input.text = '1\n11\n2\n22\n22\n33\n5.0\n2.5');
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
      ],
      outputActions: [
        SmallDropdown(
          items: const ['A -> Z (Text)', 'Z -> A (Text)'],
          initialValue: _sort,
          onChanged: (value) {
            setState(() => _sort = value);
            _run();
          },
        ),
        SmallDropdown(
          items: const ['With Duplicates', 'Without Duplicates'],
          initialValue: _dupes,
          onChanged: (value) {
            setState(() => _dupes = value);
            _run();
          },
        ),
        ToolButton(label: 'Copy', onPressed: _copyOutput),
      ],
      inputController: _input,
      outputController: _output,
      inputPlaceholder: 'Line 1\nLine 2\nLine 2',
      outputPlaceholder: 'Line 1\nLine 2',
    );
  }
}

class _SimplePassThroughView extends StatefulWidget {
  const _SimplePassThroughView({
    required this.inputPlaceholder,
    this.showIndent = false,
    this.showIncludeComments = false,
  });

  final String inputPlaceholder;
  final bool showIndent;
  final bool showIncludeComments;

  @override
  State<_SimplePassThroughView> createState() => _SimplePassThroughViewState();
}

class _SimplePassThroughViewState extends State<_SimplePassThroughView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _indent = '2 spaces';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    setState(() => _output.text = _input.text);
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    final outputActions = <Widget>[];
    if (widget.showIncludeComments) {
      outputActions.add(
        const SmallDropdown(
          items: ['Include Comments', 'Exclude Comments'],
          initialValue: 'Include Comments',
        ),
      );
    }
    if (widget.showIndent) {
      outputActions.add(
        SmallDropdown(
          items: const ['2 spaces', '4 spaces', 'Tabs'],
          initialValue: _indent,
          onChanged: (value) => setState(() => _indent = value),
        ),
      );
    }
    outputActions.add(ToolButton(label: 'Copy', onPressed: _copyOutput));

    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: () {}),
        ToolButton(label: 'Clear', onPressed: _clearInput),
      ],
      outputActions: outputActions,
      inputController: _input,
      outputController: _output,
      inputPlaceholder: widget.inputPlaceholder,
      outputPlaceholder: 'Output...',
    );
  }
}

class _HtmlBeautifyMinifyView extends StatefulWidget {
  const _HtmlBeautifyMinifyView();

  @override
  State<_HtmlBeautifyMinifyView> createState() =>
      _HtmlBeautifyMinifyViewState();
}

class _HtmlBeautifyMinifyViewState extends State<_HtmlBeautifyMinifyView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _format = 'Beautify';
  String _indent = '2 spaces';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    if (_format == 'Minify') {
      _output.text = _minifyHtml(text);
    } else {
      _output.text = text;
    }
    setState(() {});
  }

  String _minifyHtml(String html) {
    var result = html;
    result = result.replaceAll(RegExp(r'<!--(?!\[if)[\s\S]*?-->'), '');
    result = result.replaceAll(RegExp(r'>\s+<'), '><');
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ');
    result = result.replaceAll(RegExp(r'\s*=\s*'), '=');
    return result.trim();
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _run();
  }

  void _setSample() {
    const sample = '<div class="card">\n  <h1>Hello</h1>\n</div>';
    setState(() => _input.text = sample);
    _run();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
      ],
      outputActions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Format...',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            SmallDropdown(
              items: const ['Beautify', 'Minify'],
              initialValue: _format,
              onChanged: (value) {
                setState(() => _format = value);
                _run();
              },
            ),
          ],
        ),
        if (_format == 'Beautify')
          SmallDropdown(
            items: const ['2 spaces', '4 spaces', 'Tabs'],
            initialValue: _indent,
            onChanged: (value) {
              setState(() => _indent = value);
              _run();
            },
          ),
        ToolButton(label: 'Copy', onPressed: _copyOutput),
      ],
      inputController: _input,
      outputController: _output,
      inputPlaceholder: 'Paste HTML here...',
      outputPlaceholder: 'Output...',
    );
  }
}

class _JsBeautifyMinifyView extends StatefulWidget {
  const _JsBeautifyMinifyView();

  @override
  State<_JsBeautifyMinifyView> createState() => _JsBeautifyMinifyViewState();
}

class _JsBeautifyMinifyViewState extends State<_JsBeautifyMinifyView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _format = 'Beautify';
  String _indent = '2 spaces';

  static const Set<String> _jsKeywords = {
    'break',
    'case',
    'catch',
    'continue',
    'debugger',
    'default',
    'delete',
    'do',
    'else',
    'finally',
    'for',
    'function',
    'if',
    'in',
    'instanceof',
    'new',
    'return',
    'switch',
    'this',
    'throw',
    'try',
    'typeof',
    'var',
    'void',
    'while',
    'with',
    'class',
    'const',
    'enum',
    'export',
    'extends',
    'import',
    'super',
    'implements',
    'interface',
    'let',
    'package',
    'private',
    'protected',
    'public',
    'static',
    'yield',
    'async',
    'await',
    'of',
    'true',
    'false',
    'null',
    'undefined',
    'nan',
    'infinity',
  };

  static const Set<String> _tsKeywords = {
    'type',
    'interface',
    'namespace',
    'module',
    'declare',
    'abstract',
    'as',
    'asserts',
    'any',
    'boolean',
    'constructor',
    'get',
    'set',
    'infer',
    'is',
    'keyof',
    'never',
    'readonly',
    'require',
    'number',
    'object',
    'string',
    'symbol',
    'unique',
    'unknown',
    'from',
    'global',
    'bigint',
    'override',
    'satisfies',
  };

  static final Set<String> _allKeywords = {..._jsKeywords, ..._tsKeywords};

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    switch (_format) {
      case 'Minify':
        _output.text = _minifyJs(text);
        break;
      case 'Obfuscate':
        _output.text = _obfuscateJs(text);
        break;
      case 'Verify':
        _output.text = _formatKeywordTypos(text);
        break;
      case 'Beautify':
      default:
        _output.text = _beautifyJs(text, _indentFor(_indent));
        break;
    }
    setState(() {});
  }

  String _beautifyJs(String code, String indentString) {
    if (code.trim().isEmpty) return '';
    var result = '';
    var indentLevel = 0;
    String? inString;
    var inSingleLineComment = false;
    var inMultiLineComment = false;
    var genericDepth = 0;
    var lastChar = ' ';
    var lastNonWhitespace = ' ';
    final chars = code.split('');
    var i = 0;

    const genericKeywords = {
      'Array',
      'Map',
      'Set',
      'Promise',
      'Record',
      'Partial',
      'Required',
      'Pick',
      'Omit',
      'Exclude',
      'Extract',
      'ReturnType',
      'Parameters',
      'InstanceType',
      'Readonly',
      'NonNullable',
    };
    const typeKeywords = {
      'extends',
      'implements',
      'type',
      'interface',
      'as',
      'is',
      'keyof',
      'typeof',
      'infer',
    };

    String indent() => List.filled(indentLevel, indentString).join();

    void addNewline() {
      result = _trimTrailingWhitespace(result);
      if (!result.endsWith('\n')) {
        result += '\n';
      }
    }

    String? peek([int offset = 1]) {
      final idx = i + offset;
      return idx < chars.length ? chars[idx] : null;
    }

    String extractLastToken() {
      var token = '';
      for (final char in result.split('').reversed) {
        if (_isTokenChar(char)) {
          token = char + token;
        } else {
          break;
        }
      }
      return token;
    }

    while (i < chars.length) {
      final char = chars[i];
      final next = peek();

      if (inString == null &&
          !inMultiLineComment &&
          char == '/' &&
          next == '/') {
        result += '//';
        i += 2;
        inSingleLineComment = true;
        continue;
      }

      if (inSingleLineComment) {
        result += char;
        if (char == '\n') {
          inSingleLineComment = false;
          result += indent();
        }
        i += 1;
        continue;
      }

      if (inString == null && char == '/' && next == '*') {
        result += '/*';
        i += 2;
        inMultiLineComment = true;
        continue;
      }

      if (inMultiLineComment) {
        result += char;
        if (char == '*' && next == '/') {
          result += '/';
          inMultiLineComment = false;
          i += 2;
          continue;
        }
        i += 1;
        continue;
      }

      if ((char == '"' || char == "'" || char == '`') && lastChar != '\\') {
        if (inString == char) {
          inString = null;
        } else {
          inString ??= char;
        }
        result += char;
        lastChar = char;
        lastNonWhitespace = char;
        i += 1;
        continue;
      }

      if (inString != null) {
        result += char;
        lastChar = char;
        i += 1;
        continue;
      }

      switch (char) {
        case '{':
          if (!result.endsWith(' ') &&
              !result.endsWith('\n') &&
              !result.endsWith('(')) {
            result += ' ';
          }
          result += '{';
          indentLevel += 1;
          addNewline();
          result += indent();
          break;
        case '}':
          indentLevel = max(0, indentLevel - 1);
          addNewline();
          result += indent();
          result += '}';
          if (next != null &&
              next != ',' &&
              next != ';' &&
              next != ')' &&
              next != '}' &&
              next != ']' &&
              next != '.' &&
              next != '>') {
            addNewline();
            result += indent();
          }
          break;
        case '[':
          result += char;
          if (next == '{' || next == '[') {
            indentLevel += 1;
            addNewline();
            result += indent();
          }
          break;
        case ']':
          if (lastNonWhitespace == '}' || lastNonWhitespace == ']') {
            indentLevel = max(0, indentLevel - 1);
            addNewline();
            result += indent();
          }
          result += char;
          break;
        case '<':
          final token = extractLastToken();
          final isGeneric =
              genericKeywords.contains(token) ||
              typeKeywords.contains(token) ||
              (token.isNotEmpty && _startsWithUppercase(token)) ||
              lastNonWhitespace == ':' ||
              genericDepth > 0;
          if (isGeneric) {
            genericDepth += 1;
            result += char;
          } else {
            if (!result.endsWith(' ')) {
              result += ' ';
            }
            result += char;
            if (next == '=') {
              result += '=';
              i += 1;
            }
            result += ' ';
          }
          break;
        case '>':
          if (genericDepth > 0) {
            genericDepth -= 1;
            result += char;
          } else {
            if (!result.endsWith(' ') && !result.endsWith('=')) {
              result += ' ';
            }
            result += char;
            if (next == '=') {
              result += '=';
              i += 1;
            }
            if (!result.endsWith(' ')) {
              result += ' ';
            }
          }
          break;
        case ';':
          result += char;
          if (next != null && next != '}') {
            addNewline();
            result += indent();
          }
          break;
        case ',':
          result += char;
          if (lastNonWhitespace == '}' || lastNonWhitespace == ']') {
            addNewline();
            result += indent();
          } else {
            result += ' ';
          }
          break;
        case ':':
          result += ': ';
          break;
        case '@':
          if (result.isNotEmpty && !RegExp(r'\s$').hasMatch(result)) {
            addNewline();
            result += indent();
          }
          result += char;
          break;
        case '(':
        case ')':
          result += char;
          break;
        case '=':
          if (!result.endsWith(' ') &&
              !result.endsWith('!') &&
              !result.endsWith('<') &&
              !result.endsWith('>')) {
            result += ' ';
          }
          result += char;
          if (next == '=') {
            result += '=';
            i += 1;
            if (peek() == '=') {
              result += '=';
              i += 1;
            }
          } else if (next == '>') {
            result += '>';
            i += 1;
          }
          result += ' ';
          break;
        case '+':
        case '-':
        case '*':
        case '/':
        case '%':
          if (char == '/' &&
              (lastNonWhitespace == '(' ||
                  lastNonWhitespace == '=' ||
                  lastNonWhitespace == ',')) {
            result += char;
          } else {
            if (!result.endsWith(' ') &&
                !result.endsWith('\n') &&
                !result.endsWith('(')) {
              result += ' ';
            }
            result += char;
            if (next == '=' || next == char) {
              result += next!;
              i += 1;
            }
            result += ' ';
          }
          break;
        case '!':
        case '&':
        case '|':
        case '?':
          result += char;
          if (next == char ||
              next == '=' ||
              (char == '?' && next == '.') ||
              (char == '?' && next == '?')) {
            result += next!;
            i += 1;
          }
          if (char == '&' || char == '|') {
            result += ' ';
          }
          break;
        case ' ':
        case '\t':
        case '\n':
        case '\r':
          if (result.isNotEmpty &&
              !result.endsWith(' ') &&
              !result.endsWith('\n')) {
            result += ' ';
          }
          break;
        default:
          result += char;
      }

      lastChar = char;
      if (!RegExp(r'\s').hasMatch(char)) {
        lastNonWhitespace = char;
      }
      i += 1;
    }

    return _cleanupJsBeautify(result, indentString);
  }

  String _cleanupJsBeautify(String input, String indentString) {
    var result = input;
    const replacements = {
      '  ': ' ',
      ' \n': '\n',
      '( ': '(',
      ' )': ')',
      '[ ': '[',
      ' ]': ']',
      ' ;': ';',
      ' ,': ',',
      '< ': '<',
      ' >': '>',
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in replacements.entries) {
        if (result.contains(entry.key)) {
          result = result.replaceAll(entry.key, entry.value);
          changed = true;
        }
      }
    }

    final lines = result.split('\n');
    final finalLines = <String>[];
    var indent = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('}') || trimmed.startsWith(']')) {
        indent = max(0, indent - 1);
      }
      if (trimmed.isNotEmpty) {
        finalLines.add(List.filled(indent, indentString).join() + trimmed);
      } else {
        finalLines.add('');
      }
      if (trimmed.endsWith('{') ||
          (trimmed.endsWith('[') && !trimmed.contains(']'))) {
        indent += 1;
      }
    }

    return finalLines.join('\n').trim();
  }

  bool _isTokenChar(String value) {
    return RegExp(r'[A-Za-z0-9_]').hasMatch(value);
  }

  bool _startsWithUppercase(String value) {
    if (value.isEmpty) return false;
    final first = value[0];
    return first.toUpperCase() == first && first.toLowerCase() != first;
  }

  String _trimTrailingWhitespace(String value) {
    var result = value;
    while (result.isNotEmpty &&
        RegExp(r'\s').hasMatch(result[result.length - 1])) {
      if (result.endsWith('\n')) {
        break;
      }
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  String _minifyJs(String text) {
    var output = text.replaceAll(RegExp(r'/\\*([\\s\\S]*?)\\*/'), '');
    output = output.replaceAll(RegExp(r'//.*'), '');
    output = output.replaceAll(RegExp(r'\s+'), ' ');
    output = output.replaceAll(RegExp(r'\s*([{}();,:])\s*'), r'$1');
    return output.trim();
  }

  String _obfuscateJs(String text) {
    if (text.trim().isEmpty) return '';
    final encoded = base64.encode(utf8.encode(text));
    return [
      '(function(){',
      '  const _d = typeof atob === "function"',
      '    ? atob',
      '    : (s) => Buffer.from(s, "base64").toString("utf8");',
      '  eval(_d("$encoded"));',
      '})();',
    ].join('\n');
  }

  String _formatKeywordTypos(String text) {
    final typos = _findKeywordTypos(text);
    if (typos.isEmpty) {
      return 'No keyword typos found.';
    }
    return typos
        .map(
          (typo) =>
              'Line ${typo.line}, Col ${typo.column}: \'${typo.found}\' -> did you mean \'${typo.suggestion}\'?',
        )
        .join('\n');
  }

  List<_KeywordTypo> _findKeywordTypos(String code, {int maxDistance = 2}) {
    final tokens = _extractTokens(code);
    final typos = <_KeywordTypo>[];
    for (final token in tokens) {
      final value = token.value;
      final lower = value.toLowerCase();
      if (_allKeywords.contains(lower)) {
        continue;
      }
      if (value.length < 2 || value.length > 12) {
        continue;
      }
      if (value.isNotEmpty && value[0].toUpperCase() == value[0]) {
        continue;
      }
      final closest = _findClosestKeyword(lower, maxDistance: maxDistance);
      if (closest != null) {
        typos.add(
          _KeywordTypo(
            found: value,
            suggestion: closest.keyword,
            line: token.line,
            column: token.column,
            distance: closest.distance,
          ),
        );
      }
    }
    return typos;
  }

  List<_Token> _extractTokens(String code) {
    final tokens = <_Token>[];
    final chars = code.split('');
    var current = StringBuffer();
    int? tokenLine;
    int? tokenColumn;
    var line = 1;
    var col = 1;
    String? inString;
    var inLineComment = false;
    var inBlockComment = false;

    void flushToken() {
      if (current.isEmpty || tokenLine == null || tokenColumn == null) return;
      tokens.add(_Token(current.toString(), tokenLine!, tokenColumn!));
      current = StringBuffer();
      tokenLine = null;
      tokenColumn = null;
    }

    for (var i = 0; i < chars.length; i++) {
      final char = chars[i];
      final next = i + 1 < chars.length ? chars[i + 1] : null;
      final prev = i > 0 ? chars[i - 1] : null;

      if (char == '\n') {
        flushToken();
        line += 1;
        col = 1;
        inLineComment = false;
        continue;
      }

      if (inString == null && !inBlockComment && char == '/' && next == '/') {
        inLineComment = true;
      }
      if (inString == null && !inLineComment && char == '/' && next == '*') {
        inBlockComment = true;
      }
      if (inBlockComment && char == '*' && next == '/') {
        inBlockComment = false;
        i += 1;
        col += 2;
        continue;
      }

      if (inLineComment || inBlockComment) {
        col += 1;
        continue;
      }

      if ((char == '"' || char == "'" || char == '`') && prev != '\\') {
        if (inString == char) {
          inString = null;
        } else {
          inString ??= char;
        }
        col += 1;
        continue;
      }

      if (inString != null) {
        col += 1;
        continue;
      }

      final isTokenChar = RegExp(r'[A-Za-z0-9_]').hasMatch(char);
      final isStartChar = RegExp(r'[A-Za-z_]').hasMatch(char);

      if (isTokenChar && (current.isNotEmpty || isStartChar)) {
        if (current.isEmpty) {
          tokenLine = line;
          tokenColumn = col;
        }
        current.write(char);
      } else {
        flushToken();
      }

      col += 1;
    }

    flushToken();
    return tokens;
  }

  _KeywordCandidate? _findClosestKeyword(
    String word, {
    required int maxDistance,
  }) {
    _KeywordCandidate? best;
    for (final keyword in _allKeywords) {
      if ((keyword.length - word.length).abs() > maxDistance) continue;
      final distance = _levenshteinDistance(word, keyword);
      if (distance > 0 && distance <= maxDistance) {
        if (best == null || distance < best.distance) {
          best = _KeywordCandidate(keyword, distance);
        }
      }
    }
    return best;
  }

  int _levenshteinDistance(String s1, String s2) {
    final a = s1.split('');
    final b = s2.split('');
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final matrix = List.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return matrix[a.length][b.length];
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _run();
  }

  void _setSample() {
    const sample =
        '// program to generate fibonacci series up to n terms\n'
        '\n'
        '// take input from the user\n'
        "const number = parseInt(prompt('Enter the number of terms: '));\n"
        'let n1 = 0, n2 = 1, nextTerm;\n'
        '\n'
        "console.log('Fibonacci Series:');\n"
        '\n'
        'for (let i = 1; i <= number; i++) {\n'
        '    console.log(n1);\n'
        '    nextTerm = n1 + n2;\n'
        '    n1 = n2;\n'
        '    n2 = nextTerm;\n'
        '}\n';
    setState(() => _input.text = sample);
    _run();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
      ],
      outputActions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Format...',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            SmallDropdown(
              items: const ['Beautify', 'Minify', 'Obfuscate', 'Verify'],
              initialValue: _format,
              onChanged: (value) {
                setState(() => _format = value);
                _run();
              },
            ),
          ],
        ),
        if (_format == 'Beautify')
          SmallDropdown(
            items: const ['2 spaces', '4 spaces', 'Tabs'],
            initialValue: _indent,
            onChanged: (value) {
              setState(() => _indent = value);
              _run();
            },
          ),
        ToolButton(label: 'Copy', onPressed: _copyOutput),
      ],
      inputController: _input,
      outputController: _output,
      inputPlaceholder: 'Paste JS here...',
      outputPlaceholder: 'Output...',
    );
  }
}

class _Token {
  const _Token(this.value, this.line, this.column);

  final String value;
  final int line;
  final int column;
}

class _KeywordTypo {
  const _KeywordTypo({
    required this.found,
    required this.suggestion,
    required this.line,
    required this.column,
    required this.distance,
  });

  final String found;
  final String suggestion;
  final int line;
  final int column;
  final int distance;
}

class _KeywordCandidate {
  const _KeywordCandidate(this.keyword, this.distance);

  final String keyword;
  final int distance;
}

class _Base64ImageView extends StatefulWidget {
  const _Base64ImageView();

  @override
  State<_Base64ImageView> createState() => _Base64ImageViewState();
}

class _Base64ImageViewState extends State<_Base64ImageView> {
  final TextEditingController _input = TextEditingController();
  String _previewLabel = 'Image preview (base64 only)';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(() => _input.text = 'iVBORw0KGgoAAAANSUhEUgAAAAUA');
  }

  void _clear() {
    setState(() {
      _input.clear();
      _previewLabel = 'Image preview (base64 only)';
    });
  }

  Future<void> _copyString() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
  }

  Future<void> _copyImage() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: EditorPane(
            label: 'String',
            actions: [
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clear),
              ToolButton(label: 'Copy', onPressed: _copyString),
            ],
            controller: _input,
            onChanged: (_) => setState(() {
              _previewLabel = _input.text.isEmpty
                  ? 'Image preview (base64 only)'
                  : 'Preview ready';
            }),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Image',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  ToolIconButton(
                    icon: Icons.content_paste,
                    tooltip: 'Clipboard',
                    onPressed: () {},
                  ),
                  ToolIconButton(
                    icon: Icons.upload_file,
                    tooltip: 'Load File...',
                    onPressed: () {},
                  ),
                  ToolIconButton(
                    icon: Icons.clear,
                    tooltip: 'Clear',
                    onPressed: () {
                      setState(
                        () => _previewLabel = 'Image preview (base64 only)',
                      );
                    },
                  ),
                  ToolIconButton(
                    icon: Icons.save_alt,
                    tooltip: 'Save',
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          _previewLabel,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: IconButton(
                          onPressed: _copyImage,
                          icon: const Icon(Icons.copy_all, size: 16),
                          tooltip: 'Copy',
                          padding: const EdgeInsets.all(4),
                          splashRadius: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UrlParserView extends StatefulWidget {
  const _UrlParserView();

  @override
  State<_UrlParserView> createState() => _UrlParserViewState();
}

class _UrlParserViewState extends State<_UrlParserView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _queryJson = TextEditingController();
  String _protocol = '';
  String _host = '';
  String _path = '';
  String _file = '';
  String _query = '';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _queryJson.dispose();
    super.dispose();
  }

  void _parse() {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _protocol = '';
        _host = '';
        _path = '';
        _file = '';
        _query = '';
        _queryJson.clear();
        _error = null;
      });
      return;
    }
    try {
      final uri = Uri.parse(raw);
      _protocol = uri.scheme;
      _host = uri.host;
      _path = uri.path;
      _file = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      _query = uri.query;
      final queryMap = uri.queryParameters;
      _queryJson.text = const JsonEncoder.withIndent('  ').convert(queryMap);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _parse();
  }

  void _setSample() {
    const sample =
        'https://www.google.com/search?q=sample+long+query&src=devutils';
    setState(() => _input.text = sample);
    _parse();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _queryJson.clear();
      _error = null;
    });
  }

  Future<void> _copyQuery() async {
    await Clipboard.setData(ClipboardData(text: _queryJson.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: EditorPane(
            label: 'Input',
            actions: [
              ToolButton(label: 'Go', onPressed: _parse),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
            ],
            controller: _input,
            onChanged: (_) => _parse(),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Field'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Protocol: $_protocol'),
                    Text('Host: $_host'),
                    Text('Path: $_path'),
                    Text('File name: $_file'),
                    Text('Query: $_query'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: EditorPane(
                  label: 'Query string',
                  actions: [ToolButton(label: 'Copy', onPressed: _copyQuery)],
                  controller: _queryJson,
                  readOnly: true,
                  placeholder: '{ }',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

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
      _standard.clear();
      _raw.clear();
      _version.clear();
      _variant.clear();
      _time.clear();
      _clock.clear();
      _node.clear();
      setState(() {});
      return;
    }
    final normalized = text.toLowerCase();
    _standard.text = normalized;
    _raw.text = normalized.replaceAll('-', '');
    if (normalized.contains('-')) {
      final parts = normalized.split('-');
      if (parts.length >= 3) {
        _version.text = parts[2].isNotEmpty ? parts[2][0] : '';
      }
    }
    _variant.text = normalized.isNotEmpty ? normalized[0] : '';
    setState(() {});
  }

  String _uuidV4() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = _bytesToHex(bytes, lower: true);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _generate() {
    final count = int.tryParse(_count.text) ?? 1;
    final values = <String>[];
    for (var i = 0; i < count; i++) {
      values.add(_uuidV4());
    }
    var output = values.join('\n');
    if (!_lowercase) {
      output = output.toUpperCase();
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: [
              EditorPane(
                label: 'Input',
                actions: [
                  ToolButton(
                    label: 'Clipboard',
                    onPressed: () async {
                      final text = await _readClipboardText();
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
                  const ToolIconButton(icon: Icons.settings),
                ],
                controller: _input,
                onChanged: (_) => _decode(),
                placeholder: '00000000-0000-0000-0000-000000000000',
                expand: false,
                fixedHeight: 120,
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Standard String Format',
                trailing: ToolIconButton(
                  icon: Icons.copy,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _standard.text)),
                ),
                controller: _standard,
                readOnly: true,
              ),
              LabeledField(
                label: 'Raw Contents',
                trailing: ToolIconButton(
                  icon: Icons.copy,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _raw.text)),
                ),
                controller: _raw,
                readOnly: true,
              ),
              LabeledField(
                label: 'Version',
                trailing: ToolIconButton(
                  icon: Icons.copy,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _version.text)),
                ),
                controller: _version,
                readOnly: true,
              ),
              LabeledField(
                label: 'Variant',
                trailing: ToolIconButton(
                  icon: Icons.copy,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _variant.text)),
                ),
                controller: _variant,
                readOnly: true,
              ),
              LabeledField(
                label: 'Contents - Time',
                trailing: ToolIconButton(icon: Icons.copy, onPressed: () {}),
                controller: _time,
                readOnly: true,
              ),
              LabeledField(
                label: 'Contents - Clock ID',
                trailing: ToolIconButton(icon: Icons.copy, onPressed: () {}),
                controller: _clock,
                readOnly: true,
              ),
              LabeledField(
                label: 'Contents - Node',
                trailing: ToolIconButton(icon: Icons.copy, onPressed: () {}),
                controller: _node,
                readOnly: true,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Generate new IDs',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  SmallDropdown(
                    items: const ['UUID v4', 'UUID v1', 'ULID'],
                    initialValue: _type,
                    onChanged: (value) => setState(() => _type = value),
                  ),
                  const SizedBox(width: 8),
                  _InlineTextField(
                    width: 48,
                    hintText: '1',
                    controller: _count,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ToolButton(label: 'Generate', onPressed: _generate),
                  const SizedBox(width: 8),
                  ToolButton(label: 'Clear', onPressed: _clearGenerated),
                  const Spacer(),
                  Checkbox(
                    value: _lowercase,
                    onChanged: (value) =>
                        setState(() => _lowercase = value ?? false),
                  ),
                  const Text('lowercased'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: EditorPane(
                  label: '',
                  actions: const [],
                  controller: _generated,
                  readOnly: true,
                  placeholder: '- Right click -> Save to file...',
                  copyAction: _copyGenerated,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HtmlPreviewView extends StatefulWidget {
  const _HtmlPreviewView();

  @override
  State<_HtmlPreviewView> createState() => _HtmlPreviewViewState();
}

class _HtmlPreviewViewState extends State<_HtmlPreviewView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _preview = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _preview.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() {
      _input.text = text;
      _preview.text = text;
    });
  }

  void _setSample() {
    const sample = '<h1>Hello from DevUtils.app!</h1>';
    setState(() {
      _input.text = sample;
      _preview.text = sample;
    });
  }

  void _clear() {
    setState(() {
      _input.clear();
      _preview.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: EditorPane(
            label: 'Input',
            actions: [
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clear),
              const ToolIconButton(icon: Icons.settings),
              const SmallDropdown(
                items: ['Format...'],
                initialValue: 'Format...',
              ),
            ],
            controller: _input,
            onChanged: (value) => setState(() => _preview.text = value),
            placeholder: '<html>...</html>',
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: EditorPane(
            label: 'Preview',
            actions: const [
              ToolButton(label: 'Open in Browser'),
              ToolButton(label: 'Reload'),
            ],
            readOnly: true,
            placeholder: '',
            controller: _preview,
          ),
        ),
      ],
    );
  }
}

class _TextDiffView extends StatefulWidget {
  const _TextDiffView();

  @override
  State<_TextDiffView> createState() => _TextDiffViewState();
}

class _TextDiffViewState extends State<_TextDiffView> {
  final TextEditingController _left = TextEditingController();
  final TextEditingController _right = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _mode = 'Characters';

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final left = _left.text;
    final right = _right.text;
    List<String> leftParts;
    List<String> rightParts;
    if (_mode == 'Words') {
      leftParts = left.split(RegExp(r'\s+'));
      rightParts = right.split(RegExp(r'\s+'));
    } else if (_mode == 'Lines') {
      leftParts = left.split('\n');
      rightParts = right.split('\n');
    } else {
      leftParts = left.split('');
      rightParts = right.split('');
    }
    final removed = leftParts
        .where((item) => !rightParts.contains(item))
        .toList();
    final added = rightParts
        .where((item) => !leftParts.contains(item))
        .toList();
    final buffer = StringBuffer();
    for (final item in removed) {
      buffer.writeln('- $item');
    }
    for (final item in added) {
      buffer.writeln('+ $item');
    }
    setState(() => _output.text = buffer.toString().trimRight());
  }

  void _swap() {
    final temp = _left.text;
    _left.text = _right.text;
    _right.text = temp;
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: EditorPane(
                  label: 'Input 1',
                  actions: [
                    ToolButton(
                      label: 'Clipboard',
                      onPressed: () async {
                        final text = await _readClipboardText();
                        setState(() => _left.text = text);
                        _run();
                      },
                    ),
                    ToolButton(
                      label: 'Sample',
                      onPressed: () {
                        setState(() => _left.text = 'Line one\nLine two');
                        _run();
                      },
                    ),
                    ToolButton(
                      label: 'Clear',
                      onPressed: () {
                        setState(() => _left.clear());
                        _run();
                      },
                    ),
                  ],
                  controller: _left,
                  onChanged: (_) => _run(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: EditorPane(
                  label: 'Input 2',
                  actions: [
                    ToolButton(
                      label: 'Clipboard',
                      onPressed: () async {
                        final text = await _readClipboardText();
                        setState(() => _right.text = text);
                        _run();
                      },
                    ),
                    ToolButton(
                      label: 'Clear',
                      onPressed: () {
                        setState(() => _right.clear());
                        _run();
                      },
                    ),
                    ToolButton(label: 'Swap Inputs', onPressed: _swap),
                  ],
                  controller: _right,
                  onChanged: (_) => _run(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Diff mode:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SegmentedToggle(
              options: const ['Characters', 'Words', 'Lines'],
              initialIndex: 0,
              onChanged: (index) {
                setState(
                  () => _mode = const ['Characters', 'Words', 'Lines'][index],
                );
                _run();
              },
            ),
            const SizedBox(width: 8),
            const Text(
              'Output:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SmallDropdown(
              items: ['Formatted Text', 'Plain Text'],
              initialValue: 'Formatted Text',
            ),
            const Icon(Icons.chevron_left, size: 16),
            Text(
              '${_output.text.split('\n').where((line) => line.isNotEmpty).length}',
            ),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: EditorPane(
            label: '',
            actions: [
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            controller: _output,
            readOnly: true,
            placeholder: 'Diff output...',
          ),
        ),
      ],
    );
  }
}

class _NumberBaseConverterView extends StatefulWidget {
  const _NumberBaseConverterView();

  @override
  State<_NumberBaseConverterView> createState() =>
      _NumberBaseConverterViewState();
}

class _NumberBaseConverterViewState extends State<_NumberBaseConverterView> {
  final TextEditingController _base2 = TextEditingController();
  final TextEditingController _base8 = TextEditingController();
  final TextEditingController _base10 = TextEditingController();
  final TextEditingController _base16 = TextEditingController();
  final TextEditingController _custom = TextEditingController();
  String _customBase = '36';
  bool _updating = false;

  @override
  void dispose() {
    _base2.dispose();
    _base8.dispose();
    _base10.dispose();
    _base16.dispose();
    _custom.dispose();
    super.dispose();
  }

  void _updateFrom(int base, String text) {
    if (_updating) return;
    _updating = true;
    try {
      final value = int.parse(text, radix: base);
      _base2.text = value.toRadixString(2);
      _base8.text = value.toRadixString(8);
      _base10.text = value.toRadixString(10);
      _base16.text = value.toRadixString(16);
      final customBase = int.tryParse(_customBase) ?? 10;
      _custom.text = value.toRadixString(customBase);
    } catch (_) {}
    _updating = false;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your number in any of the text field. The other text fields will automatically calculated.',
            ),
            const SizedBox(height: 12),
            _BaseRow(
              label: 'Base 2 (Binary)',
              controller: _base2,
              onChanged: (value) => _updateFrom(2, value),
            ),
            _BaseRow(
              label: 'Base 8 (Octal)',
              controller: _base8,
              onChanged: (value) => _updateFrom(8, value),
            ),
            _BaseRow(
              label: 'Base 10 (Decimal)',
              controller: _base10,
              onChanged: (value) => _updateFrom(10, value),
            ),
            _BaseRow(
              label: 'Base 16 (Hex)',
              controller: _base16,
              onChanged: (value) => _updateFrom(16, value),
            ),
            _BaseRow(
              label: 'Select base:',
              trailing: SmallDropdown(
                items: const ['36', '32', '16', '10'],
                initialValue: _customBase,
                onChanged: (value) {
                  setState(() => _customBase = value);
                  _updateFrom(int.tryParse(_customBase) ?? 10, _custom.text);
                },
              ),
              actions: const ['Clipboard', 'Sample', 'Clear'],
              controller: _custom,
              onChanged: (value) =>
                  _updateFrom(int.tryParse(_customBase) ?? 10, value),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoremIpsumView extends StatefulWidget {
  const _LoremIpsumView();

  @override
  State<_LoremIpsumView> createState() => _LoremIpsumViewState();
}

class _LoremIpsumViewState extends State<_LoremIpsumView> {
  final TextEditingController _output = TextEditingController();
  String _count = 'x1';
  String _mode = 'Append';

  @override
  void dispose() {
    _output.dispose();
    super.dispose();
  }

  void _addText(String text) {
    final count = int.tryParse(_count.replaceAll('x', '')) ?? 1;
    final repeated = List<String>.filled(count, text).join('\n\n');
    if (_mode == 'Append' && _output.text.isNotEmpty) {
      _output.text = '${_output.text}\n$repeated';
    } else {
      _output.text = repeated;
    }
    setState(() {});
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 180,
          child: Column(
            children: [
              ToolButton(
                label: 'Paragraph',
                onPressed: () => _addText(_paragraph()),
              ),
              ToolButton(
                label: 'Sentence',
                onPressed: () => _addText('Lorem ipsum dolor sit amet.'),
              ),
              ToolButton(label: 'Word', onPressed: () => _addText('Lorem')),
              ToolButton(
                label: 'Title',
                onPressed: () => _addText('Lorem Ipsum Title'),
              ),
              ToolButton(
                label: 'First name',
                onPressed: () => _addText('Alex'),
              ),
              ToolButton(
                label: 'Last name',
                onPressed: () => _addText('Johnson'),
              ),
              ToolButton(
                label: 'Full name',
                onPressed: () => _addText('Alex Johnson'),
              ),
              ToolButton(
                label: 'Email',
                onPressed: () => _addText('hello@example.com'),
              ),
              ToolButton(
                label: 'URL',
                onPressed: () => _addText('https://example.com'),
              ),
              ToolButton(
                label: 'Short tweet',
                onPressed: () => _addText('Building tools offline.'),
              ),
              ToolButton(
                label: 'Long tweet',
                onPressed: () => _addText(
                  'DevUtils helps you with daily tasks, offline and fast.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  const Spacer(),
                  SmallDropdown(
                    items: const ['x1', 'x5', 'x10'],
                    initialValue: _count,
                    onChanged: (value) => setState(() => _count = value),
                  ),
                  const SizedBox(width: 8),
                  SmallDropdown(
                    items: const ['Append', 'Replace'],
                    initialValue: _mode,
                    onChanged: (value) => setState(() => _mode = value),
                  ),
                  const SizedBox(width: 8),
                  ToolButton(
                    label: 'Clear',
                    onPressed: () => setState(() => _output.clear()),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: EditorPane(
                  label: '',
                  actions: const [],
                  controller: _output,
                  placeholder: 'Lorem ipsum...',
                  copyAction: _copyOutput,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _paragraph() {
    return 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.';
  }
}

class _QrCodeView extends StatefulWidget {
  const _QrCodeView();

  @override
  State<_QrCodeView> createState() => _QrCodeViewState();
}

class _QrCodeViewState extends State<_QrCodeView> {
  final TextEditingController _content = TextEditingController();
  String _preview = 'QR Preview';

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  void _updatePreview() {
    setState(() {
      _preview = _content.text.isEmpty
          ? 'QR Preview'
          : 'QR Ready (${_content.text.length} chars)';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: EditorPane(
            label: 'Content',
            actions: [
              ToolButton(
                label: 'Clipboard',
                onPressed: () async {
                  final text = await _readClipboardText();
                  setState(() => _content.text = text);
                  _updatePreview();
                },
              ),
              ToolButton(
                label: 'Sample',
                onPressed: () {
                  setState(
                    () => _content.text = 'BEGIN:VCARD\nFN:DevUtils\nEND:VCARD',
                  );
                  _updatePreview();
                },
              ),
              ToolButton(
                label: 'Clear',
                onPressed: () {
                  setState(() => _content.clear());
                  _updatePreview();
                },
              ),
              const SmallDropdown(
                items: ['Select Template'],
                initialValue: 'Select Template',
              ),
            ],
            controller: _content,
            onChanged: (_) => _updatePreview(),
            placeholder: 'BEGIN:VCARD...',
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: const [
                  Text(
                    'Read QR Code:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  ToolButton(label: 'File...'),
                  ToolButton(label: 'Clipboard'),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  ToolButton(label: 'Add Watermark...'),
                  ToolButton(label: 'Add Icon...'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Stack(
                    children: [
                      Center(child: Text(_preview)),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.copy_all, size: 16),
                          tooltip: 'Copy image',
                          padding: const EdgeInsets.all(4),
                          splashRadius: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: const [
                  SmallDropdown(
                    items: [
                      'Error Correction: H (30%)',
                      'Error Correction: M (15%)',
                    ],
                    initialValue: 'Error Correction: H (30%)',
                  ),
                  ToolButton(label: 'Save'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StringInspectorView extends StatefulWidget {
  const _StringInspectorView();

  @override
  State<_StringInspectorView> createState() => _StringInspectorViewState();
}

class _StringInspectorViewState extends State<_StringInspectorView> {
  final TextEditingController _input = TextEditingController();
  bool _caseSensitive = true;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Map<String, int> _wordCounts(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => _caseSensitive ? word : word.toLowerCase());
    final counts = <String, int>{};
    for (final word in words) {
      counts[word] = (counts[word] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final text = _input.text;
    final chars = text.characters.length;
    final bytes = utf8.encode(text).length;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final lines = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    final counts = _wordCounts(text);

    return Column(
      children: [
        Expanded(
          child: EditorPane(
            label: 'Input',
            actions: [
              ToolButton(
                label: 'Clipboard',
                onPressed: () async {
                  final clip = await _readClipboardText();
                  setState(() => _input.text = clip);
                },
              ),
              ToolButton(
                label: 'Sample',
                onPressed: () {
                  setState(
                    () => _input.text =
                        'This is a special emoji 😀.\nAwesome, right?',
                  );
                },
              ),
              ToolButton(
                label: 'Clear',
                onPressed: () => setState(() => _input.clear()),
              ),
            ],
            controller: _input,
            onChanged: (_) => setState(() {}),
            placeholder: 'This is a special emoji...',
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Count'),
              Text('Characters $chars'),
              Text('Bytes $bytes'),
              Text('Words $words'),
              Text('Lines $lines'),
              const SizedBox(height: 8),
              const SectionHeader(title: 'Selection'),
              const Text('Location 0'),
              const Text('Current line 0'),
              const Text('Column 0'),
              const SizedBox(height: 12),
              const SectionHeader(title: 'Word distribution'),
              Row(
                children: [
                  const ToolButton(label: 'Filter'),
                  const SizedBox(width: 8),
                  Checkbox(
                    value: _caseSensitive,
                    onChanged: (value) =>
                        setState(() => _caseSensitive = value ?? true),
                  ),
                  const Text('Case sensitive'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: ListView(
                    children: counts.entries
                        .map((entry) => Text('${entry.key}: ${entry.value}'))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MarkdownPreviewView extends StatefulWidget {
  const _MarkdownPreviewView();

  @override
  State<_MarkdownPreviewView> createState() => _MarkdownPreviewViewState();
}

class _MarkdownPreviewViewState extends State<_MarkdownPreviewView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _preview = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _preview.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() {
      _input.text = text;
      _preview.text = text;
    });
  }

  void _setSample() {
    const sample = '# Heading 1\n\nParagraphs are separated by a blank line.';
    setState(() {
      _input.text = sample;
      _preview.text = sample;
    });
  }

  void _clear() {
    setState(() {
      _input.clear();
      _preview.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: EditorPane(
            label: 'Input',
            actions: [
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clear),
              const ToolButton(label: 'Cheatsheet'),
            ],
            controller: _input,
            onChanged: (value) => setState(() => _preview.text = value),
            placeholder: '# Heading 1',
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: EditorPane(
            label: 'Preview',
            actions: const [
              ToolButton(label: 'Open in Browser'),
              SmallDropdown(items: ['Preview'], initialValue: 'Preview'),
            ],
            readOnly: true,
            placeholder: '',
            controller: _preview,
          ),
        ),
      ],
    );
  }
}

class _SqlFormatterView extends StatefulWidget {
  const _SqlFormatterView();

  @override
  State<_SqlFormatterView> createState() => _SqlFormatterViewState();
}

class _SqlFormatterViewState extends State<_SqlFormatterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _mode = 'Format';
  String _case = 'Uppercase';
  String _indent = '2 spaces';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    if (_mode == 'SQL to English') {
      final explanation = _SqlExplainer().explain(_input.text);
      _output.text = _formatSqlExplanation(explanation);
      setState(() {});
      return;
    }
    var text = _input.text;
    final keywords = [
      'select',
      'from',
      'where',
      'join',
      'left',
      'right',
      'inner',
      'outer',
      'group',
      'order',
      'by',
      'limit',
    ];
    for (final word in keywords) {
      final reg = RegExp('\\b$word\\b', caseSensitive: false);
      text = text.replaceAllMapped(reg, (match) {
        final value = match.group(0)!;
        return _case == 'Uppercase' ? value.toUpperCase() : value.toLowerCase();
      });
    }
    final indent = _indentFor(_indent);
    text = text.replaceAll(
      RegExp(r'\\bSELECT\\b', caseSensitive: false),
      'SELECT',
    );
    final split = text.split(
      RegExp(r'\\s+(FROM|WHERE|GROUP|ORDER)\\s+', caseSensitive: false),
    );
    _output.text = split.map((line) => line.trim()).join('\n$indent');
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
            final text = await _readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = 'select * from users where id = 1');
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
        const SmallDropdown(
          items: ['General SQL'],
          initialValue: 'General SQL',
        ),
      ],
      outputActions: [
        SmallDropdown(
          items: const ['Format', 'SQL to English'],
          initialValue: _mode,
          onChanged: (value) {
            setState(() => _mode = value);
            _run();
          },
        ),
        if (_mode == 'Format')
          SmallDropdown(
            items: const ['Uppercase', 'Lowercase'],
            initialValue: _case,
            onChanged: (value) {
              setState(() => _case = value);
              _run();
            },
          ),
        if (_mode == 'Format')
          SmallDropdown(
            items: const ['2 spaces', '4 spaces', 'Tabs'],
            initialValue: _indent,
            onChanged: (value) => setState(() => _indent = value),
          ),
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
    );
  }
}

String _formatSqlExplanation(_SqlExplanation explanation) {
  final buffer = StringBuffer();
  buffer.writeln('SUMMARY:');
  buffer.writeln(explanation.summary);
  buffer.writeln();
  buffer.writeln('BREAKDOWN:');
  for (final component in explanation.breakdown) {
    buffer.writeln('  [${component.clause}] ${component.explanation}');
  }
  if (explanation.tables.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Tables: ${explanation.tables.join(", ")}');
  }
  if (explanation.columns.isNotEmpty) {
    buffer.writeln('Columns: ${explanation.columns.join(", ")}');
  }
  if (explanation.conditions.isNotEmpty) {
    buffer.writeln('Conditions: ${explanation.conditions.join("; ")}');
  }
  return buffer.toString().trimRight();
}

class _SqlExplanation {
  _SqlExplanation({
    required this.summary,
    required this.breakdown,
    required this.tables,
    required this.columns,
    required this.conditions,
    required this.queryType,
  });

  final String summary;
  final List<_SqlComponent> breakdown;
  final List<String> tables;
  final List<String> columns;
  final List<String> conditions;
  final _SqlQueryType queryType;
}

class _SqlComponent {
  _SqlComponent({required this.clause, required this.explanation});

  final String clause;
  final String explanation;
}

enum _SqlQueryType {
  select,
  insert,
  update,
  delete,
  create,
  alter,
  drop,
  unknown,
}

class _SqlExplainer {
  _SqlExplanation explain(String sql) {
    final normalized = _normalizeSql(sql);
    final type = _detectQueryType(normalized);
    switch (type) {
      case _SqlQueryType.select:
        return _explainSelect(normalized);
      case _SqlQueryType.insert:
        return _explainInsert(normalized);
      case _SqlQueryType.update:
        return _explainUpdate(normalized);
      case _SqlQueryType.delete:
        return _explainDelete(normalized);
      case _SqlQueryType.create:
        return _explainCreate(normalized);
      case _SqlQueryType.drop:
        return _explainDrop(normalized);
      case _SqlQueryType.alter:
        return _explainGeneric(normalized, type);
      case _SqlQueryType.unknown:
        return _explainGeneric(normalized, type);
    }
  }

  _SqlExplanation _explainSelect(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];
    final conditions = <String>[];
    final summaryParts = <String>[];

    final selectMatch = _firstMatch(
      sql,
      r'SELECT\s+(DISTINCT\s+)?(.+?)\s+FROM',
    );
    if (selectMatch != null) {
      final selectClause = selectMatch.group(0)!;
      final isDistinct = selectClause.toUpperCase().contains('DISTINCT');
      final colString = selectMatch.group(2)!.trim();
      if (colString == '*') {
        columns.add('all columns');
        components.add(
          _SqlComponent(
            clause: 'SELECT *',
            explanation: 'Retrieves all columns',
          ),
        );
      } else {
        columns.addAll(
          colString
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty),
        );
        final colDesc = columns.length > 3
            ? '${columns.length} columns'
            : columns.join(', ');
        components.add(
          _SqlComponent(clause: 'SELECT', explanation: 'Retrieves $colDesc'),
        );
      }
      if (isDistinct) {
        components.add(
          _SqlComponent(
            clause: 'DISTINCT',
            explanation: 'Removes duplicate rows from results',
          ),
        );
      }
    }

    final fromMatch = _firstMatch(
      sql,
      r'FROM\s+([\w\s,\.`"]+?)(?:\s+(?:WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|GROUP|ORDER|LIMIT|HAVING|UNION|$))',
    );
    if (fromMatch != null) {
      final tablesPart = fromMatch
          .group(1)!
          .replaceAll(
            RegExp(
              r'\s+(WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|GROUP|ORDER|LIMIT|HAVING|UNION).*',
            ),
            '',
          )
          .trim();
      final parsedTables = tablesPart
          .split(',')
          .map((item) => item.trim())
          .map((item) => item.split(' ').first)
          .where((item) => item.isNotEmpty)
          .toList();
      tables.addAll(parsedTables);
      if (parsedTables.isNotEmpty) {
        final tableDesc = parsedTables.length == 1
            ? "the '${parsedTables[0]}' table"
            : 'tables: ${parsedTables.join(', ')}';
        components.add(
          _SqlComponent(clause: 'FROM', explanation: 'From $tableDesc'),
        );
        summaryParts.add('from $tableDesc');
      }
    }

    const joinPattern =
        r'(LEFT\s+OUTER\s+|RIGHT\s+OUTER\s+|LEFT\s+|RIGHT\s+|INNER\s+|OUTER\s+|CROSS\s+)?JOIN\s+([\w\.`"]+)(?:\s+(?:AS\s+)?(\w+))?(?:\s+ON\s+(.+?))?(?=\s+(?:LEFT|RIGHT|INNER|OUTER|CROSS|JOIN|WHERE|GROUP|ORDER|LIMIT|HAVING|$))';
    for (final match in _allMatches(sql, joinPattern)) {
      final joinType = (match.group(1) ?? '').trim().toUpperCase();
      final joinTable = match.group(2) ?? '';
      final joinCondition = match.group(4) ?? '';
      if (joinTable.isEmpty) {
        continue;
      }
      tables.add(joinTable);
      final joinDesc = _describeJoin(joinType, joinTable, joinCondition);
      components.add(
        _SqlComponent(clause: '${joinType}JOIN', explanation: joinDesc),
      );
      summaryParts.add(joinDesc.toLowerCase());
    }

    final whereMatch = _firstMatch(
      sql,
      r'WHERE\s+(.+?)(?:\s+(?:GROUP|ORDER|LIMIT|HAVING|UNION|$))',
    );
    if (whereMatch != null) {
      final whereClause = whereMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(GROUP|ORDER|LIMIT|HAVING|UNION).*'), '')
          .trim();
      final explained = _explainConditions(whereClause);
      conditions.addAll(explained.map((item) => item.raw));
      components.add(
        _SqlComponent(
          clause: 'WHERE',
          explanation:
              'Filters results where: ${explained.map((item) => item.explanation).join('; ')}',
        ),
      );
      summaryParts.add(
        'filtered by ${conditions.length} condition${conditions.length == 1 ? '' : 's'}',
      );
    }

    final groupMatch = _firstMatch(
      sql,
      r'GROUP\s+BY\s+(.+?)(?:\s+(?:HAVING|ORDER|LIMIT|UNION|$))',
    );
    if (groupMatch != null) {
      final groupClause = groupMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(HAVING|ORDER|LIMIT|UNION).*'), '')
          .trim();
      final groupCols = groupClause
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (groupCols.isNotEmpty) {
        components.add(
          _SqlComponent(
            clause: 'GROUP BY',
            explanation: 'Groups results by ${groupCols.join(', ')}',
          ),
        );
        summaryParts.add('grouped by ${groupCols.join(', ')}');
      }
    }

    final havingMatch = _firstMatch(
      sql,
      r'HAVING\s+(.+?)(?:\s+(?:ORDER|LIMIT|UNION|$))',
    );
    if (havingMatch != null) {
      final havingClause = havingMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(ORDER|LIMIT|UNION).*'), '')
          .trim();
      if (havingClause.isNotEmpty) {
        components.add(
          _SqlComponent(
            clause: 'HAVING',
            explanation: 'Filters groups where: $havingClause',
          ),
        );
      }
    }

    final orderMatch = _firstMatch(
      sql,
      r'ORDER\s+BY\s+(.+?)(?:\s+(?:LIMIT|OFFSET|UNION|$))',
    );
    if (orderMatch != null) {
      final orderClause = orderMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(LIMIT|OFFSET|UNION).*'), '')
          .trim();
      if (orderClause.isNotEmpty) {
        final orderExplanation = _explainOrderBy(orderClause);
        components.add(
          _SqlComponent(clause: 'ORDER BY', explanation: orderExplanation),
        );
        summaryParts.add('sorted by $orderClause');
      }
    }

    final limitMatch = _firstMatch(sql, r'LIMIT\s+(\d+)(?:\s+OFFSET\s+(\d+))?');
    if (limitMatch != null) {
      final limitValue = int.tryParse(limitMatch.group(1) ?? '');
      final offsetValue = int.tryParse(limitMatch.group(2) ?? '');
      if (limitValue != null) {
        var limitExplanation =
            'Returns only the first $limitValue result${limitValue == 1 ? '' : 's'}';
        if (offsetValue != null) {
          limitExplanation += ', skipping the first $offsetValue';
        }
        components.add(
          _SqlComponent(clause: 'LIMIT', explanation: limitExplanation),
        );
        summaryParts.add('limited to $limitValue rows');
      }
    }

    final columnSummary = columns.firstOrNull == 'all columns'
        ? 'all columns'
        : '${columns.length} column${columns.length == 1 ? '' : 's'}';
    var summary = 'Retrieves $columnSummary';
    if (summaryParts.isNotEmpty) {
      summary = '$summary ${summaryParts.join(', ')}';
    }

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: conditions,
      queryType: _SqlQueryType.select,
    );
  }

  _SqlExplanation _explainInsert(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'INSERT\s+INTO\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tablePart = tableMatch.group(1)!;
      tables.add(tablePart);
      components.add(
        _SqlComponent(
          clause: 'INSERT INTO',
          explanation: "Adds new row(s) to the '$tablePart' table",
        ),
      );
    }

    final colMatch = _firstMatch(
      sql,
      r'\(([^)]+)\)\s*VALUES',
      caseInsensitive: true,
    );
    if (colMatch != null) {
      final colPart = colMatch.group(1)!;
      columns.addAll(
        colPart
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
      components.add(
        _SqlComponent(
          clause: 'COLUMNS',
          explanation: 'Sets values for: ${columns.join(', ')}',
        ),
      );
    }

    final valuesCount = RegExp(r'\)\s*,\s*\(').allMatches(sql).length + 1;
    components.add(
      _SqlComponent(
        clause: 'VALUES',
        explanation: 'Inserting $valuesCount row${valuesCount == 1 ? '' : 's'}',
      ),
    );

    if (sql.toUpperCase().contains('SELECT')) {
      components.add(
        _SqlComponent(
          clause: 'SELECT',
          explanation: 'Values come from a subquery',
        ),
      );
    }

    final summary =
        "Inserts $valuesCount row${valuesCount == 1 ? '' : 's'} into '${tables.firstOrNull ?? 'table'}' with ${columns.length} column${columns.length == 1 ? '' : 's'}";

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: const [],
      queryType: _SqlQueryType.insert,
    );
  }

  _SqlExplanation _explainUpdate(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];
    final conditions = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'UPDATE\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tablePart = tableMatch.group(1)!;
      tables.add(tablePart);
      components.add(
        _SqlComponent(
          clause: 'UPDATE',
          explanation: "Modifies rows in the '$tablePart' table",
        ),
      );
    }

    final setMatch = _firstMatch(
      sql,
      r'SET\s+(.+?)(?:\s+WHERE|$)',
      caseInsensitive: true,
    );
    if (setMatch != null) {
      final setPart = setMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+WHERE.*', caseSensitive: false), '')
          .trim();
      final assignments = setPart
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      columns.addAll(
        assignments
            .map((assignment) => assignment.split('=').first.trim())
            .where((value) => value.isNotEmpty),
      );

      final setExplanations = <String>[];
      for (final assignment in assignments) {
        final parts = assignment.split('=').map((part) => part.trim()).toList();
        if (parts.length == 2) {
          setExplanations.add("'${parts[0]}' to ${parts[1]}");
        }
      }
      components.add(
        _SqlComponent(
          clause: 'SET',
          explanation: 'Changes: ${setExplanations.join(', ')}',
        ),
      );
    }

    final whereMatch = _firstMatch(
      sql,
      r'WHERE\s+(.+?)$',
      caseInsensitive: true,
    );
    if (whereMatch != null) {
      final whereClause = whereMatch.group(1)!.trim();
      final explained = _explainConditions(whereClause);
      conditions.addAll(explained.map((item) => item.raw));
      components.add(
        _SqlComponent(
          clause: 'WHERE',
          explanation:
              'Only affects rows where: ${explained.map((item) => item.explanation).join('; ')}',
        ),
      );
    } else {
      components.add(
        _SqlComponent(
          clause: 'WARNING',
          explanation: 'No WHERE clause - this will update ALL rows.',
        ),
      );
    }

    final summary =
        "Updates ${columns.length} column${columns.length == 1 ? '' : 's'} in '${tables.firstOrNull ?? 'table'}'"
        '${conditions.isEmpty ? ' (ALL ROWS)' : ' with ${conditions.length} filter condition${conditions.length == 1 ? '' : 's'}'}';

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: conditions,
      queryType: _SqlQueryType.update,
    );
  }

  _SqlExplanation _explainDelete(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final conditions = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'DELETE\s+FROM\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tablePart = tableMatch.group(1)!;
      tables.add(tablePart);
      components.add(
        _SqlComponent(
          clause: 'DELETE FROM',
          explanation: "Removes rows from the '$tablePart' table",
        ),
      );
    }

    final whereMatch = _firstMatch(
      sql,
      r'WHERE\s+(.+?)$',
      caseInsensitive: true,
    );
    if (whereMatch != null) {
      final whereClause = whereMatch.group(1)!.trim();
      final explained = _explainConditions(whereClause);
      conditions.addAll(explained.map((item) => item.raw));
      components.add(
        _SqlComponent(
          clause: 'WHERE',
          explanation:
              'Only deletes rows where: ${explained.map((item) => item.explanation).join('; ')}',
        ),
      );
    } else {
      components.add(
        _SqlComponent(
          clause: 'WARNING',
          explanation: 'No WHERE clause - this will delete ALL rows.',
        ),
      );
    }

    final summary =
        "Deletes rows from '${tables.firstOrNull ?? 'table'}'"
        '${conditions.isEmpty ? ' (ALL ROWS)' : ' where ${conditions.length} condition${conditions.length == 1 ? '' : 's'} match'}';

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: const [],
      conditions: conditions,
      queryType: _SqlQueryType.delete,
    );
  }

  _SqlExplanation _explainCreate(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tableName = tableMatch.group(2)!;
      tables.add(tableName);
      final ifNotExists = tableMatch.group(1) != null;
      var explanation = "Creates a new table called '$tableName'";
      if (ifNotExists) {
        explanation += ' (only if it does not already exist)';
      }
      components.add(
        _SqlComponent(clause: 'CREATE TABLE', explanation: explanation),
      );

      final colSection = _firstMatch(sql, r'\((.+)\)', caseInsensitive: true);
      if (colSection != null) {
        final colPart = colSection.group(1) ?? '';
        final colDefs = _splitColumnDefinitions(colPart);
        for (final def in colDefs) {
          final explained = _explainColumnDefinition(def);
          columns.add(explained.name);
          components.add(
            _SqlComponent(clause: 'COLUMN', explanation: explained.explanation),
          );
        }
      }
    }

    final indexMatch = _firstMatch(
      sql,
      r'CREATE\s+(UNIQUE\s+)?INDEX\s+([\w\.`"]+)\s+ON\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (indexMatch != null) {
      final isUnique = indexMatch.group(1) != null;
      components.add(
        _SqlComponent(
          clause: 'CREATE INDEX',
          explanation:
              'Creates a${isUnique ? ' unique' : 'n'} index for faster lookups',
        ),
      );
    }

    final summary =
        "Creates table '${tables.firstOrNull ?? ''}' with ${columns.length} column${columns.length == 1 ? '' : 's'}";
    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: const [],
      queryType: _SqlQueryType.create,
    );
  }

  _SqlExplanation _explainDrop(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];

    final dropMatch = _firstMatch(
      sql,
      r'DROP\s+(TABLE|INDEX|DATABASE)\s+(IF\s+EXISTS\s+)?([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (dropMatch != null) {
      final objectType = dropMatch.group(1)!.toUpperCase();
      final objectName = dropMatch.group(3)!;
      final ifExists = dropMatch.group(2) != null;
      tables.add(objectName);
      var explanation =
          'Permanently deletes the ${objectType.toLowerCase()} \'$objectName\'';
      if (ifExists) {
        explanation += ' (only if it exists)';
      }
      components.add(_SqlComponent(clause: 'DROP', explanation: explanation));
    }

    return _SqlExplanation(
      summary:
          "Drops (deletes) '${tables.firstOrNull ?? 'object'}' permanently",
      breakdown: components,
      tables: tables,
      columns: const [],
      conditions: const [],
      queryType: _SqlQueryType.drop,
    );
  }

  _SqlExplanation _explainGeneric(String sql, _SqlQueryType type) {
    return _SqlExplanation(
      summary: 'Executes a ${type.name.toUpperCase()} statement',
      breakdown: [
        _SqlComponent(
          clause: type.name.toUpperCase(),
          explanation: 'Unable to parse detailed structure',
        ),
      ],
      tables: const [],
      columns: const [],
      conditions: const [],
      queryType: type,
    );
  }

  String _normalizeSql(String sql) {
    var result = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    result = result.replaceAll(RegExp(r'--.*?(?=\n|$)'), '');
    result = result.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    return result;
  }

  _SqlQueryType _detectQueryType(String sql) {
    final upper = sql.trim().toUpperCase();
    if (upper.startsWith('SELECT')) return _SqlQueryType.select;
    if (upper.startsWith('INSERT')) return _SqlQueryType.insert;
    if (upper.startsWith('UPDATE')) return _SqlQueryType.update;
    if (upper.startsWith('DELETE')) return _SqlQueryType.delete;
    if (upper.startsWith('CREATE')) return _SqlQueryType.create;
    if (upper.startsWith('ALTER')) return _SqlQueryType.alter;
    if (upper.startsWith('DROP')) return _SqlQueryType.drop;
    return _SqlQueryType.unknown;
  }

  String _describeJoin(String type, String table, String condition) {
    String desc;
    switch (type.trim()) {
      case 'LEFT':
      case 'LEFT OUTER':
        desc =
            "Includes all rows from the left table, plus matching rows from '$table'";
        break;
      case 'RIGHT':
      case 'RIGHT OUTER':
        desc =
            "Includes all rows from '$table', plus matching rows from the left table";
        break;
      case 'OUTER':
      case 'FULL OUTER':
        desc = 'Includes all rows from both tables, matching where possible';
        break;
      case 'CROSS':
        desc =
            "Combines every row with every row from '$table' (cartesian product)";
        break;
      default:
        desc = "Combines with '$table' where matches exist";
    }
    if (condition.isNotEmpty) {
      desc += ' on $condition';
    }
    return desc;
  }

  List<_SqlCondition> _explainConditions(String whereClause) {
    final parts = whereClause
        .replaceAll(RegExp(r'\s+AND\s+', caseSensitive: false), '§AND§')
        .replaceAll(RegExp(r'\s+OR\s+', caseSensitive: false), '§OR§')
        .split('§')
        .where((item) => item.isNotEmpty)
        .toList();
    final explained = <_SqlCondition>[];
    for (final part in parts) {
      if (part == 'AND' || part == 'OR') {
        continue;
      }
      explained.add(
        _SqlCondition(
          raw: part.trim(),
          explanation: _explainSingleCondition(part),
        ),
      );
    }
    return explained;
  }

  String _explainSingleCondition(String condition) {
    final cond = condition.trim();
    final upper = cond.toUpperCase();
    if (upper.contains(' IS NULL')) {
      final col = cond.replaceAll(
        RegExp(r'\s+IS\s+NULL', caseSensitive: false),
        '',
      );
      return "'$col' has no value";
    }
    if (upper.contains(' IS NOT NULL')) {
      final col = cond.replaceAll(
        RegExp(r'\s+IS\s+NOT\s+NULL', caseSensitive: false),
        '',
      );
      return "'$col' has a value";
    }
    if (upper.contains(' IN ')) {
      final match = _firstMatch(
        cond,
        r'(.+?)\s+IN\s*\((.+?)\)',
        caseInsensitive: true,
      );
      if (match != null) {
        final parts = match
            .group(0)!
            .split(RegExp(r'\s+IN\s+', caseSensitive: false));
        if (parts.length == 2) {
          return "'${parts[0]}' is one of ${parts[1]}";
        }
      }
    }
    if (upper.contains(' LIKE ')) {
      final parts = cond
          .split(RegExp(r'\s+LIKE\s+', caseSensitive: false))
          .map((item) => item.trim())
          .toList();
      if (parts.length == 2) {
        final pattern = parts[1].replaceAll("'", '');
        if (pattern.startsWith('%') && pattern.endsWith('%')) {
          final text = pattern.replaceAll('%', '');
          return "'${parts[0]}' contains '$text'";
        }
        if (pattern.startsWith('%')) {
          final text = pattern.replaceAll('%', '');
          return "'${parts[0]}' ends with '$text'";
        }
        if (pattern.endsWith('%')) {
          final text = pattern.replaceAll('%', '');
          return "'${parts[0]}' starts with '$text'";
        }
        return "'${parts[0]}' matches pattern '$pattern'";
      }
    }
    if (upper.contains(' BETWEEN ')) {
      final match = _firstMatch(
        cond,
        r'(.+?)\s+BETWEEN\s+(.+?)\s+AND\s+(.+)',
        caseInsensitive: true,
      );
      if (match != null) {
        final col = match.group(1)!.trim();
        final low = match.group(2)!.trim();
        final high = match.group(3)!.trim();
        return "'$col' is between $low and $high";
      }
    }
    const operators = [
      ['>=', 'is greater than or equal to'],
      ['<=', 'is less than or equal to'],
      ['<>', 'is not equal to'],
      ['!=', 'is not equal to'],
      ['=', 'equals'],
      ['>', 'is greater than'],
      ['<', 'is less than'],
    ];
    for (final entry in operators) {
      final op = entry[0];
      final desc = entry[1];
      if (cond.contains(op)) {
        final parts = cond.split(op).map((item) => item.trim()).toList();
        if (parts.length == 2) {
          return "'${parts[0]}' $desc ${parts[1]}";
        }
      }
    }
    return cond;
  }

  String _explainOrderBy(String clause) {
    final parts = clause
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final explanations = <String>[];
    for (final part in parts) {
      final upper = part.toUpperCase();
      final col = part
          .replaceAll(RegExp(r'\s+(ASC|DESC)$', caseSensitive: false), '')
          .trim();
      if (upper.endsWith('DESC')) {
        explanations.add("'$col' descending (Z->A, 9->0)");
      } else {
        explanations.add("'$col' ascending (A->Z, 0->9)");
      }
    }
    return 'Sorts by ${explanations.join(', then by ')}';
  }

  List<String> _splitColumnDefinitions(String section) {
    final definitions = <String>[];
    var current = StringBuffer();
    var parenDepth = 0;
    for (final char in section.split('')) {
      if (char == '(') {
        parenDepth += 1;
      } else if (char == ')') {
        parenDepth = parenDepth > 0 ? parenDepth - 1 : 0;
      }
      if (char == ',' && parenDepth == 0) {
        final value = current.toString().trim();
        if (value.isNotEmpty) {
          definitions.add(value);
        }
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    final tail = current.toString().trim();
    if (tail.isNotEmpty) {
      definitions.add(tail);
    }
    return definitions;
  }

  _SqlColumnExplanation _explainColumnDefinition(String definition) {
    final parts = definition
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return _SqlColumnExplanation(name: '', explanation: definition);
    }
    final upperDef = definition.toUpperCase();
    if (upperDef.startsWith('PRIMARY KEY') ||
        upperDef.startsWith('FOREIGN KEY') ||
        upperDef.startsWith('UNIQUE') ||
        upperDef.startsWith('CHECK') ||
        upperDef.startsWith('CONSTRAINT')) {
      return _SqlColumnExplanation(
        name: 'constraint',
        explanation: _explainConstraint(definition),
      );
    }
    final name = parts[0];
    final type = parts.length > 1 ? parts[1] : 'unknown';
    final attributes = <String>[];
    if (upperDef.contains('PRIMARY KEY')) attributes.add('primary key');
    if (upperDef.contains('NOT NULL')) attributes.add('required');
    if (upperDef.contains('UNIQUE')) attributes.add('unique');
    if (upperDef.contains('AUTO_INCREMENT') ||
        upperDef.contains('AUTOINCREMENT')) {
      attributes.add('auto-generated');
    }
    if (upperDef.contains('DEFAULT')) attributes.add('has default value');
    if (upperDef.contains('REFERENCES')) attributes.add('foreign key');
    var explanation = "'$name' (${_describeDataType(type)}";
    if (attributes.isNotEmpty) {
      explanation += ', ${attributes.join(', ')}';
    }
    explanation += ')';
    return _SqlColumnExplanation(name: name, explanation: explanation);
  }

  String _describeDataType(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('INT')) return 'whole number';
    if (upper.contains('VARCHAR') || upper.contains('CHAR')) return 'text';
    if (upper.contains('TEXT')) return 'long text';
    if (upper.contains('DECIMAL') ||
        upper.contains('NUMERIC') ||
        upper.contains('FLOAT') ||
        upper.contains('DOUBLE')) {
      return 'decimal number';
    }
    if (upper.contains('BOOL')) return 'true/false';
    if (upper.contains('DATE') && upper.contains('TIME')) {
      return 'date and time';
    }
    if (upper.contains('DATE')) return 'date';
    if (upper.contains('TIME')) return 'time';
    if (upper.contains('BLOB') || upper.contains('BINARY')) {
      return 'binary data';
    }
    if (upper.contains('JSON')) return 'JSON data';
    if (upper.contains('UUID')) return 'unique identifier';
    return type.toLowerCase();
  }

  String _explainConstraint(String definition) {
    final upper = definition.toUpperCase();
    if (upper.contains('PRIMARY KEY')) {
      return 'Primary key constraint - uniquely identifies each row';
    }
    if (upper.contains('FOREIGN KEY')) {
      final refMatch = _firstMatch(
        definition,
        r'REFERENCES\s+([\w\.]+)',
        caseInsensitive: true,
      );
      if (refMatch != null) {
        final refTable = refMatch.group(1) ?? '';
        return "Foreign key - links to '$refTable'";
      }
      return 'Foreign key constraint - links to another table';
    }
    if (upper.contains('UNIQUE')) {
      return 'Unique constraint - no duplicate values allowed';
    }
    if (upper.contains('CHECK')) {
      return 'Check constraint - validates data before insert/update';
    }
    return definition;
  }

  RegExpMatch? _firstMatch(
    String input,
    String pattern, {
    bool caseInsensitive = true,
  }) {
    return RegExp(
      pattern,
      caseSensitive: !caseInsensitive,
      dotAll: true,
    ).firstMatch(input);
  }

  Iterable<RegExpMatch> _allMatches(String input, String pattern) {
    return RegExp(
      pattern,
      caseSensitive: false,
      dotAll: true,
    ).allMatches(input);
  }
}

class _SqlCondition {
  _SqlCondition({required this.raw, required this.explanation});

  final String raw;
  final String explanation;
}

class _SqlColumnExplanation {
  _SqlColumnExplanation({required this.name, required this.explanation});

  final String name;
  final String explanation;
}

extension _FirstOrNullExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _StringCaseConverterView extends StatefulWidget {
  const _StringCaseConverterView();

  @override
  State<_StringCaseConverterView> createState() =>
      _StringCaseConverterViewState();
}

class _StringCaseConverterViewState extends State<_StringCaseConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _mode = 'camelCase';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final lines = _input.text.split('\n');
    final converted = lines.map(_convert).join('\n');
    _output.text = converted;
    setState(() {});
  }

  String _convert(String input) {
    final words = input
        .replaceAll(RegExp(r'[_\-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    if (_mode == 'snake_case') {
      return words.map((w) => w.toLowerCase()).join('_');
    }
    if (_mode == 'kebab-case') {
      return words.map((w) => w.toLowerCase()).join('-');
    }
    final first = words.first.toLowerCase();
    final rest = words
        .skip(1)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase());
    return ([first, ...rest]).join();
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(
          label: 'Clipboard',
          onPressed: () async {
            final text = await _readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = 'requestURLDecoderID');
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
        const ToolIconButton(icon: Icons.settings),
      ],
      outputActions: [
        SmallDropdown(
          items: const ['camelCase', 'snake_case', 'kebab-case'],
          initialValue: _mode,
          onChanged: (value) {
            setState(() => _mode = value);
            _run();
          },
        ),
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
    );
  }
}

class _CronJobParserView extends StatefulWidget {
  const _CronJobParserView();

  @override
  State<_CronJobParserView> createState() => _CronJobParserViewState();
}

class _CronJobParserViewState extends State<_CronJobParserView> {
  final TextEditingController _input = TextEditingController(
    text: '*/5 * * * *',
  );
  String _summary = 'Every 5 minutes';
  String _minutes = '';
  List<String> _next = [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  void _parse() {
    final parts = _input.text.trim().split(RegExp(r'\s+'));
    if (parts.length < 5) {
      setState(() {
        _summary = 'Invalid cron expression';
        _minutes = '';
        _next = [];
      });
      return;
    }
    final minute = parts[0];
    if (minute.startsWith('*/')) {
      final step = int.tryParse(minute.substring(2)) ?? 1;
      _summary = 'Every $step minutes';
      final mins = <String>[];
      for (var m = 0; m < 60; m += step) {
        mins.add(m.toString().padLeft(2, '0'));
      }
      _minutes = mins.join(', ');
      _next = _nextExecutions(step);
    } else if (minute == '*') {
      _summary = 'Every minute';
      _minutes = '(All)';
      _next = _nextExecutions(1);
    } else {
      _summary = 'At minute $minute';
      _minutes = minute;
      final step = int.tryParse(minute) ?? 0;
      _next = step >= 0 ? _nextExecutions(60) : [];
    }
    setState(() {});
  }

  List<String> _nextExecutions(int stepMinutes) {
    final now = DateTime.now();
    final list = <String>[];
    var current = now.add(
      Duration(minutes: stepMinutes - (now.minute % stepMinutes)),
    );
    for (var i = 0; i < 5; i++) {
      list.add(current.toString());
      current = current.add(Duration(minutes: stepMinutes));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ToolButton(
                  label: 'Clipboard',
                  onPressed: () async {
                    final text = await _readClipboardText();
                    setState(() => _input.text = text);
                    _parse();
                  },
                ),
                const SizedBox(width: 8),
                ToolButton(
                  label: 'Sample',
                  onPressed: () {
                    setState(() => _input.text = '*/5 * * * *');
                    _parse();
                  },
                ),
                const SizedBox(width: 8),
                ToolButton(
                  label: 'Clear',
                  onPressed: () {
                    setState(() => _input.clear());
                    _parse();
                  },
                ),
                const SizedBox(width: 8),
                ToolButton(
                  label: 'Copy',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _input.text)),
                ),
                const Spacer(),
                const SmallDropdown(
                  items: ['Pick an example...'],
                  initialValue: 'Pick an example...',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InlineTextField(
              hintText: '*/5 * * * *',
              controller: _input,
              onChanged: (_) => _parse(),
            ),
            const SizedBox(height: 12),
            Text(_summary),
            const SizedBox(height: 12),
            Text('Minutes: $_minutes'),
            const Text('Hours: (All)'),
            const Text('Day of Month: (All)'),
            const Text('Months: (All)'),
            const Text('Day of Week: (All)'),
            const SizedBox(height: 12),
            const Text('Next executions:'),
            for (final item in _next) Text(item),
          ],
        ),
      ),
    );
  }
}

class _ColorConverterView extends StatefulWidget {
  const _ColorConverterView();

  @override
  State<_ColorConverterView> createState() => _ColorConverterViewState();
}

class _ColorConverterViewState extends State<_ColorConverterView> {
  final TextEditingController _input = TextEditingController(text: '#5CC07F');
  final TextEditingController _hex = TextEditingController();
  final TextEditingController _hexAlpha = TextEditingController();
  final TextEditingController _rgb = TextEditingController();
  final TextEditingController _rgba = TextEditingController();
  final TextEditingController _hsl = TextEditingController();
  final TextEditingController _hsla = TextEditingController();
  final TextEditingController _hsv = TextEditingController();
  final TextEditingController _hwb = TextEditingController();
  final TextEditingController _cmyk = TextEditingController();
  Color _color = const Color(0xFF5CC07F);

  @override
  void initState() {
    super.initState();
    _updateFromHex(_input.text);
  }

  void _updateFromHex(String text) {
    final hex = text.replaceAll('#', '');
    if (hex.length != 6 && hex.length != 8) return;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return;
    final color = hex.length == 6 ? Color(0xFF000000 | value) : Color(value);
    _color = color;
    _fillFields(color);
    setState(() {});
  }

  void _fillFields(Color color) {
    final r = _colorComponent(color.r);
    final g = _colorComponent(color.g);
    final b = _colorComponent(color.b);
    final alpha = _colorComponent(color.a);
    final a = alpha / 255;
    _hex.text = '#${_bytesToHex([r, g, b], lower: true)}';
    _hexAlpha.text = '#${_bytesToHex([r, g, b, alpha], lower: true)}';
    _rgb.text = 'rgb($r, $g, $b)';
    _rgba.text = 'rgba($r, $g, $b, ${a.toStringAsFixed(2)})';
    final hsl = _rgbToHsl(r, g, b);
    _hsl.text = 'hsl(${hsl[0]}deg, ${hsl[1]}%, ${hsl[2]}%)';
    _hsla.text =
        'hsla(${hsl[0]}deg, ${hsl[1]}%, ${hsl[2]}%, ${a.toStringAsFixed(2)})';
    final hsv = _rgbToHsv(r, g, b);
    _hsv.text = 'hsb(${hsv[0]}deg, ${hsv[1]}%, ${hsv[2]}%)';
    _hwb.text = 'hwb(${hsv[0]}deg, ${hsv[1]}%, ${100 - hsv[1]}%)';
    final cmyk = _rgbToCmyk(r, g, b);
    _cmyk.text = 'cmyk(${cmyk[0]}%, ${cmyk[1]}%, ${cmyk[2]}%, ${cmyk[3]}%)';
  }

  List<int> _rgbToHsl(int r, int g, int b) {
    final rf = r / 255;
    final gf = g / 255;
    final bf = b / 255;
    final max = [rf, gf, bf].reduce(maxOf);
    final min = [rf, gf, bf].reduce(minOf);
    var h = 0.0;
    var s = 0.0;
    final l = (max + min) / 2;
    if (max != min) {
      final d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      if (max == rf) {
        h = (gf - bf) / d + (gf < bf ? 6 : 0);
      } else if (max == gf) {
        h = (bf - rf) / d + 2;
      } else {
        h = (rf - gf) / d + 4;
      }
      h /= 6;
    }
    return [(h * 360).round(), (s * 100).round(), (l * 100).round()];
  }

  List<int> _rgbToHsv(int r, int g, int b) {
    final rf = r / 255;
    final gf = g / 255;
    final bf = b / 255;
    final max = [rf, gf, bf].reduce(maxOf);
    final min = [rf, gf, bf].reduce(minOf);
    final d = max - min;
    var h = 0.0;
    final s = max == 0 ? 0 : d / max;
    if (max != min) {
      if (max == rf) {
        h = (gf - bf) / d + (gf < bf ? 6 : 0);
      } else if (max == gf) {
        h = (bf - rf) / d + 2;
      } else {
        h = (rf - gf) / d + 4;
      }
      h /= 6;
    }
    return [(h * 360).round(), (s * 100).round(), (max * 100).round()];
  }

  List<int> _rgbToCmyk(int r, int g, int b) {
    final rf = r / 255;
    final gf = g / 255;
    final bf = b / 255;
    final k = 1 - [rf, gf, bf].reduce(maxOf);
    if (k == 1) return [0, 0, 0, 100];
    final c = (1 - rf - k) / (1 - k);
    final m = (1 - gf - k) / (1 - k);
    final y = (1 - bf - k) / (1 - k);
    return [
      (c * 100).round(),
      (m * 100).round(),
      (y * 100).round(),
      (k * 100).round(),
    ];
  }

  double maxOf(double a, double b) => a > b ? a : b;
  double minOf(double a, double b) => a < b ? a : b;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Input:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      ToolButton(
                        label: 'Clipboard',
                        onPressed: () async {
                          final text = await _readClipboardText();
                          setState(() => _input.text = text);
                          _updateFromHex(text);
                        },
                      ),
                      ToolButton(
                        label: 'Sample',
                        onPressed: () {
                          setState(() => _input.text = '#5CC07F');
                          _updateFromHex(_input.text);
                        },
                      ),
                      ToolButton(
                        label: 'Clear',
                        onPressed: () => setState(() => _input.clear()),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: _color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InlineTextField(
                    hintText: '#5CC07F',
                    controller: _input,
                    onChanged: (value) => _updateFromHex(value),
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Hex',
                    trailing: ToolIconButton(
                      icon: Icons.copy,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _hex.text)),
                    ),
                    controller: _hex,
                    readOnly: true,
                  ),
                  LabeledField(
                    label: 'Hex with alpha',
                    trailing: ToolIconButton(
                      icon: Icons.copy,
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: _hexAlpha.text),
                      ),
                    ),
                    controller: _hexAlpha,
                    readOnly: true,
                  ),
                  LabeledField(
                    label: 'RGB',
                    trailing: ToolIconButton(
                      icon: Icons.copy,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _rgb.text)),
                    ),
                    controller: _rgb,
                    readOnly: true,
                  ),
                  LabeledField(
                    label: 'RGBA',
                    trailing: ToolIconButton(
                      icon: Icons.copy,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _rgba.text)),
                    ),
                    controller: _rgba,
                    readOnly: true,
                  ),
                  LabeledField(
                    label: 'HSL',
                    trailing: ToolIconButton(
                      icon: Icons.copy,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _hsl.text)),
                    ),
                    controller: _hsl,
                    readOnly: true,
                  ),
                  LabeledField(
                    label: 'HSLA',
                    trailing: ToolIconButton(
                      icon: Icons.copy,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _hsla.text)),
                    ),
                    controller: _hsla,
                    readOnly: true,
                  ),
                  LabeledField(
                    label: 'HSB (HSV)',
                    trailing: ToolIconButton(
                      icon: Icons.copy,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _hsv.text)),
                    ),
                    controller: _hsv,
                    readOnly: true,
                  ),
                  LabeledField(
                    label: 'HWB',
                    trailing: ToolIconButton(
                      icon: Icons.copy,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _hwb.text)),
                    ),
                    controller: _hwb,
                    readOnly: true,
                  ),
                  LabeledField(
                    label: 'CMYK',
                    trailing: ToolIconButton(
                      icon: Icons.copy,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _cmyk.text)),
                    ),
                    controller: _cmyk,
                    readOnly: true,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  ToolButton(label: 'Code Presets'),
                  SizedBox(width: 8),
                  ToolButton(label: 'View Source'),
                  SizedBox(width: 8),
                  ToolButton(label: 'Variables'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '# CSS Level 4 Color Module:\n${_rgb.text}\n${_hsl.text}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RandomStringGeneratorView extends StatefulWidget {
  const _RandomStringGeneratorView();

  @override
  State<_RandomStringGeneratorView> createState() =>
      _RandomStringGeneratorViewState();
}

class _RandomStringGeneratorViewState
    extends State<_RandomStringGeneratorView> {
  final TextEditingController _seed = TextEditingController(
    text: '904731371168665084',
  );
  final TextEditingController _upper = TextEditingController(text: '18');
  final TextEditingController _lower = TextEditingController(text: '18');
  final TextEditingController _symbols = TextEditingController(text: '2');
  final TextEditingController _digits = TextEditingController(text: '8');
  final TextEditingController _words = TextEditingController(text: '0');
  final TextEditingController _output = TextEditingController();
  String _count = 'x10';

  @override
  void dispose() {
    _seed.dispose();
    _upper.dispose();
    _lower.dispose();
    _symbols.dispose();
    _digits.dispose();
    _words.dispose();
    _output.dispose();
    super.dispose();
  }

  void _generate() {
    final rand = Random();
    final uppers = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final lowers = 'abcdefghijklmnopqrstuvwxyz';
    final symbols = '!@#\$%^&*';
    final digits = '0123456789';
    final upCount = int.tryParse(_upper.text) ?? 0;
    final lowCount = int.tryParse(_lower.text) ?? 0;
    final symCount = int.tryParse(_symbols.text) ?? 0;
    final digCount = int.tryParse(_digits.text) ?? 0;
    final totalCount = (int.tryParse(_count.replaceAll('x', '')) ?? 10);
    final lines = <String>[];
    for (var i = 0; i < totalCount; i++) {
      final buffer = StringBuffer();
      for (var j = 0; j < upCount; j++) {
        buffer.write(uppers[rand.nextInt(uppers.length)]);
      }
      for (var j = 0; j < lowCount; j++) {
        buffer.write(lowers[rand.nextInt(lowers.length)]);
      }
      for (var j = 0; j < symCount; j++) {
        buffer.write(symbols[rand.nextInt(symbols.length)]);
      }
      for (var j = 0; j < digCount; j++) {
        buffer.write(digits[rand.nextInt(digits.length)]);
      }
      lines.add(buffer.toString());
    }
    _output.text = lines.join('\n');
    setState(() {});
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Presets:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const SmallDropdown(
                        items: ['(Click to Select)'],
                        initialValue: '(Click to Select)',
                      ),
                      const SizedBox(width: 8),
                      ToolButton(label: 'Sample', onPressed: _generate),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LabeledField(label: 'Seed', controller: _seed),
                  LabeledField(
                    label: 'Uppercased Characters',
                    controller: _upper,
                  ),
                  LabeledField(
                    label: 'Lowercased Characters',
                    controller: _lower,
                  ),
                  LabeledField(label: 'Symbols', controller: _symbols),
                  LabeledField(label: 'Digits', controller: _digits),
                  LabeledField(label: 'Words', controller: _words),
                  const LabeledField(label: 'Separator'),
                  const LabeledField(label: 'Separating Group Size'),
                  const LabeledField(label: 'Custom Character Set'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Checkbox(value: true, onChanged: null),
                  const Text('Colors'),
                  const Spacer(),
                  SmallDropdown(
                    items: const ['x10', 'x20'],
                    initialValue: _count,
                    onChanged: (value) => setState(() => _count = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: EditorPane(
                  label: '',
                  actions: const [],
                  controller: _output,
                  readOnly: true,
                  placeholder: 'Generated strings...',
                  copyAction: _copyOutput,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SvgToCssView extends StatefulWidget {
  const _SvgToCssView();

  @override
  State<_SvgToCssView> createState() => _SvgToCssViewState();
}

class _SvgToCssViewState extends State<_SvgToCssView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _format = 'URL Encoded';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final svg = _input.text.trim();
    if (svg.isEmpty) {
      _output.clear();
      setState(() {});
      return;
    }
    final data = _format == 'URL Encoded' ? Uri.encodeComponent(svg) : svg;
    _output.text = "background-image: url('data:image/svg+xml,$data');";
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(
                label: 'Clipboard',
                onPressed: () async {
                  final text = await _readClipboardText();
                  setState(() => _input.text = text);
                  _run();
                },
              ),
              ToolButton(
                label: 'Sample',
                onPressed: () {
                  setState(
                    () => _input.text =
                        '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
                  );
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
              SmallDropdown(
                items: const ['URL Encoded', 'Raw'],
                initialValue: _format,
                onChanged: (value) {
                  setState(() => _format = value);
                  _run();
                },
              ),
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            inputController: _input,
            outputController: _output,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('Preview')),
          ),
        ),
      ],
    );
  }
}

class _CurlToCodeView extends StatefulWidget {
  const _CurlToCodeView();

  @override
  State<_CurlToCodeView> createState() => _CurlToCodeViewState();
}

class _CurlToCodeViewState extends State<_CurlToCodeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _lang = 'NodeJS / Fetch';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final url = _extractUrl(_input.text);
    if (url == null) {
      _output.text = '';
      setState(() {});
      return;
    }
    _output.text = _codeFor(url, _lang);
    setState(() {});
  }

  String? _extractUrl(String text) {
    final match = RegExp("curl\\s+['\\\"]?([^'\\\"\\s]+)").firstMatch(text);
    return match?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(
          label: 'Clipboard',
          onPressed: () async {
            final text = await _readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = "curl 'https://devutils.com/'");
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
        SmallDropdown(
          items: const [
            'NodeJS / Fetch',
            'JavaScript / axios',
            'JavaScript / node:http',
            'Python / Requests',
            'PHP / cURL',
            'PHP / Guzzle',
            'Go / net/http',
            'Rust / reqwest',
            'C# / HttpClient',
            'Java / HttpClient',
            'Ruby / Net::HTTP',
            'Ruby / Faraday',
            'Swift / URLSession',
            'Dart / http',
            'Dart / dio',
            'wget',
          ],
          initialValue: _lang,
          onChanged: (value) {
            setState(() => _lang = value);
            _run();
          },
        ),
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
    );
  }

  String _codeFor(String url, String language) {
    if (language == 'wget') {
      return "wget '$url'";
    }
    if (language == 'NodeJS / Fetch') {
      return "fetch('$url')\n  .then(res => res.text())\n  .then(console.log);";
    }
    if (language == 'JavaScript / axios') {
      return "import axios from 'axios';\n\naxios.get('$url')\n  .then(res => console.log(res.data))\n  .catch(console.error);";
    }
    if (language == 'JavaScript / node:http') {
      final isHttps = url.startsWith('https');
      final module = isHttps ? 'https' : 'http';
      return "const $module = require('$module');\n\n$module.get('$url', res => {\n  let data = '';\n  res.on('data', chunk => data += chunk);\n  res.on('end', () => console.log(data));\n}).on('error', console.error);";
    }
    if (language == 'Python / Requests') {
      return "import requests\n\nresponse = requests.get('$url')\nprint(response.text)";
    }
    if (language == 'PHP / cURL') {
      return "<?php\n\$ch = curl_init();\ncurl_setopt(\$ch, CURLOPT_URL, '$url');\ncurl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);\n\$response = curl_exec(\$ch);\ncurl_close(\$ch);\n\necho \$response;\n";
    }
    if (language == 'PHP / Guzzle') {
      return "<?php\nrequire 'vendor/autoload.php';\n\n\$client = new GuzzleHttp\\\\Client();\n\$response = \$client->get('$url');\n\necho \$response->getBody();\n";
    }
    if (language == 'Go / net/http') {
      return "package main\n\nimport (\n  \"fmt\"\n  \"io\"\n  \"net/http\"\n)\n\nfunc main() {\n  resp, err := http.Get(\"$url\")\n  if err != nil {\n    panic(err)\n  }\n  defer resp.Body.Close()\n  body, _ := io.ReadAll(resp.Body)\n  fmt.Println(string(body))\n}\n";
    }
    if (language == 'Rust / reqwest') {
      return "use reqwest::blocking;\n\nfn main() -> Result<(), Box<dyn std::error::Error>> {\n  let body = blocking::get(\"$url\")?.text()?;\n  println!(\"{}\", body);\n  Ok(())\n}\n";
    }
    if (language == 'C# / HttpClient') {
      return "using System.Net.Http;\n\nvar client = new HttpClient();\nvar response = await client.GetStringAsync(\"$url\");\nConsole.WriteLine(response);";
    }
    if (language == 'Java / HttpClient') {
      return "import java.net.URI;\nimport java.net.http.HttpClient;\nimport java.net.http.HttpRequest;\nimport java.net.http.HttpResponse;\n\nHttpClient client = HttpClient.newHttpClient();\nHttpRequest request = HttpRequest.newBuilder()\n  .uri(URI.create(\"$url\"))\n  .build();\n\nHttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());\nSystem.out.println(response.body());";
    }
    if (language == 'Ruby / Net::HTTP') {
      return "require 'net/http'\nrequire 'uri'\n\nuri = URI.parse('$url')\nresponse = Net::HTTP.get_response(uri)\nputs response.body";
    }
    if (language == 'Ruby / Faraday') {
      return "require 'faraday'\n\nresponse = Faraday.get('$url')\nputs response.body";
    }
    if (language == 'Swift / URLSession') {
      return "import Foundation\n\nlet url = URL(string: \"$url\")!\nlet task = URLSession.shared.dataTask(with: url) { data, _, error in\n  if let error = error {\n    print(error)\n    return\n  }\n  if let data = data, let text = String(data: data, encoding: .utf8) {\n    print(text)\n  }\n}\n\ntask.resume()\n";
    }
    if (language == 'Dart / http') {
      return "import 'package:http/http.dart' as http;\n\nvoid main() async {\n  final response = await http.get(Uri.parse('$url'));\n  print(response.body);\n}\n";
    }
    if (language == 'Dart / dio') {
      return "import 'package:dio/dio.dart';\n\nvoid main() async {\n  final dio = Dio();\n  final response = await dio.get('$url');\n  print(response.data);\n}\n";
    }
    return "fetch('$url')\n  .then(res => res.text())\n  .then(console.log);";
  }
}

class _JsonToCodeView extends StatefulWidget {
  const _JsonToCodeView();

  @override
  State<_JsonToCodeView> createState() => _JsonToCodeViewState();
}

class _JsonToCodeViewState extends State<_JsonToCodeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _lang = 'Swift';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _output.clear();
      setState(() {});
      return;
    }
    try {
      final decoded = jsonDecode(text);
      _output.text =
          '// $_lang output\n${const JsonEncoder.withIndent('  ').convert(decoded)}';
    } catch (e) {
      _output.text = 'Invalid JSON: $e';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final optionsPanel = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD5D5D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              ToolButton(label: 'Language'),
              SizedBox(width: 8),
              ToolButton(label: 'Other'),
            ],
          ),
          SizedBox(height: 8),
          CheckboxListTile(
            value: false,
            onChanged: null,
            title: Text('Plain types only'),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          CheckboxListTile(
            value: true,
            onChanged: null,
            title: Text('Generate initializers and mutators'),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          CheckboxListTile(
            value: true,
            onChanged: null,
            title: Text('Explicit CodingKey values in Codable types'),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          SizedBox(height: 8),
          ToolButton(label: 'Reset to Defaults'),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final editors = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: EditorPane(
                label: 'Input',
                actions: [
                  ToolButton(
                    label: 'Clipboard',
                    onPressed: () async {
                      final text = await _readClipboardText();
                      setState(() => _input.text = text);
                      _run();
                    },
                  ),
                  ToolButton(
                    label: 'Sample',
                    onPressed: () {
                      setState(() => _input.text = '{"name":"DevUtils"}');
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
                  const SmallDropdown(items: ['JSON'], initialValue: 'JSON'),
                ],
                controller: _input,
                onChanged: (_) => _run(),
                placeholder: 'Enter your text...',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: EditorPane(
                label: 'Output',
                actions: [
                  SmallDropdown(
                    items: const ['Swift', 'TypeScript', 'Kotlin'],
                    initialValue: _lang,
                    onChanged: (value) {
                      setState(() => _lang = value);
                      _run();
                    },
                  ),
                  ToolButton(
                    label: 'Copy',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: _output.text)),
                  ),
                ],
                controller: _output,
                readOnly: true,
                placeholder: '- Right click -> Save to file...',
              ),
            ),
          ],
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: editors),
              const SizedBox(width: 16),
              SizedBox(width: 260, child: optionsPanel),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: editors),
            const SizedBox(height: 16),
            optionsPanel,
          ],
        );
      },
    );
  }
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
    _output.text = 'Unexpected Error:\nThe operation could not be completed.';
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
            final text = await _readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = '-----BEGIN CERTIFICATE-----');
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
        const ToolIconButton(icon: Icons.settings),
      ],
      outputActions: [
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
      outputPlaceholder:
          'Unexpected Error:\nThe operation could not be completed.',
    );
  }
}

class _PhpJsonConverterView extends StatefulWidget {
  const _PhpJsonConverterView();

  @override
  State<_PhpJsonConverterView> createState() => _PhpJsonConverterViewState();
}

class _PhpJsonConverterViewState extends State<_PhpJsonConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  bool _phpToJson = true;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    _output.text = 'Scripts Runtime for this tool is missing (php)';
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
            final text = await _readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(
              () => _input.text = _phpToJson
                  ? '(object) array('
                  : '{"store": {"book": []}}',
            );
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
        ToolIconButton(icon: Icons.settings, onPressed: _run),
        SegmentedToggle(
          options: const ['PHP → JSON', 'JSON → PHP'],
          initialIndex: _phpToJson ? 0 : 1,
          onChanged: (index) {
            setState(() => _phpToJson = index == 0);
            _run();
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
      inputPlaceholder: _phpToJson ? '(object) array(' : '{"store": {}}',
      outputPlaceholder: 'Scripts Runtime for this tool is missing (php)',
    );
  }
}

class _HexAsciiConverterView extends StatefulWidget {
  const _HexAsciiConverterView();

  @override
  State<_HexAsciiConverterView> createState() => _HexAsciiConverterViewState();
}

class _HexAsciiConverterViewState extends State<_HexAsciiConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  bool _hexToAscii = true;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      if (_hexToAscii) {
        final bytes = <int>[];
        final parts = text.split(RegExp(r'\s+'));
        for (final part in parts) {
          if (part.trim().isEmpty) continue;
          var token = part.trim();
          if (token.startsWith('0x') || token.startsWith('0X')) {
            token = token.substring(2);
          }
          if (token.length.isOdd) {
            token = '0$token';
          }
          for (var i = 0; i < token.length; i += 2) {
            final hexPair = token.substring(i, i + 2);
            bytes.add(int.parse(hexPair, radix: 16));
          }
        }
        _output.text = String.fromCharCodes(bytes);
      } else {
        final bytes = text.codeUnits;
        final buffer = StringBuffer();
        for (var i = 0; i < bytes.length; i++) {
          if (i > 0) buffer.write(' ');
          buffer.write(
            bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase(),
          );
        }
        _output.text = buffer.toString();
      }
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(
                label: 'Clipboard',
                onPressed: () async {
                  final text = await _readClipboardText();
                  setState(() => _input.text = text);
                  _run();
                },
              ),
              ToolButton(
                label: 'Sample',
                onPressed: () {
                  setState(
                    () =>
                        _input.text = _hexToAscii ? '48 65 6C 6C 6F' : 'Hello',
                  );
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
              SegmentedToggle(
                options: const ['Hex → ASCII', 'ASCII → Hex'],
                initialIndex: _hexToAscii ? 0 : 1,
                onChanged: (index) {
                  setState(() => _hexToAscii = index == 0);
                  _run();
                },
              ),
            ],
            outputActions: [
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: _hexToAscii ? '48 65 6C 6C 6F' : 'Hello',
            outputPlaceholder: _hexToAscii ? 'Hello' : '48 65 6C 6C 6F',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

class _AuthTotpView extends StatefulWidget {
  const _AuthTotpView();

  @override
  State<_AuthTotpView> createState() => _AuthTotpViewState();
}

class _AuthTotpViewState extends State<_AuthTotpView> {
  List<_TotpEntry> _entries = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('totp_entries');
      if (raw == null || raw.isEmpty) {
        setState(() {
          _entries = [
            _TotpEntry(
              name: 'twitter',
              secret: 'JBSWY3DPEHPK3PXP',
              color: const Color(0xFFE6E6E6),
            ),
          ];
        });
      } else {
        final decoded = jsonDecode(raw) as List<dynamic>;
        setState(() {
          _entries = decoded
              .map(
                (entry) => _TotpEntry(
                  name: entry['name'] as String? ?? 'New app',
                  secret: entry['secret'] as String? ?? '',
                  color: Color(entry['color'] as int? ?? 0xFFE6E6E6),
                ),
              )
              .toList();
        });
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _openAddDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => _TotpAddDialog(
        onAdd: (entry) {
          setState(() => _entries.add(entry));
          _saveEntries();
        },
      ),
    );
  }

  void _openEditDialog(int index) {
    final entry = _entries[index];
    showDialog<void>(
      context: context,
      builder: (context) => _TotpAddDialog(
        title: 'Edit application',
        actionLabel: 'Save',
        initialEntry: entry,
        onAdd: (updated) {
          setState(() => _entries[index] = updated);
          _saveEntries();
        },
      ),
    );
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _entries
          .map(
            (entry) => {
              'name': entry.name,
              'secret': entry.secret,
              'color': entry.color.toARGB32(),
            },
          )
          .toList(),
    );
    await prefs.setString('totp_entries', encoded);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (var i = 0; i < _entries.length; i++)
            _TotpCard(entry: _entries[i], onEdit: () => _openEditDialog(i)),
          _TotpAddCard(onTap: _openAddDialog),
        ],
      ),
    );
  }
}

class _TotpEntry {
  _TotpEntry({required this.name, required this.secret, required this.color});

  final String name;
  final String secret;
  final Color color;
}

class _TotpCard extends StatelessWidget {
  const _TotpCard({required this.entry, required this.onEdit});

  final _TotpEntry entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final current = _totpCode(entry.secret, now);
    final next = _totpCode(entry.secret, now + 30);
    final secondsRemaining = 30 - (now % 30);
    final warn = secondsRemaining <= 5;
    final blink = warn && (now % 2 == 0);
    final currentColor = blink ? Colors.redAccent : const Color(0xFF1F1F1F);
    final nextColor = blink ? const Color(0xFFD32F2F) : Colors.black38;
    return Container(
      width: 240,
      height: 132,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: entry.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current',
                    style: TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    current,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: currentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Next',
                    style: TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                  const SizedBox(height: 2),
                  Text(next, style: TextStyle(fontSize: 14, color: nextColor)),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${secondsRemaining}s',
                    style: const TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(
                      Icons.edit,
                      size: 16,
                      color: Colors.black38,
                    ),
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.name,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _TotpAddCard extends StatelessWidget {
  const _TotpAddCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 240,
        height: 132,
        decoration: BoxDecoration(
          color: const Color(0xFFDADADA),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black12),
        ),
        child: const Center(
          child: Icon(Icons.add, size: 40, color: Colors.black26),
        ),
      ),
    );
  }
}

class _TotpAddDialog extends StatefulWidget {
  const _TotpAddDialog({
    required this.onAdd,
    this.initialEntry,
    this.title = 'New application',
    this.actionLabel = 'Add',
  });

  final ValueChanged<_TotpEntry> onAdd;
  final _TotpEntry? initialEntry;
  final String title;
  final String actionLabel;

  @override
  State<_TotpAddDialog> createState() => _TotpAddDialogState();
}

class _TotpAddDialogState extends State<_TotpAddDialog> {
  final TextEditingController _secret = TextEditingController();
  final TextEditingController _name = TextEditingController();
  Color _selected = const Color(0xFFE6E6E6);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEntry;
    if (initial != null) {
      _secret.text = initial.secret;
      _name.text = initial.name;
      _selected = initial.color;
    }
  }

  @override
  void dispose() {
    _secret.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final secret = _secret.text.trim();
    final name = _name.text.trim().isEmpty ? 'New app' : _name.text.trim();
    if (secret.isEmpty) return;
    widget.onAdd(_TotpEntry(name: name, secret: secret, color: _selected));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Secret key',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    _InlineTextField(
                      hintText: 'Paste or enter secret',
                      controller: _secret,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Application name',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    _InlineTextField(
                      hintText: 'Optional label',
                      controller: _name,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Accent color',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _totpPalette
                          .map(
                            (color) => GestureDetector(
                              onTap: () => setState(() => _selected = color),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _selected == color
                                        ? const Color(0xFF2B2B2B)
                                        : Colors.black26,
                                    width: _selected == color ? 2 : 1,
                                  ),
                                  boxShadow: _selected == color
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x22000000),
                                            blurRadius: 6,
                                            offset: Offset(0, 2),
                                          ),
                                        ]
                                      : const [],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF202124),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(widget.actionLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<Color> _totpPalette = [
  Colors.white,
  Colors.black,
  Color(0xFFFF4A3D),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
  Color(0xFF673AB7),
  Color(0xFF3F51B5),
  Color(0xFF2196F3),
  Color(0xFF03A9F4),
  Color(0xFF00BCD4),
  Color(0xFF009688),
  Color(0xFF4CAF50),
  Color(0xFF8BC34A),
  Color(0xFFCDDC39),
  Color(0xFFFFEB3B),
  Color(0xFFFFC107),
  Color(0xFFFF9800),
  Color(0xFFFF5722),
  Color(0xFF795548),
  Color(0xFF9E9E9E),
  Color(0xFF607D8B),
];

String _totpCode(String secret, int timestampSeconds) {
  final key = _base32Decode(secret);
  if (key.isEmpty) return '------';
  final counter = timestampSeconds ~/ 30;
  final bytes = ByteData(8)..setInt64(0, counter);
  final hmac = crypto.Hmac(crypto.sha1, key);
  final digest = hmac.convert(bytes.buffer.asUint8List()).bytes;
  final offset = digest.last & 0x0f;
  final code =
      ((digest[offset] & 0x7f) << 24) |
      ((digest[offset + 1] & 0xff) << 16) |
      ((digest[offset + 2] & 0xff) << 8) |
      (digest[offset + 3] & 0xff);
  final otp = code % 1000000;
  return otp.toString().padLeft(6, '0');
}

List<int> _base32Decode(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final output = <int>[];
  for (final char in cleaned.split('')) {
    final index = alphabet.indexOf(char);
    if (index == -1) continue;
    buffer = (buffer << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      output.add((buffer >> bits) & 0xff);
    }
  }
  return output;
}

class _YamlToJsonView extends StatefulWidget {
  const _YamlToJsonView();

  @override
  State<_YamlToJsonView> createState() => _YamlToJsonViewState();
}

class _YamlToJsonViewState extends State<_YamlToJsonView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _indent = '2 spaces';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      final yamlNode = loadYaml(text);
      final normalized = _normalizeYaml(yamlNode);
      final encoder = JsonEncoder.withIndent(_indentFor(_indent));
      _output.text = encoder.convert(normalized);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    const sample =
        '- item: Super Hoop\n  quantity: 1\n- item: Basketball\n  quantity: 4';
    setState(() => _input.text = sample);
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
            ],
            outputActions: [
              SmallDropdown(
                items: const ['2 spaces', '4 spaces', 'Tabs'],
                initialValue: _indent,
                onChanged: (value) {
                  setState(() => _indent = value);
                  _run();
                },
              ),
              ToolButton(label: 'Copy', onPressed: _copyOutput),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: '---\n- item: Super Hoop',
            outputPlaceholder: '[]',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

dynamic _normalizeYaml(dynamic node) {
  if (node is YamlMap) {
    return node.map(
      (key, value) => MapEntry(key.toString(), _normalizeYaml(value)),
    );
  }
  if (node is YamlList) {
    return node.map(_normalizeYaml).toList();
  }
  return node;
}

class _YamlJsonConverterView extends StatefulWidget {
  const _YamlJsonConverterView();

  @override
  State<_YamlJsonConverterView> createState() => _YamlJsonConverterViewState();
}

class _YamlJsonConverterViewState extends State<_YamlJsonConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _indent = '2 spaces';
  bool _yamlToJson = true;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      if (_yamlToJson) {
        final yamlNode = loadYaml(text);
        final normalized = _normalizeYaml(yamlNode);
        final encoder = JsonEncoder.withIndent(_indentFor(_indent));
        _output.text = encoder.convert(normalized);
      } else {
        final jsonData = jsonDecode(text);
        _output.text = _toYamlString(jsonData);
      }
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(() {
      _input.text = _yamlToJson
          ? '- item: Super Hoop\n  quantity: 1\n- item: Basketball\n  quantity: 4'
          : '{"store":{"book":[{"category":"reference","title":"Sayings"}]}}';
    });
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              SegmentedToggle(
                options: const ['YAML → JSON', 'JSON → YAML'],
                initialIndex: _yamlToJson ? 0 : 1,
                onChanged: (index) {
                  setState(() => _yamlToJson = index == 0);
                  _run();
                },
              ),
            ],
            outputActions: [
              if (_yamlToJson)
                SmallDropdown(
                  items: const ['2 spaces', '4 spaces', 'Tabs'],
                  initialValue: _indent,
                  onChanged: (value) {
                    setState(() => _indent = value);
                    _run();
                  },
                ),
              ToolButton(label: 'Copy', onPressed: _copyOutput),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: _yamlToJson
                ? '---\n- item: Super Hoop'
                : '{"store": {"book": []}}',
            outputPlaceholder: _yamlToJson ? '[]' : 'store:\n  book: []',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

class _JsonToYamlView extends StatefulWidget {
  const _JsonToYamlView();

  @override
  State<_JsonToYamlView> createState() => _JsonToYamlViewState();
}

class _JsonToYamlViewState extends State<_JsonToYamlView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      final jsonData = jsonDecode(text);
      _output.text = _toYamlString(jsonData);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    const sample =
        '{"store":{"book":[{"category":"reference","title":"Sayings"}]}}';
    setState(() => _input.text = sample);
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
            ],
            outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: '{"store": {"book": []}}',
            outputPlaceholder: 'store:\n  book: []',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

String _toYamlString(dynamic value, {int indent = 0}) {
  final pad = '  ' * indent;
  if (value is Map) {
    final buffer = StringBuffer();
    for (final entry in value.entries) {
      buffer.write('$pad${entry.key}:');
      if (entry.value is Map || entry.value is List) {
        buffer.write('\n');
        buffer.write(_toYamlString(entry.value, indent: indent + 1));
      } else {
        buffer.write(' ${_yamlScalar(entry.value)}\n');
      }
    }
    return buffer.toString().trimRight();
  }
  if (value is List) {
    final buffer = StringBuffer();
    for (final item in value) {
      if (item is Map || item is List) {
        buffer.write('$pad- \n');
        buffer.write(_toYamlString(item, indent: indent + 1));
        buffer.write('\n');
      } else {
        buffer.write('$pad- ${_yamlScalar(item)}\n');
      }
    }
    return buffer.toString().trimRight();
  }
  return '$pad${_yamlScalar(value)}';
}

String _yamlScalar(dynamic value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  final text = value.toString();
  if (text.contains(':') ||
      text.contains('#') ||
      text.contains('"') ||
      text.contains('\n')) {
    final escaped = text.replaceAll('"', '\\"');
    return '"$escaped"';
  }
  return text;
}

class _JsonToCsvView extends StatefulWidget {
  const _JsonToCsvView();

  @override
  State<_JsonToCsvView> createState() => _JsonToCsvViewState();
}

class _JsonToCsvViewState extends State<_JsonToCsvView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      final decoded = jsonDecode(text);
      final rows = _jsonToCsvRows(decoded);
      final buffer = StringBuffer();
      for (final row in rows) {
        buffer.writeln(row.map(_escapeCsv).join(','));
      }
      _output.text = buffer.toString().trimRight();
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    const sample =
        '{"data":[{"id":1,"name":"JSON Formatter","deep":{"nested":1,"value":2}}]}';
    setState(() => _input.text = sample);
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
            ],
            outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: '{"data":[{"id":1,"name":"JSON Formatter"}]}',
            outputPlaceholder: 'id,name',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

List<List<String>> _jsonToCsvRows(dynamic decoded) {
  dynamic data = decoded;
  if (decoded is Map && decoded['data'] is List) {
    data = decoded['data'];
  }
  if (data is! List) {
    throw ArgumentError('Expected a JSON array of objects.');
  }
  final flattened = <Map<String, dynamic>>[];
  final headers = <String>{};
  for (final item in data) {
    if (item is Map) {
      final map = _flattenJson(item);
      flattened.add(map);
      headers.addAll(map.keys);
    } else {
      throw ArgumentError('Each row must be an object.');
    }
  }
  final headerList = headers.toList()..sort();
  final rows = <List<String>>[];
  rows.add(headerList);
  for (final item in flattened) {
    rows.add(headerList.map((key) => '${item[key] ?? ''}').toList());
  }
  return rows;
}

Map<String, dynamic> _flattenJson(
  Map<dynamic, dynamic> input, {
  String prefix = '',
}) {
  final result = <String, dynamic>{};
  input.forEach((key, value) {
    final fullKey = prefix.isEmpty ? '$key' : '$prefix.$key';
    if (value is Map) {
      result.addAll(_flattenJson(value, prefix: fullKey));
    } else {
      result[fullKey] = value;
    }
  });
  return result;
}

String _escapeCsv(String value) {
  if (value.contains('"')) {
    value = value.replaceAll('"', '""');
  }
  if (value.contains(',') || value.contains('\n') || value.contains('\r')) {
    return '"$value"';
  }
  return value;
}

class _JsonCsvConverterView extends StatefulWidget {
  const _JsonCsvConverterView();

  @override
  State<_JsonCsvConverterView> createState() => _JsonCsvConverterViewState();
}

class _JsonCsvConverterViewState extends State<_JsonCsvConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  bool _csvToJson = true;
  String _indent = '2 spaces';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      if (_csvToJson) {
        final rows = _parseCsv(text);
        if (rows.isEmpty) {
          _output.text = '[]';
        } else {
          final headers = rows.first;
          final data = <Map<String, String>>[];
          for (var i = 1; i < rows.length; i++) {
            final row = rows[i];
            final map = <String, String>{};
            for (var j = 0; j < headers.length; j++) {
              map[headers[j]] = j < row.length ? row[j] : '';
            }
            data.add(map);
          }
          final encoder = JsonEncoder.withIndent(_indentFor(_indent));
          _output.text = encoder.convert(data);
        }
      } else {
        final decoded = jsonDecode(text);
        final rows = _jsonToCsvRows(decoded);
        final buffer = StringBuffer();
        for (final row in rows) {
          buffer.writeln(row.map(_escapeCsv).join(','));
        }
        _output.text = buffer.toString().trimRight();
      }
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(() {
      _input.text = _csvToJson
          ? 'id,name,note\n1,DevUtils,"Sample row"\n2,Example,"Escaped ""string"""'
          : '{"data":[{"id":1,"name":"JSON Formatter","deep":{"nested":1,"value":2}}]}';
    });
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              SegmentedToggle(
                options: const ['CSV → JSON', 'JSON → CSV'],
                initialIndex: _csvToJson ? 0 : 1,
                onChanged: (index) {
                  setState(() => _csvToJson = index == 0);
                  _run();
                },
              ),
            ],
            outputActions: [
              if (_csvToJson)
                SmallDropdown(
                  items: const ['2 spaces', '4 spaces', 'Tabs'],
                  initialValue: _indent,
                  onChanged: (value) {
                    setState(() => _indent = value);
                    _run();
                  },
                ),
              ToolButton(label: 'Copy', onPressed: _copyOutput),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: _csvToJson
                ? 'id,name,note'
                : '{"data":[{"id":1}]}',
            outputPlaceholder: _csvToJson ? '[]' : 'id,name',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

class _HashGeneratorView extends StatefulWidget {
  const _HashGeneratorView();

  @override
  State<_HashGeneratorView> createState() => _HashGeneratorViewState();
}

class _HashGeneratorViewState extends State<_HashGeneratorView> {
  final TextEditingController _input = TextEditingController();
  bool _lowercase = false;
  final Map<String, String> _hashes = {};

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _compute() {
    final bytes = utf8.encode(_input.text);
    final digestMap = <String, String>{
      'MD2': _digestHex(MD2Digest(), bytes),
      'MD4': _digestHex(MD4Digest(), bytes),
      'MD5': _digestHex(MD5Digest(), bytes),
      'SHA-1': _digestHex(SHA1Digest(), bytes),
      'SHA-224': _digestHex(SHA224Digest(), bytes),
      'SHA-256': _digestHex(SHA256Digest(), bytes),
      'SHA-384': _digestHex(SHA384Digest(), bytes),
      'SHA-512': _digestHex(SHA512Digest(), bytes),
      'RIPEMD-128': _digestHex(RIPEMD128Digest(), bytes),
      'RIPEMD-160': _digestHex(RIPEMD160Digest(), bytes),
      'RIPEMD-320': _digestHex(RIPEMD320Digest(), bytes),
      'Tiger': _digestHex(TigerDigest(), bytes),
      'Whirlpool': _digestHex(WhirlpoolDigest(), bytes),
      'Keccak-256': _digestHex(KeccakDigest(256), bytes),
    };
    _hashes
      ..clear()
      ..addAll(
        digestMap.map(
          (key, value) =>
              MapEntry(key, _lowercase ? value.toLowerCase() : value),
        ),
      );
    setState(() {});
  }

  String _digestHex(dynamic digest, List<int> bytes) {
    final out = digest.process(Uint8List.fromList(bytes));
    return _bytesToHex(out);
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _compute();
  }

  void _setSample() {
    setState(() => _input.text = 'Ut quidam aut expedita porro ut ipsa ea et');
    _compute();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _hashes.clear();
    });
  }

  Future<void> _copyHash(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  @override
  Widget build(BuildContext context) {
    final byteCount = utf8.encode(_input.text).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: EditorPane(
            label: 'Input',
            actions: [
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              const ToolButton(label: 'Load file...'),
              ToolButton(label: 'Clear', onPressed: _clearInput),
            ],
            controller: _input,
            onChanged: (_) => _compute(),
            placeholder: 'Enter text to hash...',
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('$byteCount bytes (string)'),
                  const SizedBox(width: 12),
                  Checkbox(
                    value: _lowercase,
                    onChanged: (value) {
                      setState(() => _lowercase = value ?? false);
                      _compute();
                    },
                  ),
                  const Text('lowercased'),
                ],
              ),
              const SizedBox(height: 8),
              _HashField(
                label: 'MD2',
                value: _hashes['MD2'] ?? '',
                onCopy: () => _copyHash(_hashes['MD2'] ?? ''),
              ),
              _HashField(
                label: 'MD4',
                value: _hashes['MD4'] ?? '',
                onCopy: () => _copyHash(_hashes['MD4'] ?? ''),
              ),
              _HashField(
                label: 'MD5',
                value: _hashes['MD5'] ?? '',
                onCopy: () => _copyHash(_hashes['MD5'] ?? ''),
              ),
              _HashField(
                label: 'SHA1',
                value: _hashes['SHA1'] ?? '',
                onCopy: () => _copyHash(_hashes['SHA1'] ?? ''),
              ),
              _HashField(
                label: 'SHA224',
                value: _hashes['SHA224'] ?? '',
                onCopy: () => _copyHash(_hashes['SHA224'] ?? ''),
              ),
              _HashField(
                label: 'SHA256',
                value: _hashes['SHA256'] ?? '',
                onCopy: () => _copyHash(_hashes['SHA256'] ?? ''),
              ),
              _HashField(
                label: 'SHA384',
                value: _hashes['SHA384'] ?? '',
                onCopy: () => _copyHash(_hashes['SHA384'] ?? ''),
              ),
              _HashField(
                label: 'SHA512',
                value: _hashes['SHA512'] ?? '',
                onCopy: () => _copyHash(_hashes['SHA512'] ?? ''),
              ),
              _HashField(
                label: 'Keccak-256',
                value: _hashes['Keccak-256'] ?? '',
                onCopy: () => _copyHash(_hashes['Keccak-256'] ?? ''),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TextEncryptionView extends StatefulWidget {
  const _TextEncryptionView();

  @override
  State<_TextEncryptionView> createState() => _TextEncryptionViewState();
}

class _TextEncryptionViewState extends State<_TextEncryptionView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  final TextEditingController _key = TextEditingController();

  String _category = 'Modern';
  String _algorithm = 'AES-256-CBC';
  String _mode = 'Encrypt';
  String _outputFormat = 'Base64';
  String? _error;

  static const _categories = [
    'Modern',
    'Legacy',
    'Stream',
    'Lightweight',
    'Classical',
  ];

  static const _algorithmsByCategory = {
    'Modern': [
      'AES-128-ECB',
      'AES-128-CBC',
      'AES-128-CFB',
      'AES-128-OFB',
      'AES-128-CTR',
      'AES-192-ECB',
      'AES-192-CBC',
      'AES-192-CFB',
      'AES-192-OFB',
      'AES-192-CTR',
      'AES-256-ECB',
      'AES-256-CBC',
      'AES-256-CFB',
      'AES-256-OFB',
      'AES-256-CTR',
      'ChaCha20',
      'Salsa20',
    ],
    'Legacy': ['3DES-CBC', '3DES-ECB', 'RC2-CBC', 'RC2-ECB'],
    'Stream': ['RC4'],
    'Lightweight': ['TEA', 'XTEA'],
    'Classical': ['XOR', 'Vigenere', 'Caesar', 'ROT13', 'Atbash'],
  };

  List<String> get _algorithms => _algorithmsByCategory[_category] ?? [];

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _key.dispose();
    super.dispose();
  }

  void _process() {
    final inputText = _input.text;
    final keyText = _key.text;

    if (inputText.isEmpty) {
      setState(() {
        _output.clear();
        _error = null;
      });
      return;
    }

    if (keyText.isEmpty) {
      setState(() {
        _output.clear();
        _error = 'Please enter a password/key';
      });
      return;
    }

    try {
      String result;
      if (_mode == 'Encrypt') {
        result = _encrypt(inputText, keyText);
      } else {
        result = _decrypt(inputText, keyText);
      }
      setState(() {
        _output.text = result;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _output.clear();
        _error = 'Error: ${e.toString()}';
      });
    }
  }

  String _encrypt(String plaintext, String password) {
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));

    // Classical ciphers - text-based, no binary output
    if (_category == 'Classical') {
      return _encryptClassical(plaintext, password);
    }

    Uint8List result;

    if (_algorithm.startsWith('AES')) {
      result = _encryptAES(plaintextBytes, password);
    } else if (_algorithm == 'ChaCha20') {
      result = _encryptChaCha20(plaintextBytes, password);
    } else if (_algorithm == 'Salsa20') {
      result = _encryptSalsa20(plaintextBytes, password);
    } else if (_algorithm.startsWith('3DES')) {
      result = _encrypt3DES(plaintextBytes, password);
    } else if (_algorithm.startsWith('RC2')) {
      result = _encryptRC2(plaintextBytes, password);
    } else if (_algorithm == 'RC4') {
      result = _encryptRC4(plaintextBytes, password);
    } else if (_algorithm == 'TEA') {
      result = _encryptTEA(plaintextBytes, password);
    } else if (_algorithm == 'XTEA') {
      result = _encryptXTEA(plaintextBytes, password);
    } else {
      throw Exception('Unknown algorithm: $_algorithm');
    }

    return _outputFormat == 'Base64'
        ? base64Encode(result)
        : _bytesToHex(result);
  }

  String _encryptClassical(String plaintext, String key) {
    switch (_algorithm) {
      case 'XOR':
        final keyBytes = utf8.encode(key);
        final textBytes = utf8.encode(plaintext);
        final result = Uint8List(textBytes.length);
        for (var i = 0; i < textBytes.length; i++) {
          result[i] = textBytes[i] ^ keyBytes[i % keyBytes.length];
        }
        return _outputFormat == 'Base64'
            ? base64Encode(result)
            : _bytesToHex(result);
      case 'Vigenere':
        return _vigenereEncrypt(plaintext, key);
      case 'Caesar':
        final shift = int.tryParse(key) ?? 3;
        return _caesarEncrypt(plaintext, shift);
      case 'ROT13':
        return _caesarEncrypt(plaintext, 13);
      case 'Atbash':
        return _atbashCipher(plaintext);
      default:
        throw Exception('Unknown classical cipher');
    }
  }

  Uint8List _encryptAES(Uint8List plaintext, String password) {
    final keySize = _algorithm.contains('128')
        ? 16
        : _algorithm.contains('192')
        ? 24
        : 32;
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, keySize));
    final iv = _generateIV(16);

    final mode = _algorithm.split('-').last;
    Uint8List ciphertext;

    switch (mode) {
      case 'ECB':
        ciphertext = _aesEcbEncrypt(_pkcs7Pad(plaintext, 16), key);
        return ciphertext; // No IV for ECB
      case 'CBC':
        ciphertext = _aesCbcEncrypt(_pkcs7Pad(plaintext, 16), key, iv);
        break;
      case 'CFB':
        ciphertext = _aesCfbEncrypt(plaintext, key, iv);
        break;
      case 'OFB':
        ciphertext = _aesOfbEncrypt(plaintext, key, iv);
        break;
      case 'CTR':
        ciphertext = _aesCtrEncrypt(plaintext, key, iv);
        break;
      default:
        throw Exception('Unknown AES mode: $mode');
    }

    return _combineIvAndCiphertext(iv, ciphertext);
  }

  Uint8List _encryptChaCha20(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = _generateIV(12);

    final cipher = ChaCha20Engine()
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    final ciphertext = cipher.process(plaintext);

    return _combineIvAndCiphertext(nonce, ciphertext);
  }

  Uint8List _encryptSalsa20(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = _generateIV(8);

    final cipher = Salsa20Engine()
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    final ciphertext = cipher.process(plaintext);

    return _combineIvAndCiphertext(nonce, ciphertext);
  }

  Uint8List _encrypt3DES(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 24));
    final padded = _pkcs7Pad(plaintext, 8);

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(DESedeEngine())
        ..init(true, pc.KeyParameter(key));
      return _processBlocks(cipher, padded, 8);
    } else {
      final iv = _generateIV(8);
      final cipher = CBCBlockCipher(DESedeEngine())
        ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _combineIvAndCiphertext(iv, _processBlocks(cipher, padded, 8));
    }
  }

  Uint8List _encryptRC2(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final padded = _pkcs7Pad(plaintext, 8);

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(RC2Engine())
        ..init(true, pc.KeyParameter(key));
      return _processBlocks(cipher, padded, 8);
    } else {
      final iv = _generateIV(8);
      final cipher = CBCBlockCipher(RC2Engine())
        ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _combineIvAndCiphertext(iv, _processBlocks(cipher, padded, 8));
    }
  }

  Uint8List _encryptRC4(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final cipher = RC4Engine()..init(true, pc.KeyParameter(key));
    return cipher.process(plaintext);
  }

  Uint8List _encryptTEA(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final padded = _pkcs7Pad(plaintext, 8);
    return _teaEncrypt(padded, key);
  }

  Uint8List _encryptXTEA(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final padded = _pkcs7Pad(plaintext, 8);
    return _xteaEncrypt(padded, key);
  }

  String _decrypt(String ciphertextStr, String password) {
    // Classical ciphers
    if (_category == 'Classical') {
      return _decryptClassical(ciphertextStr, password);
    }

    Uint8List combined;
    try {
      combined = _outputFormat == 'Base64'
          ? Uint8List.fromList(base64Decode(ciphertextStr.trim()))
          : _hexToBytes(ciphertextStr.trim());
    } catch (e) {
      throw Exception('Invalid $_outputFormat input');
    }

    Uint8List plaintext;

    if (_algorithm.startsWith('AES')) {
      plaintext = _decryptAES(combined, password);
    } else if (_algorithm == 'ChaCha20') {
      plaintext = _decryptChaCha20(combined, password);
    } else if (_algorithm == 'Salsa20') {
      plaintext = _decryptSalsa20(combined, password);
    } else if (_algorithm.startsWith('3DES')) {
      plaintext = _decrypt3DES(combined, password);
    } else if (_algorithm.startsWith('RC2')) {
      plaintext = _decryptRC2(combined, password);
    } else if (_algorithm == 'RC4') {
      plaintext = _decryptRC4(combined, password);
    } else if (_algorithm == 'TEA') {
      plaintext = _decryptTEA(combined, password);
    } else if (_algorithm == 'XTEA') {
      plaintext = _decryptXTEA(combined, password);
    } else {
      throw Exception('Unknown algorithm: $_algorithm');
    }

    return utf8.decode(plaintext);
  }

  String _decryptClassical(String ciphertext, String key) {
    switch (_algorithm) {
      case 'XOR':
        final keyBytes = utf8.encode(key);
        final ciphertextBytes = _outputFormat == 'Base64'
            ? base64Decode(ciphertext)
            : _hexToBytes(ciphertext);
        final result = Uint8List(ciphertextBytes.length);
        for (var i = 0; i < ciphertextBytes.length; i++) {
          result[i] = ciphertextBytes[i] ^ keyBytes[i % keyBytes.length];
        }
        return utf8.decode(result);
      case 'Vigenere':
        return _vigenereDecrypt(ciphertext, key);
      case 'Caesar':
        final shift = int.tryParse(key) ?? 3;
        return _caesarDecrypt(ciphertext, shift);
      case 'ROT13':
        return _caesarEncrypt(ciphertext, 13); // ROT13 is symmetric
      case 'Atbash':
        return _atbashCipher(ciphertext); // Atbash is symmetric
      default:
        throw Exception('Unknown classical cipher');
    }
  }

  Uint8List _decryptAES(Uint8List combined, String password) {
    final keySize = _algorithm.contains('128')
        ? 16
        : _algorithm.contains('192')
        ? 24
        : 32;
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, keySize));

    final mode = _algorithm.split('-').last;
    Uint8List ciphertext;
    Uint8List iv;

    if (mode == 'ECB') {
      ciphertext = combined;
      return _pkcs7Unpad(_aesEcbDecrypt(ciphertext, key));
    }

    if (combined.length < 17) throw Exception('Ciphertext too short');
    iv = Uint8List.fromList(combined.sublist(0, 16));
    ciphertext = Uint8List.fromList(combined.sublist(16));

    switch (mode) {
      case 'CBC':
        return _pkcs7Unpad(_aesCbcDecrypt(ciphertext, key, iv));
      case 'CFB':
        return _aesCfbDecrypt(ciphertext, key, iv);
      case 'OFB':
        return _aesOfbDecrypt(ciphertext, key, iv);
      case 'CTR':
        return _aesCtrDecrypt(ciphertext, key, iv);
      default:
        throw Exception('Unknown AES mode: $mode');
    }
  }

  Uint8List _decryptChaCha20(Uint8List combined, String password) {
    if (combined.length < 13) throw Exception('Ciphertext too short');
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = Uint8List.fromList(combined.sublist(0, 12));
    final ciphertext = Uint8List.fromList(combined.sublist(12));

    final cipher = ChaCha20Engine()
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    return cipher.process(ciphertext);
  }

  Uint8List _decryptSalsa20(Uint8List combined, String password) {
    if (combined.length < 9) throw Exception('Ciphertext too short');
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = Uint8List.fromList(combined.sublist(0, 8));
    final ciphertext = Uint8List.fromList(combined.sublist(8));

    final cipher = Salsa20Engine()
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    return cipher.process(ciphertext);
  }

  Uint8List _decrypt3DES(Uint8List combined, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 24));

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(DESedeEngine())
        ..init(false, pc.KeyParameter(key));
      return _pkcs7Unpad(_processBlocks(cipher, combined, 8));
    } else {
      if (combined.length < 9) throw Exception('Ciphertext too short');
      final iv = Uint8List.fromList(combined.sublist(0, 8));
      final ciphertext = Uint8List.fromList(combined.sublist(8));
      final cipher = CBCBlockCipher(DESedeEngine())
        ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _pkcs7Unpad(_processBlocks(cipher, ciphertext, 8));
    }
  }

  Uint8List _decryptRC2(Uint8List combined, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(RC2Engine())
        ..init(false, pc.KeyParameter(key));
      return _pkcs7Unpad(_processBlocks(cipher, combined, 8));
    } else {
      if (combined.length < 9) throw Exception('Ciphertext too short');
      final iv = Uint8List.fromList(combined.sublist(0, 8));
      final ciphertext = Uint8List.fromList(combined.sublist(8));
      final cipher = CBCBlockCipher(RC2Engine())
        ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _pkcs7Unpad(_processBlocks(cipher, ciphertext, 8));
    }
  }

  Uint8List _decryptRC4(Uint8List ciphertext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final cipher = RC4Engine()..init(false, pc.KeyParameter(key));
    return cipher.process(ciphertext);
  }

  Uint8List _decryptTEA(Uint8List ciphertext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    return _pkcs7Unpad(_teaDecrypt(ciphertext, key));
  }

  Uint8List _decryptXTEA(Uint8List ciphertext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    return _pkcs7Unpad(_xteaDecrypt(ciphertext, key));
  }

  // ============ Helper Methods ============

  Uint8List _generateIV(int size) {
    final iv = Uint8List(size);
    final random = Random.secure();
    for (var i = 0; i < size; i++) {
      iv[i] = random.nextInt(256);
    }
    return iv;
  }

  Uint8List _combineIvAndCiphertext(Uint8List iv, Uint8List ciphertext) {
    final combined = Uint8List(iv.length + ciphertext.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, ciphertext);
    return combined;
  }

  Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padLength = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setRange(0, data.length, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLength;
    }
    return padded;
  }

  Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLength = data.last;
    if (padLength > 0 && padLength <= 16 && padLength <= data.length) {
      return Uint8List.fromList(data.sublist(0, data.length - padLength));
    }
    return data;
  }

  Uint8List _processBlocks(dynamic cipher, Uint8List data, int blockSize) {
    final output = Uint8List(data.length);
    for (var offset = 0; offset < data.length; offset += blockSize) {
      cipher.processBlock(data, offset, output, offset);
    }
    return output;
  }

  // ============ AES Modes ============

  Uint8List _aesEcbEncrypt(Uint8List plaintext, Uint8List key) {
    final cipher = ECBBlockCipher(AESEngine())
      ..init(true, pc.KeyParameter(key));
    return _processBlocks(cipher, plaintext, 16);
  }

  Uint8List _aesEcbDecrypt(Uint8List ciphertext, Uint8List key) {
    final cipher = ECBBlockCipher(AESEngine())
      ..init(false, pc.KeyParameter(key));
    return _processBlocks(cipher, ciphertext, 16);
  }

  Uint8List _aesCbcEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processBlocks(cipher, plaintext, 16);
  }

  Uint8List _aesCbcDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processBlocks(cipher, ciphertext, 16);
  }

  Uint8List _aesCfbEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = CFBBlockCipher(AESEngine(), 128)
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(plaintext);
  }

  Uint8List _aesCfbDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CFBBlockCipher(AESEngine(), 128)
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(ciphertext);
  }

  Uint8List _aesOfbEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = OFBBlockCipher(AESEngine(), 128)
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(plaintext);
  }

  Uint8List _aesOfbDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = OFBBlockCipher(AESEngine(), 128)
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(ciphertext);
  }

  Uint8List _aesCtrEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(plaintext);
  }

  Uint8List _aesCtrDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(ciphertext);
  }

  // ============ TEA / XTEA ============

  Uint8List _teaEncrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = 0;

      for (var j = 0; j < 32; j++) {
        sum = (sum + delta) & 0xFFFFFFFF;
        v0 =
            (v0 + ((((v1 << 4) + k[0]) ^ (v1 + sum)) ^ ((v1 >> 5) + k[1]))) &
            0xFFFFFFFF;
        v1 =
            (v1 + ((((v0 << 4) + k[2]) ^ (v0 + sum)) ^ ((v0 >> 5) + k[3]))) &
            0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  Uint8List _teaDecrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = (delta * 32) & 0xFFFFFFFF;

      for (var j = 0; j < 32; j++) {
        v1 =
            (v1 - ((((v0 << 4) + k[2]) ^ (v0 + sum)) ^ ((v0 >> 5) + k[3]))) &
            0xFFFFFFFF;
        v0 =
            (v0 - ((((v1 << 4) + k[0]) ^ (v1 + sum)) ^ ((v1 >> 5) + k[1]))) &
            0xFFFFFFFF;
        sum = (sum - delta) & 0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  Uint8List _xteaEncrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = 0;

      for (var j = 0; j < 32; j++) {
        v0 =
            (v0 + ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + k[sum & 3]))) &
            0xFFFFFFFF;
        sum = (sum + delta) & 0xFFFFFFFF;
        v1 =
            (v1 +
                ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + k[(sum >> 11) & 3]))) &
            0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  Uint8List _xteaDecrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = (delta * 32) & 0xFFFFFFFF;

      for (var j = 0; j < 32; j++) {
        v1 =
            (v1 -
                ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + k[(sum >> 11) & 3]))) &
            0xFFFFFFFF;
        sum = (sum - delta) & 0xFFFFFFFF;
        v0 =
            (v0 - ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + k[sum & 3]))) &
            0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  int _bytesToUint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  List<int> _bytesToUint32List(Uint8List bytes) {
    final result = <int>[];
    for (var i = 0; i < bytes.length; i += 4) {
      result.add(_bytesToUint32(bytes, i));
    }
    return result;
  }

  List<int> _uint32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  // ============ Classical Ciphers ============

  String _vigenereEncrypt(String plaintext, String key) {
    final keyUpper = key.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (keyUpper.isEmpty) return plaintext;

    final result = StringBuffer();
    var keyIndex = 0;

    for (final char in plaintext.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final charValue = char - base;
        final keyValue = keyUpper.codeUnitAt(keyIndex % keyUpper.length) - 65;
        final encrypted = (charValue + keyValue) % 26;
        result.writeCharCode(base + encrypted);
        keyIndex++;
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  String _vigenereDecrypt(String ciphertext, String key) {
    final keyUpper = key.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (keyUpper.isEmpty) return ciphertext;

    final result = StringBuffer();
    var keyIndex = 0;

    for (final char in ciphertext.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final charValue = char - base;
        final keyValue = keyUpper.codeUnitAt(keyIndex % keyUpper.length) - 65;
        final decrypted = (charValue - keyValue + 26) % 26;
        result.writeCharCode(base + decrypted);
        keyIndex++;
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  String _caesarEncrypt(String text, int shift) {
    final normalizedShift = ((shift % 26) + 26) % 26;
    final result = StringBuffer();

    for (final char in text.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final shifted = (char - base + normalizedShift) % 26;
        result.writeCharCode(base + shifted);
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  String _caesarDecrypt(String text, int shift) {
    return _caesarEncrypt(text, -shift);
  }

  String _atbashCipher(String text) {
    final result = StringBuffer();

    for (final char in text.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final mirrored = 25 - (char - base);
        result.writeCharCode(base + mirrored);
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  // ============ Utility ============

  Uint8List _hexToBytes(String hex) {
    hex = hex.replaceAll(' ', '').replaceAll('\n', '');
    if (hex.length % 2 != 0) throw Exception('Invalid hex length');
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  void _swapInputOutput() {
    final temp = _input.text;
    setState(() {
      _input.text = _output.text;
      _output.text = temp;
      _mode = _mode == 'Encrypt' ? 'Decrypt' : 'Encrypt';
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ensure algorithm is valid for current category
    if (!_algorithms.contains(_algorithm)) {
      _algorithm = _algorithms.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Controls row 1: Category & Algorithm
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Category:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SmallDropdown(
                  items: _categories,
                  initialValue: _category,
                  onChanged: (v) => setState(() {
                    _category = v;
                    _algorithm = _algorithmsByCategory[v]!.first;
                  }),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Algorithm:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SmallDropdown(
                  items: _algorithms,
                  initialValue: _algorithm,
                  onChanged: (v) => setState(() => _algorithm = v),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Mode:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SegmentedToggle(
                  options: const ['Encrypt', 'Decrypt'],
                  initialIndex: _mode == 'Encrypt' ? 0 : 1,
                  onChanged: (i) =>
                      setState(() => _mode = i == 0 ? 'Encrypt' : 'Decrypt'),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Output:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SegmentedToggle(
                  options: const ['Base64', 'Hex'],
                  initialIndex: _outputFormat == 'Base64' ? 0 : 1,
                  onChanged: (i) =>
                      setState(() => _outputFormat = i == 0 ? 'Base64' : 'Hex'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Key input row
        Row(
          children: [
            const Text(
              'Password/Key:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFD5D5D5)),
                ),
                child: TextField(
                  controller: _key,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Enter password for encryption/decryption...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) => _process(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Input/Output editors
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: EditorPane(
                  label: _mode == 'Encrypt' ? 'Plaintext' : 'Ciphertext',
                  actions: [
                    ToolButton(label: 'Go', onPressed: _process),
                    ToolButton(
                      label: 'Clipboard',
                      onPressed: () async {
                        final text = await _readClipboardText();
                        setState(() => _input.text = text);
                        _process();
                      },
                    ),
                    ToolButton(
                      label: 'Sample',
                      onPressed: () {
                        setState(
                          () => _input.text =
                              'Hello, World! This is a secret message.',
                        );
                        _process();
                      },
                    ),
                    ToolButton(
                      label: 'Clear',
                      onPressed: () {
                        setState(() {
                          _input.clear();
                          _output.clear();
                          _error = null;
                        });
                      },
                    ),
                  ],
                  controller: _input,
                  onChanged: (_) => _process(),
                  placeholder: _mode == 'Encrypt'
                      ? 'Enter text to encrypt...'
                      : 'Enter ciphertext to decrypt...',
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.swap_horiz),
                    tooltip: 'Swap & toggle mode',
                    onPressed: _swapInputOutput,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorPane(
                  label: _mode == 'Encrypt' ? 'Ciphertext' : 'Plaintext',
                  actions: [
                    ToolButton(
                      label: 'Copy',
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _output.text)),
                    ),
                  ],
                  controller: _output,
                  readOnly: true,
                  placeholder: _mode == 'Encrypt'
                      ? 'Encrypted output appears here...'
                      : 'Decrypted output appears here...',
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
      ],
    );
  }
}

class _UserAgentToolView extends StatefulWidget {
  const _UserAgentToolView();

  @override
  State<_UserAgentToolView> createState() => _UserAgentToolViewState();
}

class _UserAgentToolViewState extends State<_UserAgentToolView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _browser = 'Chrome';
  String _platform = 'Any';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _generate() {
    final platform = _platform == 'Any'
        ? null
        : _UaPlatform.values.firstWhere((value) => value.label == _platform);
    final ua = _UaGenerator.generateFromSelection(_browser, platform);
    setState(() => _input.text = ua);
    _validate();
  }

  void _validate() {
    final result = _UaValidator.validate(_input.text);
    _output.text = _formatUserAgentResult(result);
    setState(() {});
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _validate();
  }

  void _setSample() {
    final sample = _UaGenerator.generate(
      browser: _UaBrowser.chrome,
      platform: _UaPlatform.macOS,
    );
    setState(() => _input.text = sample);
    _validate();
  }

  void _clear() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputLabel: 'User Agent',
      outputLabel: 'Analysis',
      inputActions: [
        ToolButton(label: 'Go', onPressed: _validate),
        ToolButton(label: 'Generate', onPressed: _generate),
        SmallDropdown(
          items: _UaGenerator.browserLabels,
          initialValue: _browser,
          onChanged: (value) => setState(() => _browser = value),
        ),
        SmallDropdown(
          items: _UaGenerator.platformLabels,
          initialValue: _platform,
          onChanged: (value) => setState(() => _platform = value),
        ),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clear),
      ],
      outputActions: [
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
      inputPlaceholder: 'Paste or generate a user agent...',
      outputPlaceholder: 'Analysis appears here...',
      onInputChanged: (_) => _validate(),
    );
  }
}

String _formatUserAgentResult(_UaValidationResult result) {
  final parsed = result.parsed;
  final buffer = StringBuffer();
  buffer.writeln('Summary: ${result.summary}');
  buffer.writeln('Score: ${result.score}');
  buffer.writeln('Valid: ${result.isValid ? "Yes" : "No"}');
  buffer.writeln('Confidence: ${(parsed.confidence * 100).round()}%');
  buffer.writeln('Length: ${parsed.raw.length}');
  if (parsed.isBot) {
    buffer.writeln('Bot: ${parsed.botName ?? "Unknown"}');
  }
  if (parsed.browser != null) {
    final browser = parsed.browser!;
    buffer.writeln('Browser: ${browser.name} ${browser.version}');
    if (browser.isWebView) {
      buffer.writeln('WebView: Yes');
    }
  }
  if (parsed.webView != null) {
    final webView = parsed.webView!;
    buffer.writeln('WebView App: ${webView.app}');
    if (webView.appVersion != null) {
      buffer.writeln('App Version: ${webView.appVersion}');
    }
    if (webView.buildId != null) {
      buffer.writeln('Build ID: ${webView.buildId}');
    }
    if (webView.additionalInfo.isNotEmpty) {
      buffer.writeln('App Details:');
      webView.additionalInfo.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
    }
  }
  if (parsed.platform != null) {
    final platform = parsed.platform!;
    final parts = [
      platform.name,
      if (platform.version != null) platform.version!,
      if (platform.architecture != null) '(${platform.architecture})',
    ];
    buffer.writeln('Platform: ${parts.join(' ')}');
  }
  if (parsed.device != null) {
    final device = parsed.device!;
    final parts = [
      device.type.name,
      if (device.model != null) device.model!,
      if (device.vendor != null) '(${device.vendor})',
    ];
    buffer.writeln('Device: ${parts.join(' ')}');
  }
  if (parsed.engine != null) {
    final engine = parsed.engine!;
    buffer.writeln(
      'Engine: ${engine.name}${engine.version != null ? " ${engine.version}" : ""}',
    );
  }
  if (parsed.issues.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Issues:');
    for (final issue in parsed.issues) {
      buffer.writeln(
        '  ${issue.severity.name.toUpperCase()}: ${issue.message}',
      );
    }
  }
  return buffer.toString().trimRight();
}

enum _UaBrowser {
  chrome('Chrome'),
  safari('Safari'),
  firefox('Firefox'),
  edge('Edge'),
  brave('Brave'),
  chromium('Chromium'),
  facebook('Facebook'),
  instagram('Instagram'),
  twitter('Twitter'),
  tiktok('TikTok'),
  linkedin('LinkedIn'),
  snapchat('Snapchat'),
  pinterest('Pinterest'),
  whatsapp('WhatsApp'),
  telegram('Telegram'),
  discord('Discord'),
  slack('Slack'),
  wechat('WeChat'),
  line('Line');

  const _UaBrowser(this.label);
  final String label;
}

enum _UaPlatform {
  macOS('macOS'),
  windows('Windows'),
  linux('Linux'),
  iOS('iOS'),
  android('Android');

  const _UaPlatform(this.label);
  final String label;
}

class _UaGenerator {
  static final Random _rand = Random();

  static const List<String> chromeVersions = [
    '120.0.6099.109',
    '121.0.6167.85',
    '122.0.6261.94',
    '123.0.6312.58',
    '124.0.6367.91',
    '125.0.6422.76',
    '126.0.6478.126',
    '127.0.6533.72',
    '128.0.6613.84',
    '129.0.6668.70',
    '130.0.6723.91',
    '131.0.6778.85',
  ];

  static const List<String> chromiumVersions = [
    '120.0.6099.0',
    '121.0.6167.0',
    '122.0.6261.0',
    '123.0.6312.0',
    '124.0.6367.0',
    '125.0.6422.0',
    '126.0.6478.0',
    '127.0.6533.0',
    '128.0.6613.0',
    '129.0.6668.0',
    '130.0.6723.0',
    '131.0.6778.0',
  ];

  static const List<String> braveVersions = [
    '1.60.125',
    '1.61.109',
    '1.62.153',
    '1.63.165',
    '1.64.109',
    '1.65.132',
    '1.66.110',
    '1.67.123',
    '1.68.134',
    '1.69.153',
    '1.70.117',
    '1.71.114',
  ];

  static const List<String> firefoxVersions = [
    '121.0',
    '122.0',
    '123.0',
    '124.0',
    '125.0',
    '126.0',
    '127.0',
    '128.0',
    '129.0',
    '130.0',
    '131.0',
    '132.0',
  ];

  static const List<String> safariVersions = [
    '17.0',
    '17.1',
    '17.2',
    '17.3',
    '17.4',
    '17.5',
    '17.6',
    '18.0',
    '18.1',
  ];

  static const List<String> edgeVersions = [
    '120.0.2210.91',
    '121.0.2277.83',
    '122.0.2365.66',
    '123.0.2420.65',
    '124.0.2478.67',
    '125.0.2535.51',
    '126.0.2592.68',
    '127.0.2651.74',
    '128.0.2739.42',
    '129.0.2792.52',
    '130.0.2849.56',
    '131.0.2903.63',
  ];

  static const List<String> facebookAppVersions = [
    '450.0.0.40.109',
    '451.0.0.41.110',
    '452.0.0.42.111',
    '453.0.0.43.112',
    '454.0.0.44.113',
  ];
  static const List<String> instagramAppVersions = [
    '312.0.0.34.111',
    '313.0.0.35.112',
    '314.0.0.36.113',
    '315.0.0.37.114',
    '316.0.0.38.115',
  ];
  static const List<String> twitterAppVersions = [
    '10.23.0',
    '10.24.0',
    '10.25.0',
    '10.26.0',
    '10.27.0',
    '10.28.0',
  ];
  static const List<String> tiktokAppVersions = [
    '32.5.3',
    '32.6.4',
    '32.7.5',
    '33.0.3',
    '33.1.4',
    '33.2.5',
  ];
  static const List<String> linkedinAppVersions = [
    '9.29.5421',
    '9.30.5432',
    '9.31.5443',
    '9.32.5454',
    '9.33.5465',
  ];
  static const List<String> snapchatAppVersions = [
    '12.75.0.38',
    '12.76.0.39',
    '12.77.0.40',
    '12.78.0.41',
    '12.79.0.42',
  ];
  static const List<String> pinterestAppVersions = [
    '11.38.0',
    '11.39.0',
    '11.40.0',
    '11.41.0',
    '11.42.0',
  ];
  static const List<String> whatsappAppVersions = [
    '2.24.2.76',
    '2.24.3.77',
    '2.24.4.78',
    '2.24.5.79',
    '2.24.6.80',
  ];
  static const List<String> telegramAppVersions = [
    '10.6.2',
    '10.7.3',
    '10.8.4',
    '10.9.5',
    '10.10.6',
  ];
  static const List<String> discordAppVersions = [
    '223.0',
    '224.0',
    '225.0',
    '226.0',
    '227.0',
  ];
  static const List<String> slackAppVersions = [
    '24.01.10',
    '24.02.11',
    '24.03.12',
    '24.04.13',
    '24.05.14',
  ];
  static const List<String> wechatAppVersions = [
    '8.0.43',
    '8.0.44',
    '8.0.45',
    '8.0.46',
    '8.0.47',
  ];
  static const List<String> lineAppVersions = [
    '14.0.1',
    '14.1.2',
    '14.2.3',
    '14.3.4',
    '14.4.5',
  ];

  static const List<_UaPair> macOSVersions = [
    _UaPair('10_15_7', '10.15.7'),
    _UaPair('11_7_10', '11.7.10'),
    _UaPair('12_7_6', '12.7.6'),
    _UaPair('13_6_9', '13.6.9'),
    _UaPair('14_6_1', '14.6.1'),
    _UaPair('15_1', '15.1'),
  ];

  static const List<_UaPair> windowsVersions = [
    _UaPair('10.0; Win64; x64', '10'),
    _UaPair('10.0; Win64; x64', '11'),
  ];

  static const List<String> iOSVersions = [
    '16_6',
    '17_0',
    '17_1',
    '17_2',
    '17_3',
    '17_4',
    '17_5',
    '17_6',
    '18_0',
    '18_1',
  ];

  static const List<String> androidVersions = ['11', '12', '13', '14', '15'];

  static const List<_UaPair> iPhoneModels = [
    _UaPair('iPhone13,2', 'iPhone 12'),
    _UaPair('iPhone13,3', 'iPhone 12 Pro'),
    _UaPair('iPhone13,4', 'iPhone 12 Pro Max'),
    _UaPair('iPhone14,5', 'iPhone 13'),
    _UaPair('iPhone14,2', 'iPhone 13 Pro'),
    _UaPair('iPhone14,3', 'iPhone 13 Pro Max'),
    _UaPair('iPhone14,7', 'iPhone 14'),
    _UaPair('iPhone14,8', 'iPhone 14 Plus'),
    _UaPair('iPhone15,2', 'iPhone 14 Pro'),
    _UaPair('iPhone15,3', 'iPhone 14 Pro Max'),
    _UaPair('iPhone15,4', 'iPhone 15'),
    _UaPair('iPhone15,5', 'iPhone 15 Plus'),
    _UaPair('iPhone16,1', 'iPhone 15 Pro'),
    _UaPair('iPhone16,2', 'iPhone 15 Pro Max'),
    _UaPair('iPhone17,1', 'iPhone 16'),
    _UaPair('iPhone17,2', 'iPhone 16 Plus'),
    _UaPair('iPhone17,3', 'iPhone 16 Pro'),
    _UaPair('iPhone17,4', 'iPhone 16 Pro Max'),
  ];

  static const List<_UaDevice> androidDevices = [
    _UaDevice('Samsung', 'SM-S911B', 'Galaxy S23'),
    _UaDevice('Samsung', 'SM-S918B', 'Galaxy S23 Ultra'),
    _UaDevice('Samsung', 'SM-S921B', 'Galaxy S24'),
    _UaDevice('Samsung', 'SM-S928B', 'Galaxy S24 Ultra'),
    _UaDevice('Samsung', 'SM-A546B', 'Galaxy A54'),
    _UaDevice('Samsung', 'SM-A556B', 'Galaxy A55'),
    _UaDevice('Google', 'Pixel 7', 'Pixel 7'),
    _UaDevice('Google', 'Pixel 7 Pro', 'Pixel 7 Pro'),
    _UaDevice('Google', 'Pixel 8', 'Pixel 8'),
    _UaDevice('Google', 'Pixel 8 Pro', 'Pixel 8 Pro'),
    _UaDevice('Google', 'Pixel 9', 'Pixel 9'),
    _UaDevice('Google', 'Pixel 9 Pro', 'Pixel 9 Pro'),
    _UaDevice('OnePlus', 'CPH2449', 'OnePlus 11'),
    _UaDevice('OnePlus', 'CPH2551', 'OnePlus 12'),
    _UaDevice('Xiaomi', '2312DRA50G', 'Xiaomi 14'),
    _UaDevice('Xiaomi', '2311DRK48G', 'Xiaomi 14 Pro'),
    _UaDevice('Oppo', 'CPH2551', 'Find X7'),
    _UaDevice('Huawei', 'ALN-AL00', 'Mate 60 Pro'),
  ];

  static const String webkitVersion = '537.36';
  static const String geckoVersion = '20100101';
  static const List<String> facebookBuildIds = [
    '477985655',
    '478012312',
    '478123456',
    '478234567',
    '478345678',
  ];

  static const List<String> browserLabels = [
    'Random',
    'Random Standard',
    'Random WebView',
    'Chrome',
    'Safari',
    'Firefox',
    'Edge',
    'Brave',
    'Chromium',
    'Facebook',
    'Instagram',
    'Twitter',
    'TikTok',
    'LinkedIn',
    'Snapchat',
    'Pinterest',
    'WhatsApp',
    'Telegram',
    'Discord',
    'Slack',
    'WeChat',
    'Line',
  ];

  static const List<String> platformLabels = [
    'Any',
    'macOS',
    'Windows',
    'Linux',
    'iOS',
    'Android',
  ];

  static String generateFromSelection(String selection, _UaPlatform? platform) {
    if (selection == 'Random') {
      return random();
    }
    if (selection == 'Random Standard') {
      return randomStandardBrowser();
    }
    if (selection == 'Random WebView') {
      return randomWebView();
    }
    final browser = _UaBrowser.values.firstWhere(
      (value) => value.label == selection,
    );
    return generate(browser: browser, platform: platform);
  }

  static String generate({
    required _UaBrowser browser,
    _UaPlatform? platform,
    String? version,
  }) {
    final _UaPlatform platformValue = platform ?? _pick(_UaPlatform.values);
    switch (browser) {
      case _UaBrowser.chrome:
        return _generateChrome(platformValue, version);
      case _UaBrowser.safari:
        return _generateSafari(platformValue, version);
      case _UaBrowser.firefox:
        return _generateFirefox(platformValue, version);
      case _UaBrowser.edge:
        return _generateEdge(platformValue, version);
      case _UaBrowser.brave:
        return _generateBrave(platformValue, version);
      case _UaBrowser.chromium:
        return _generateChromium(platformValue, version);
      case _UaBrowser.facebook:
        return _generateFacebook(platformValue, version);
      case _UaBrowser.instagram:
        return _generateInstagram(platformValue, version);
      case _UaBrowser.twitter:
        return _generateTwitter(platformValue, version);
      case _UaBrowser.tiktok:
        return _generateTikTok(platformValue, version);
      case _UaBrowser.linkedin:
        return _generateLinkedIn(platformValue, version);
      case _UaBrowser.snapchat:
        return _generateSnapchat(platformValue, version);
      case _UaBrowser.pinterest:
        return _generatePinterest(platformValue, version);
      case _UaBrowser.whatsapp:
        return _generateWhatsApp(platformValue, version);
      case _UaBrowser.telegram:
        return _generateTelegram(platformValue, version);
      case _UaBrowser.discord:
        return _generateDiscord(platformValue, version);
      case _UaBrowser.slack:
        return _generateSlack(platformValue, version);
      case _UaBrowser.wechat:
        return _generateWeChat(platformValue, version);
      case _UaBrowser.line:
        return _generateLine(platformValue, version);
    }
  }

  static String random() {
    return generate(
      browser: _pick(_UaBrowser.values),
      platform: _pick(_UaPlatform.values),
    );
  }

  static String randomStandardBrowser() {
    const standard = [
      _UaBrowser.chrome,
      _UaBrowser.safari,
      _UaBrowser.firefox,
      _UaBrowser.edge,
      _UaBrowser.brave,
      _UaBrowser.chromium,
    ];
    return generate(
      browser: _pick(standard),
      platform: _pick(_UaPlatform.values),
    );
  }

  static String randomWebView() {
    const webviews = [
      _UaBrowser.facebook,
      _UaBrowser.instagram,
      _UaBrowser.twitter,
      _UaBrowser.tiktok,
      _UaBrowser.linkedin,
      _UaBrowser.snapchat,
      _UaBrowser.pinterest,
      _UaBrowser.whatsapp,
      _UaBrowser.telegram,
      _UaBrowser.discord,
      _UaBrowser.slack,
      _UaBrowser.wechat,
      _UaBrowser.line,
    ];
    const platforms = [_UaPlatform.iOS, _UaPlatform.android];
    return generate(browser: _pick(webviews), platform: _pick(platforms));
  }

  static String _generateChrome(_UaPlatform platform, String? version) {
    final chromeVersion = version ?? _pick(chromeVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/$webkitVersion (KHTML, like Gecko) CriOS/$chromeVersion Mobile/15E148 Safari/$webkitVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Mobile Safari/$webkitVersion';
    }
  }

  static String _generateChromium(_UaPlatform platform, String? version) {
    final chromiumVersion = version ?? _pick(chromiumVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Safari/$webkitVersion';
      case _UaPlatform.iOS:
        return _generateChrome(_UaPlatform.iOS, version);
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Mobile Safari/$webkitVersion';
    }
  }

  static String _generateBrave(_UaPlatform platform, String? version) {
    final braveVersion = version ?? _pick(braveVersions);
    final chromeVersion = _pick(chromeVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Brave/$braveVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Brave/$braveVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Brave/$braveVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final safariVersion = _pick(safariVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariVersion Mobile/15E148 Safari/604.1 Brave/$braveVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Mobile Safari/$webkitVersion Brave/$braveVersion';
    }
  }

  static String _generateSafari(_UaPlatform platform, String? version) {
    final safariVersion = version ?? _pick(safariVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariVersion Safari/605.1.15';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariVersion Mobile/15E148 Safari/604.1';
      case _UaPlatform.windows:
      case _UaPlatform.linux:
      case _UaPlatform.android:
        return _generateSafari(_UaPlatform.macOS, version);
    }
  }

  static String _generateFirefox(_UaPlatform platform, String? version) {
    final firefoxVersion = version ?? _pick(firefoxVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer; rv:$firefoxVersion) Gecko/$geckoVersion Firefox/$firefoxVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer; rv:$firefoxVersion) Gecko/$geckoVersion Firefox/$firefoxVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64; rv:$firefoxVersion) Gecko/$geckoVersion Firefox/$firefoxVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/$firefoxVersion Mobile/15E148 Safari/605.1.15';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        return 'Mozilla/5.0 (Android $androidVer; Mobile; rv:$firefoxVersion) Gecko/$firefoxVersion Firefox/$firefoxVersion';
    }
  }

  static String _generateEdge(_UaPlatform platform, String? version) {
    final edgeVersion = version ?? _pick(edgeVersions);
    final chromeVersion = _pick(chromeVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Edg/$edgeVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Edg/$edgeVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Edg/$edgeVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final safariVersion = _pick(safariVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/$safariVersion EdgiOS/$edgeVersion Mobile/15E148 Safari/$webkitVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Mobile Safari/$webkitVersion EdgA/$edgeVersion';
    }
  }

  static String _generateFacebook(_UaPlatform platform, String? version) {
    final fbVersion = version ?? _pick(facebookAppVersions);
    final buildId = _pick(facebookBuildIds);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final deviceId = _pick(iPhoneModels).key;
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/$fbVersion;FBBV/$buildId;FBDV/$deviceId;FBMD/iPhone;FBSN/iOS;FBSV/${iosVer.replaceAll("_", ".")};FBSS/3;FBID/phone;FBLC/en_US;FBOP/5]';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices);
        final dpi = _pick(['240', '320', '480', '640']);
        return 'Mozilla/5.0 (Linux; Android $androidVer; ${device.model} Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion [FB_IAB/FB4A;FBAV/$fbVersion;FBBV/$buildId;FBDM/{density=$dpi.0,width=1080,height=2340};FBLC/en_US;FBRV/$buildId;FBCR/;FBMF/${device.vendor};FBBD/${device.vendor};FBPN/com.facebook.katana;FBDV/${device.model};FBSV/$androidVer;FBOP/1;FBCA/armeabi-v7a:armeabi;]';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateFacebook(_UaPlatform.iOS, version);
    }
  }

  static String _generateInstagram(_UaPlatform platform, String? version) {
    final igVersion = version ?? _pick(instagramAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram $igVersion (iPhone; iOS ${iosVer.replaceAll("_", ".")}); en_US; en-US; scale=3.00; 1170x2532; ${_pick(facebookBuildIds)})';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices);
        return 'Mozilla/5.0 (Linux; Android $androidVer; ${device.model} Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Instagram $igVersion Android ($androidVer/${device.model}; 480dpi; 1080x2340; ${device.vendor}; ${device.model}; ${device.model.toLowerCase()}; qcom; en_US; ${_pick(facebookBuildIds)})';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateInstagram(_UaPlatform.iOS, version);
    }
  }

  static String _generateTwitter(_UaPlatform platform, String? version) {
    final twitterVersion = version ?? _pick(twitterAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Twitter for iPhone/$twitterVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Twitter for Android/$twitterVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateTwitter(_UaPlatform.iOS, version);
    }
  }

  static String _generateTikTok(_UaPlatform platform, String? version) {
    final tiktokVersion = version ?? _pick(tiktokAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final deviceId = _pick(iPhoneModels).key;
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 BytedanceWebview/d8a21c6 musical_ly_$tiktokVersion JsSdk/1.0 NetType/WIFI Channel/App Store ByteLocale/en Region/US FalconTag/$deviceId';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices);
        return 'Mozilla/5.0 (Linux; Android $androidVer; ${device.model} Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion trill/$tiktokVersion BytedanceWebview/d8a21c6 JsSdk/1.0 NetType/wifi Channel/googleplay AppName/musical_ly app_version/$tiktokVersion ByteLocale/en Region/US';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateTikTok(_UaPlatform.iOS, version);
    }
  }

  static String _generateLinkedIn(_UaPlatform platform, String? version) {
    final linkedinVersion = version ?? _pick(linkedinAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [LinkedInApp]/$linkedinVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion [LinkedInApp]/$linkedinVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateLinkedIn(_UaPlatform.iOS, version);
    }
  }

  static String _generateSnapchat(_UaPlatform platform, String? version) {
    final snapVersion = version ?? _pick(snapchatAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Snapchat/$snapVersion (iPhone; iOS ${iosVer.replaceAll("_", ".")}; Scale/3.00)';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Snapchat/$snapVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateSnapchat(_UaPlatform.iOS, version);
    }
  }

  static String _generatePinterest(_UaPlatform platform, String? version) {
    final pinterestVersion = version ?? _pick(pinterestAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [Pinterest/iOS $pinterestVersion]';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion [Pinterest/Android $pinterestVersion]';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generatePinterest(_UaPlatform.iOS, version);
    }
  }

  static String _generateWhatsApp(_UaPlatform platform, String? version) {
    final waVersion = version ?? _pick(whatsappAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 WhatsApp/$waVersion w';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion WhatsApp/$waVersion a';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateWhatsApp(_UaPlatform.iOS, version);
    }
  }

  static String _generateTelegram(_UaPlatform platform, String? version) {
    final tgVersion = version ?? _pick(telegramAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Telegram-iOS/$tgVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion TelegramAndroid/$tgVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateTelegram(_UaPlatform.iOS, version);
    }
  }

  static String _generateDiscord(_UaPlatform platform, String? version) {
    final discordVersion = version ?? _pick(discordAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Discord/$discordVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion discord/$discordVersion';
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) discord/$discordVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) discord/$discordVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) discord/$discordVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
    }
  }

  static String _generateSlack(_UaPlatform platform, String? version) {
    final slackVersion = version ?? _pick(slackAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Slack/$slackVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Slack/$slackVersion';
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Slack/$slackVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Slack/$slackVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Slack/$slackVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
    }
  }

  static String _generateWeChat(_UaPlatform platform, String? version) {
    final wechatVersion = version ?? _pick(wechatAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/$wechatVersion NetType/WIFI Language/en';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion MicroMessenger/$wechatVersion NetType/WIFI Language/en';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateWeChat(_UaPlatform.iOS, version);
    }
  }

  static String _generateLine(_UaPlatform platform, String? version) {
    final lineVersion = version ?? _pick(lineAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari Line/$lineVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Line/$lineVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateLine(_UaPlatform.iOS, version);
    }
  }

  static T _pick<T>(List<T> items) => items[_rand.nextInt(items.length)];
}

class _UaPair {
  const _UaPair(this.key, this.value);
  final String key;
  final String value;
}

class _UaDevice {
  const _UaDevice(this.vendor, this.model, this.name);
  final String vendor;
  final String model;
  final String name;
}

class _UaValidationResult {
  const _UaValidationResult({
    required this.isValid,
    required this.parsed,
    required this.score,
    required this.summary,
  });

  final bool isValid;
  final _UaParsedUserAgent parsed;
  final int score;
  final String summary;
}

class _UaParsedUserAgent {
  const _UaParsedUserAgent({
    required this.raw,
    required this.browser,
    required this.platform,
    required this.device,
    required this.engine,
    required this.webView,
    required this.isBot,
    required this.botName,
    required this.isValid,
    required this.issues,
    required this.confidence,
  });

  final String raw;
  final _UaBrowserInfo? browser;
  final _UaPlatformInfo? platform;
  final _UaDeviceInfo? device;
  final _UaEngineInfo? engine;
  final _UaWebViewInfo? webView;
  final bool isBot;
  final String? botName;
  final bool isValid;
  final List<_UaValidationIssue> issues;
  final double confidence;
}

class _UaBrowserInfo {
  const _UaBrowserInfo({
    required this.name,
    required this.version,
    required this.majorVersion,
    required this.isWebView,
  });

  final String name;
  final String version;
  final int? majorVersion;
  final bool isWebView;
}

class _UaPlatformInfo {
  const _UaPlatformInfo({
    required this.name,
    required this.version,
    required this.architecture,
  });

  final String name;
  final String? version;
  final String? architecture;
}

class _UaDeviceInfo {
  const _UaDeviceInfo({
    required this.type,
    required this.model,
    required this.vendor,
  });

  final _UaDeviceType type;
  final String? model;
  final String? vendor;
}

class _UaEngineInfo {
  const _UaEngineInfo({required this.name, required this.version});
  final String name;
  final String? version;
}

class _UaWebViewInfo {
  const _UaWebViewInfo({
    required this.app,
    required this.appVersion,
    required this.buildId,
    required this.additionalInfo,
  });

  final String app;
  final String? appVersion;
  final String? buildId;
  final Map<String, String> additionalInfo;
}

enum _UaDeviceType { desktop, mobile, tablet, tv, bot, unknown }

class _UaValidationIssue {
  const _UaValidationIssue({
    required this.severity,
    required this.message,
    required this.field,
  });

  final _UaIssueSeverity severity;
  final String message;
  final String? field;
}

enum _UaIssueSeverity { error, warning, info }

class _UaRange {
  const _UaRange(this.min, this.max);
  final int min;
  final int max;
  bool contains(int value) => value >= min && value <= max;
}

class _UaValidator {
  static const List<_UaBotPattern> botPatterns = [
    _UaBotPattern('googlebot', 'Googlebot'),
    _UaBotPattern('bingbot', 'Bingbot'),
    _UaBotPattern('slurp', 'Yahoo Slurp'),
    _UaBotPattern('duckduckbot', 'DuckDuckBot'),
    _UaBotPattern('baiduspider', 'Baiduspider'),
    _UaBotPattern('yandexbot', 'YandexBot'),
    _UaBotPattern('facebookexternalhit', 'Facebook Bot'),
    _UaBotPattern('twitterbot', 'Twitter Bot'),
    _UaBotPattern('linkedinbot', 'LinkedIn Bot'),
    _UaBotPattern('applebot', 'Applebot'),
    _UaBotPattern('semrushbot', 'SEMrush Bot'),
    _UaBotPattern('ahrefsbot', 'Ahrefs Bot'),
    _UaBotPattern('mj12bot', 'Majestic Bot'),
    _UaBotPattern('dotbot', 'Moz Bot'),
    _UaBotPattern('rogerbot', 'Moz Bot'),
    _UaBotPattern('screaming frog', 'Screaming Frog'),
    _UaBotPattern('crawler', 'Generic Crawler'),
    _UaBotPattern('spider', 'Generic Spider'),
    _UaBotPattern('scraper', 'Scraper'),
    _UaBotPattern('headless', 'Headless Browser'),
    _UaBotPattern('phantom', 'PhantomJS'),
    _UaBotPattern('selenium', 'Selenium'),
    _UaBotPattern('puppeteer', 'Puppeteer'),
    _UaBotPattern('playwright', 'Playwright'),
    _UaBotPattern('wget', 'Wget'),
    _UaBotPattern('curl', 'cURL'),
    _UaBotPattern('python-requests', 'Python Requests'),
    _UaBotPattern('python-urllib', 'Python urllib'),
    _UaBotPattern('java/', 'Java Client'),
    _UaBotPattern('libwww', 'libwww'),
    _UaBotPattern('httpclient', 'HTTP Client'),
    _UaBotPattern('okhttp', 'OkHttp'),
    _UaBotPattern('axios', 'Axios'),
    _UaBotPattern('node-fetch', 'Node Fetch'),
    _UaBotPattern('go-http-client', 'Go HTTP Client'),
    _UaBotPattern('guzzle', 'Guzzle'),
  ];

  static const List<_UaBrowserPattern> browserPatterns = [
    _UaBrowserPattern('[fban/fbios', 'Facebook iOS', 'FBAV/([\\d.]+)', true),
    _UaBrowserPattern(
      '[fb_iab/fb4a',
      'Facebook Android',
      'FBAV/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('instagram', 'Instagram', 'Instagram ([\\d.]+)', true),
    _UaBrowserPattern(
      'twitter for iphone',
      'Twitter iOS',
      'Twitter for iPhone/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern(
      'twitter for android',
      'Twitter Android',
      'Twitter for Android/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern(
      'bytedancewebview',
      'TikTok',
      'musical_ly[_/]([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('trill/', 'TikTok', 'trill/([\\d.]+)', true),
    _UaBrowserPattern(
      '[linkedinapp]',
      'LinkedIn',
      '\\[LinkedInApp\\]/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('snapchat/', 'Snapchat', 'Snapchat/([\\d.]+)', true),
    _UaBrowserPattern('[pinterest', 'Pinterest', 'Pinterest', true),
    _UaBrowserPattern('whatsapp/', 'WhatsApp', 'WhatsApp/([\\d.]+)', true),
    _UaBrowserPattern(
      'telegram-ios',
      'Telegram iOS',
      'Telegram-iOS/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern(
      'telegramandroid',
      'Telegram Android',
      'TelegramAndroid/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('discord/', 'Discord', 'discord/([\\d.]+)', true),
    _UaBrowserPattern('slack/', 'Slack', 'Slack/([\\d.]+)', true),
    _UaBrowserPattern(
      'micromessenger/',
      'WeChat',
      'MicroMessenger/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('line/', 'Line', 'Line/([\\d.]+)', true),
    _UaBrowserPattern('edg/', 'Edge', 'Edg/([\\d.]+)', false),
    _UaBrowserPattern('edga/', 'Edge Android', 'EdgA/([\\d.]+)', false),
    _UaBrowserPattern('edgios/', 'Edge iOS', 'EdgiOS/([\\d.]+)', false),
    _UaBrowserPattern('opr/', 'Opera', 'OPR/([\\d.]+)', false),
    _UaBrowserPattern('opera', 'Opera', 'Opera[/ ]([\\d.]+)', false),
    _UaBrowserPattern('vivaldi/', 'Vivaldi', 'Vivaldi/([\\d.]+)', false),
    _UaBrowserPattern(
      'yabrowser/',
      'Yandex Browser',
      'YaBrowser/([\\d.]+)',
      false,
    ),
    _UaBrowserPattern('brave/', 'Brave', 'Brave/([\\d.]+)', false),
    _UaBrowserPattern('chromium/', 'Chromium', 'Chromium/([\\d.]+)', false),
    _UaBrowserPattern(
      'samsungbrowser/',
      'Samsung Browser',
      'SamsungBrowser/([\\d.]+)',
      false,
    ),
    _UaBrowserPattern('ucbrowser/', 'UC Browser', 'UCBrowser/([\\d.]+)', false),
    _UaBrowserPattern('crios/', 'Chrome iOS', 'CriOS/([\\d.]+)', false),
    _UaBrowserPattern('fxios/', 'Firefox iOS', 'FxiOS/([\\d.]+)', false),
    _UaBrowserPattern('firefox/', 'Firefox', 'Firefox/([\\d.]+)', false),
    _UaBrowserPattern('chrome/', 'Chrome', 'Chrome/([\\d.]+)', false),
    _UaBrowserPattern('safari/', 'Safari', 'Version/([\\d.]+)', false),
  ];

  static const Map<String, _UaRange> validVersionRanges = {
    'Chrome': _UaRange(70, 140),
    'Chrome iOS': _UaRange(70, 140),
    'Chromium': _UaRange(70, 140),
    'Firefox': _UaRange(70, 140),
    'Firefox iOS': _UaRange(70, 140),
    'Safari': _UaRange(12, 19),
    'Edge': _UaRange(80, 140),
    'Edge Android': _UaRange(80, 140),
    'Edge iOS': _UaRange(80, 140),
    'Opera': _UaRange(60, 115),
    'Brave': _UaRange(1, 2),
    'Vivaldi': _UaRange(5, 7),
    'Samsung Browser': _UaRange(18, 27),
    'UC Browser': _UaRange(13, 16),
    'Yandex Browser': _UaRange(23, 25),
  };

  static const Map<String, _UaRange> validWebViewRanges = {
    'Facebook iOS': _UaRange(400, 500),
    'Facebook Android': _UaRange(400, 500),
    'Instagram': _UaRange(280, 350),
    'Twitter iOS': _UaRange(9, 12),
    'Twitter Android': _UaRange(9, 12),
    'TikTok': _UaRange(28, 40),
    'WhatsApp': _UaRange(2, 3),
    'WeChat': _UaRange(8, 9),
    'Telegram iOS': _UaRange(9, 12),
    'Telegram Android': _UaRange(9, 12),
    'Discord': _UaRange(200, 250),
    'Slack': _UaRange(23, 26),
    'Snapchat': _UaRange(12, 14),
    'Line': _UaRange(13, 16),
  };

  static _UaValidationResult validate(String userAgent) {
    final parsed = parse(userAgent);
    final score = _calculateScore(parsed);
    final isValid = parsed.isValid && score.score >= 50;
    return _UaValidationResult(
      isValid: isValid,
      parsed: parsed,
      score: score.score,
      summary: score.summary,
    );
  }

  static _UaParsedUserAgent parse(String userAgent) {
    final ua = userAgent.trim();
    final issues = <_UaValidationIssue>[];

    if (ua.isEmpty) {
      return _UaParsedUserAgent(
        raw: ua,
        browser: null,
        platform: null,
        device: null,
        engine: null,
        webView: null,
        isBot: false,
        botName: null,
        isValid: false,
        issues: [
          const _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message: 'Empty user agent',
            field: null,
          ),
        ],
        confidence: 0,
      );
    }

    if (!ua.startsWith('Mozilla/') &&
        !_isKnownBot(ua) &&
        !_isKnownWebView(ua)) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Non-standard format: does not start with Mozilla/',
          field: 'format',
        ),
      );
    }

    final bot = _detectBot(ua);
    final browser = _parseBrowser(ua);
    if (browser == null && !bot.isBot) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Could not identify browser',
          field: 'browser',
        ),
      );
    }

    _UaWebViewInfo? webView;
    if (browser != null && browser.isWebView) {
      webView = _parseWebView(ua, browser.name);
    }

    if (browser != null && browser.majorVersion != null) {
      final major = browser.majorVersion!;
      if (browser.isWebView) {
        final range = validWebViewRanges[browser.name];
        if (range != null && !range.contains(major)) {
          issues.add(
            _UaValidationIssue(
              severity: major < range.min
                  ? _UaIssueSeverity.warning
                  : _UaIssueSeverity.info,
              message:
                  '${browser.name} version $major is outside expected range ${range.min}-${range.max}',
              field: 'browserVersion',
            ),
          );
        }
      } else {
        final range = validVersionRanges[browser.name];
        if (range != null && !range.contains(major)) {
          issues.add(
            _UaValidationIssue(
              severity: major < range.min
                  ? _UaIssueSeverity.warning
                  : _UaIssueSeverity.info,
              message:
                  '${browser.name} version $major is outside expected range ${range.min}-${range.max}',
              field: 'browserVersion',
            ),
          );
        }
      }
    }

    final platform = _parsePlatform(ua);
    if (platform == null && !bot.isBot) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Could not identify platform/OS',
          field: 'platform',
        ),
      );
    }

    final device = _parseDevice(
      ua,
      isBot: bot.isBot,
      isWebView: browser?.isWebView ?? false,
    );
    final engine = _parseEngine(ua);
    issues.addAll(
      _validateCombinations(browser, platform, engine, webView, ua),
    );
    issues.addAll(_checkSuspiciousPatterns(ua));

    final confidence = _calculateConfidence(
      browser,
      platform,
      engine,
      webView,
      issues,
      bot.isBot,
    );
    final hasErrors = issues.any(
      (issue) => issue.severity == _UaIssueSeverity.error,
    );
    final isValid =
        !hasErrors && (browser != null || bot.isBot) && confidence > 0.3;

    return _UaParsedUserAgent(
      raw: ua,
      browser: browser,
      platform: platform,
      device: device,
      engine: engine,
      webView: webView,
      isBot: bot.isBot,
      botName: bot.name,
      isValid: isValid,
      issues: issues,
      confidence: confidence,
    );
  }

  static bool _isKnownWebView(String ua) {
    final lower = ua.toLowerCase();
    const indicators = [
      '[fban/',
      '[fb_iab/',
      'instagram',
      'twitter for',
      'bytedancewebview',
      'trill/',
      '[linkedinapp]',
      'snapchat/',
      '[pinterest',
      'whatsapp/',
      'telegram-ios',
      'telegramandroid',
      'discord/',
      'slack/',
      'micromessenger/',
      'line/',
    ];
    return indicators.any(lower.contains);
  }

  static bool _isKnownBot(String ua) => _detectBot(ua).isBot;

  static _UaBotResult _detectBot(String ua) {
    final lower = ua.toLowerCase();
    if (_isKnownWebView(ua)) {
      return const _UaBotResult(false, null);
    }
    for (final pattern in botPatterns) {
      if (lower.contains(pattern.pattern)) {
        return _UaBotResult(true, pattern.name);
      }
    }
    return const _UaBotResult(false, null);
  }

  static _UaBrowserInfo? _parseBrowser(String ua) {
    final lower = ua.toLowerCase();
    for (final pattern in browserPatterns) {
      if (lower.contains(pattern.pattern)) {
        final version = _extractVersion(ua, pattern.versionPattern);
        final major = version != null
            ? int.tryParse(version.split('.').first)
            : null;
        return _UaBrowserInfo(
          name: pattern.name,
          version: version ?? 'unknown',
          majorVersion: major,
          isWebView: pattern.isWebView,
        );
      }
    }
    return null;
  }

  static _UaWebViewInfo? _parseWebView(String ua, String appName) {
    final base = appName.replaceAll(' iOS', '').replaceAll(' Android', '');
    String? appVersion;
    String? buildId;
    final additional = <String, String>{};

    const patterns = [
      _UaWebViewPattern('Facebook', [
        _UaKeyPattern('appVersion', 'FBAV/([\\d.]+)'),
        _UaKeyPattern('buildId', 'FBBV/([\\d]+)'),
        _UaKeyPattern('device', 'FBDV/([^;\\]]+)'),
        _UaKeyPattern('osVersion', 'FBSV/([\\d.]+)'),
        _UaKeyPattern('locale', 'FBLC/([^;\\]]+)'),
      ]),
      _UaWebViewPattern('Instagram', [
        _UaKeyPattern('appVersion', 'Instagram ([\\d.]+)'),
        _UaKeyPattern('scale', 'scale=([\\d.]+)'),
        _UaKeyPattern('resolution', '(\\d+x\\d+)'),
      ]),
      _UaWebViewPattern('TikTok', [
        _UaKeyPattern('appVersion', '(?:musical_ly[_/]|trill/)([\\d.]+)'),
        _UaKeyPattern('channel', 'Channel/([^\\s]+)'),
        _UaKeyPattern('region', 'Region/([A-Z]+)'),
        _UaKeyPattern('locale', 'ByteLocale/([a-z]+)'),
      ]),
      _UaWebViewPattern('WhatsApp', [
        _UaKeyPattern('appVersion', 'WhatsApp/([\\d.]+)'),
        _UaKeyPattern('platform', 'WhatsApp/[\\d.]+ ([wa])'),
      ]),
      _UaWebViewPattern('WeChat', [
        _UaKeyPattern('appVersion', 'MicroMessenger/([\\d.]+)'),
        _UaKeyPattern('netType', 'NetType/([^\\s]+)'),
        _UaKeyPattern('language', 'Language/([a-z]+)'),
      ]),
      _UaWebViewPattern('Telegram', [
        _UaKeyPattern('appVersion', 'Telegram(?:-iOS|Android)/([\\d.]+)'),
      ]),
      _UaWebViewPattern('Discord', [
        _UaKeyPattern('appVersion', 'discord/([\\d.]+)'),
        _UaKeyPattern('electronVersion', 'Electron/([\\d.]+)'),
      ]),
      _UaWebViewPattern('Slack', [
        _UaKeyPattern('appVersion', 'Slack/([\\d.]+)'),
        _UaKeyPattern('electronVersion', 'Electron/([\\d.]+)'),
      ]),
    ];

    for (final pattern in patterns) {
      if (base.contains(pattern.app) || pattern.app.contains(base)) {
        for (final pair in pattern.patterns) {
          final value = _extractVersion(ua, pair.regex);
          if (value == null) continue;
          switch (pair.key) {
            case 'appVersion':
              appVersion = value;
              break;
            case 'buildId':
              buildId = value;
              break;
            default:
              additional[pair.key] = value;
          }
        }
        break;
      }
    }

    if (base.contains('Facebook')) {
      appVersion ??= _extractVersion(ua, 'FBAV/([\\d.]+)');
      buildId ??= _extractVersion(ua, 'FBBV/([\\d]+)');
      additional['device'] ??= _extractVersion(ua, 'FBDV/([^;\\]]+)') ?? '';
      additional['osVersion'] ??= _extractVersion(ua, 'FBSV/([\\d.]+)') ?? '';
      additional['locale'] ??= _extractVersion(ua, 'FBLC/([^;\\]]+)') ?? '';
    }

    if (appVersion == null && buildId == null && additional.isEmpty) {
      return null;
    }
    additional.removeWhere((key, value) => value.isEmpty);
    return _UaWebViewInfo(
      app: base,
      appVersion: appVersion,
      buildId: buildId,
      additionalInfo: additional,
    );
  }

  static _UaPlatformInfo? _parsePlatform(String ua) {
    final lower = ua.toLowerCase();
    if (lower.contains('macintosh') || lower.contains('mac os x')) {
      final version = _extractVersion(
        ua,
        'Mac OS X ([\\d_\\.]+)',
      )?.replaceAll('_', '.');
      final arch = ua.contains('Intel') ? 'x86_64' : 'arm64';
      return _UaPlatformInfo(
        name: 'macOS',
        version: version,
        architecture: arch,
      );
    }
    if (lower.contains('iphone') ||
        lower.contains('ipad') ||
        lower.contains('ipod')) {
      final version = _extractVersion(
        ua,
        '(?:CPU (?:iPhone )?OS |FBSV/)([\\d_\\.]+)',
      )?.replaceAll('_', '.');
      return _UaPlatformInfo(
        name: 'iOS',
        version: version,
        architecture: 'arm64',
      );
    }
    if (lower.contains('android')) {
      final version = _extractVersion(ua, 'Android ([\\d\\.]+)');
      return _UaPlatformInfo(
        name: 'Android',
        version: version,
        architecture: null,
      );
    }
    if (lower.contains('windows')) {
      String? version;
      if (lower.contains('windows nt 10')) {
        version = '10/11';
      } else if (lower.contains('windows nt 6.3')) {
        version = '8.1';
      } else if (lower.contains('windows nt 6.2')) {
        version = '8';
      } else if (lower.contains('windows nt 6.1')) {
        version = '7';
      }
      final arch = lower.contains('win64') || lower.contains('x64')
          ? 'x86_64'
          : 'x86';
      return _UaPlatformInfo(
        name: 'Windows',
        version: version,
        architecture: arch,
      );
    }
    if (lower.contains('linux') && !lower.contains('android')) {
      final arch = lower.contains('x86_64')
          ? 'x86_64'
          : (lower.contains('aarch64') ? 'arm64' : null);
      return _UaPlatformInfo(name: 'Linux', version: null, architecture: arch);
    }
    if (lower.contains('cros')) {
      return _UaPlatformInfo(
        name: 'Chrome OS',
        version: null,
        architecture: null,
      );
    }
    return null;
  }

  static _UaDeviceInfo? _parseDevice(
    String ua, {
    required bool isBot,
    required bool isWebView,
  }) {
    if (isBot) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.bot,
        model: null,
        vendor: null,
      );
    }
    final lower = ua.toLowerCase();
    if (lower.contains('iphone')) {
      final model = _extractVersion(ua, 'FBDV/([^;\\]]+)') ?? 'iPhone';
      return _UaDeviceInfo(
        type: _UaDeviceType.mobile,
        model: model,
        vendor: 'Apple',
      );
    }
    if (lower.contains('ipad')) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.tablet,
        model: 'iPad',
        vendor: 'Apple',
      );
    }
    if (lower.contains('android')) {
      String? model;
      String? vendor;
      final extracted = _extractVersion(ua, 'Android[^;]*;\\s*([^)]+)');
      if (extracted != null) {
        final cleaned = extracted.split(' Build').first.trim();
        model = cleaned;
        vendor = _detectVendor(cleaned);
      }
      final isTablet =
          lower.contains('tablet') ||
          (lower.contains('android') && !lower.contains('mobile'));
      return _UaDeviceInfo(
        type: isTablet ? _UaDeviceType.tablet : _UaDeviceType.mobile,
        model: model,
        vendor: vendor,
      );
    }
    if (lower.contains('smart-tv') ||
        lower.contains('smarttv') ||
        lower.contains('webos') ||
        lower.contains('tizen')) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.tv,
        model: null,
        vendor: null,
      );
    }
    if (lower.contains('windows') ||
        lower.contains('macintosh') ||
        (lower.contains('linux') && !lower.contains('android'))) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.desktop,
        model: null,
        vendor: null,
      );
    }
    if (isWebView) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.mobile,
        model: null,
        vendor: null,
      );
    }
    return const _UaDeviceInfo(
      type: _UaDeviceType.unknown,
      model: null,
      vendor: null,
    );
  }

  static String? _detectVendor(String model) {
    final lower = model.toLowerCase();
    if (lower.startsWith('sm-') || lower.contains('samsung')) return 'Samsung';
    if (lower.startsWith('pixel')) return 'Google';
    if (lower.contains('oneplus') || lower.startsWith('cph')) return 'OnePlus';
    if (lower.contains('xiaomi') ||
        (lower.startsWith('m') && lower.contains('pro'))) {
      return 'Xiaomi';
    }
    if (lower.contains('huawei') || lower.startsWith('aln-')) return 'Huawei';
    if (lower.contains('oppo')) return 'Oppo';
    if (lower.contains('vivo')) return 'Vivo';
    if (lower.contains('lg')) return 'LG';
    if (lower.contains('sony')) return 'Sony';
    if (lower.contains('nokia')) return 'Nokia';
    if (lower.contains('motorola') || lower.startsWith('moto')) {
      return 'Motorola';
    }
    return null;
  }

  static _UaEngineInfo? _parseEngine(String ua) {
    final lower = ua.toLowerCase();
    if (lower.contains('gecko/') &&
        lower.contains('firefox') &&
        !lower.contains('like gecko')) {
      final version = _extractVersion(ua, 'rv:([\\d\\.]+)');
      return _UaEngineInfo(name: 'Gecko', version: version);
    }
    if (lower.contains('applewebkit/')) {
      final version = _extractVersion(ua, 'AppleWebKit/([\\d\\.]+)');
      return _UaEngineInfo(name: 'WebKit', version: version);
    }
    if (lower.contains('trident/')) {
      final version = _extractVersion(ua, 'Trident/([\\d\\.]+)');
      return _UaEngineInfo(name: 'Trident', version: version);
    }
    if (lower.contains('presto/')) {
      final version = _extractVersion(ua, 'Presto/([\\d\\.]+)');
      return _UaEngineInfo(name: 'Presto', version: version);
    }
    return null;
  }

  static String? _extractVersion(String ua, String pattern) {
    final regex = RegExp(pattern, caseSensitive: false);
    final match = regex.firstMatch(ua);
    if (match == null || match.groupCount < 1) {
      return null;
    }
    return match.group(1);
  }

  static List<_UaValidationIssue> _validateCombinations(
    _UaBrowserInfo? browser,
    _UaPlatformInfo? platform,
    _UaEngineInfo? engine,
    _UaWebViewInfo? webView,
    String ua,
  ) {
    final issues = <_UaValidationIssue>[];
    if (browser == null) {
      return issues;
    }
    if (browser.isWebView) {
      const mobileOnly = [
        'Facebook iOS',
        'Facebook Android',
        'Instagram',
        'Twitter iOS',
        'Twitter Android',
        'TikTok',
        'Snapchat',
        'WhatsApp',
        'WeChat',
        'Line',
        'LinkedIn',
        'Pinterest',
        'Telegram iOS',
        'Telegram Android',
      ];
      if (mobileOnly.contains(browser.name) &&
          platform != null &&
          platform.name != 'iOS' &&
          platform.name != 'Android') {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message: '${browser.name} WebView is only available on iOS/Android',
            field: 'browser-platform',
          ),
        );
      }
      if (browser.name.contains('iOS') &&
          platform != null &&
          platform.name != 'iOS') {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message:
                '${browser.name} indicates iOS but platform is ${platform.name}',
            field: 'browser-platform',
          ),
        );
      }
      if (browser.name.contains('Android') &&
          platform != null &&
          platform.name != 'Android') {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message:
                '${browser.name} indicates Android but platform is ${platform.name}',
            field: 'browser-platform',
          ),
        );
      }
      return issues;
    }
    if (platform == null) {
      return issues;
    }
    if (browser.name == 'Safari' &&
        platform.name != 'macOS' &&
        platform.name != 'iOS') {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Safari is only available on macOS and iOS',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Chromium' && platform.name == 'iOS') {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Chromium is not available on iOS',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Edge iOS' && platform.name != 'iOS') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Edge iOS identifier found but platform is ${platform.name}',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Edge Android' && platform.name != 'Android') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message:
              'Edge Android identifier found but platform is ${platform.name}',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Firefox' &&
        platform.name != 'iOS' &&
        engine != null &&
        engine.name != 'Gecko') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Firefox should use Gecko engine',
          field: 'browser-engine',
        ),
      );
    }
    const blinkBrowsers = [
      'Chrome',
      'Edge',
      'Chromium',
      'Brave',
      'Opera',
      'Vivaldi',
    ];
    if (blinkBrowsers.contains(browser.name) &&
        platform.name != 'iOS' &&
        engine != null &&
        engine.name != 'WebKit') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: '${browser.name} should use WebKit/Blink engine',
          field: 'browser-engine',
        ),
      );
    }
    if (platform.name == 'iOS' && engine != null && engine.name != 'WebKit') {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'All iOS browsers must use WebKit engine',
          field: 'engine',
        ),
      );
    }
    return issues;
  }

  static List<_UaValidationIssue> _checkSuspiciousPatterns(String ua) {
    final issues = <_UaValidationIssue>[];
    if (ua.length < 20) {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'User agent is suspiciously short (${ua.length} characters)',
          field: 'length',
        ),
      );
    }
    if (ua.length > 600 && !_isKnownWebView(ua)) {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'User agent is unusually long (${ua.length} characters)',
          field: 'length',
        ),
      );
    }
    final openParens = ua.split('(').length - 1;
    final closeParens = ua.split(')').length - 1;
    if (openParens != closeParens) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Mismatched parentheses',
          field: 'format',
        ),
      );
    }
    final openBrackets = ua.split('[').length - 1;
    final closeBrackets = ua.split(']').length - 1;
    if (openBrackets != closeBrackets) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Mismatched square brackets',
          field: 'format',
        ),
      );
    }
    if (ua.contains('\u0000') || ua.contains('\n') || ua.contains('\r')) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Contains invalid characters (null bytes or newlines)',
          field: 'format',
        ),
      );
    }
    const fakePatterns = [
      'fake',
      'test',
      'example',
      'dummy',
      'xxx',
      'asdf',
      'qwerty',
    ];
    final lower = ua.toLowerCase();
    for (final pattern in fakePatterns) {
      if (lower.contains(pattern)) {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.warning,
            message: "Contains suspicious pattern: '$pattern'",
            field: 'content',
          ),
        );
        break;
      }
    }
    return issues;
  }

  static double _calculateConfidence(
    _UaBrowserInfo? browser,
    _UaPlatformInfo? platform,
    _UaEngineInfo? engine,
    _UaWebViewInfo? webView,
    List<_UaValidationIssue> issues,
    bool isBot,
  ) {
    var confidence = 0.5;
    if (isBot) return 0.7;
    if (browser != null) {
      confidence += 0.15;
      if (browser.majorVersion != null) {
        confidence += 0.1;
      }
      if (browser.isWebView && webView != null) {
        confidence += 0.1;
      }
    }
    if (platform != null) {
      confidence += 0.12;
      if (platform.version != null) {
        confidence += 0.05;
      }
    }
    if (engine != null) {
      confidence += 0.08;
    }
    if (webView != null) {
      if (webView.appVersion != null) confidence += 0.05;
      if (webView.buildId != null) confidence += 0.03;
      if (webView.additionalInfo.isNotEmpty) confidence += 0.02;
    }
    for (final issue in issues) {
      switch (issue.severity) {
        case _UaIssueSeverity.error:
          confidence -= 0.2;
          break;
        case _UaIssueSeverity.warning:
          confidence -= 0.08;
          break;
        case _UaIssueSeverity.info:
          confidence -= 0.02;
          break;
      }
    }
    return confidence.clamp(0.0, 1.0);
  }

  static _UaScore _calculateScore(_UaParsedUserAgent parsed) {
    var score = 50;
    final notes = <String>[];
    if (parsed.isBot) {
      notes.add('Bot: ${parsed.botName ?? "unknown"}');
      return _UaScore(60, notes.join(' | '));
    }
    if (parsed.browser != null) {
      final browser = parsed.browser!;
      score += 15;
      notes.add(
        '${browser.isWebView ? "WebView" : "Browser"}: ${browser.name} ${browser.version}',
      );
      if (browser.majorVersion != null) {
        if (browser.isWebView) {
          final range = validWebViewRanges[browser.name];
          if (range != null) {
            if (range.contains(browser.majorVersion!)) {
              score += 10;
            } else if (browser.majorVersion! < range.min) {
              score -= 10;
              notes.add('Outdated app version');
            }
          }
        } else {
          final range = validVersionRanges[browser.name];
          if (range != null) {
            if (range.contains(browser.majorVersion!)) {
              score += 10;
            } else if (browser.majorVersion! < range.min) {
              score -= 10;
              notes.add('Outdated browser version');
            }
          }
        }
      }
    } else {
      score -= 20;
      notes.add('Unknown browser');
    }
    if (parsed.platform != null) {
      score += 10;
      notes.add(
        'Platform: ${parsed.platform!.name}${parsed.platform!.version != null ? " ${parsed.platform!.version}" : ""}',
      );
    } else {
      score -= 15;
      notes.add('Unknown platform');
    }
    if (parsed.device != null) {
      score += 5;
    }
    if (parsed.engine != null) {
      score += 5;
    }
    if (parsed.webView != null) {
      score += 5;
      if (parsed.webView!.buildId != null) {
        score += 3;
      }
    }
    for (final issue in parsed.issues) {
      switch (issue.severity) {
        case _UaIssueSeverity.error:
          score -= 15;
          break;
        case _UaIssueSeverity.warning:
          score -= 5;
          break;
        case _UaIssueSeverity.info:
          score -= 1;
          break;
      }
    }
    score += (parsed.confidence * 10).round();
    score = score.clamp(0, 100).toInt();
    final summary = notes.isEmpty ? 'Valid user agent' : notes.join(' | ');
    return _UaScore(score, summary);
  }
}

class _UaScore {
  const _UaScore(this.score, this.summary);
  final int score;
  final String summary;
}

class _UaBotPattern {
  const _UaBotPattern(this.pattern, this.name);
  final String pattern;
  final String name;
}

class _UaBrowserPattern {
  const _UaBrowserPattern(
    this.pattern,
    this.name,
    this.versionPattern,
    this.isWebView,
  );
  final String pattern;
  final String name;
  final String versionPattern;
  final bool isWebView;
}

class _UaBotResult {
  const _UaBotResult(this.isBot, this.name);
  final bool isBot;
  final String? name;
}

class _UaWebViewPattern {
  const _UaWebViewPattern(this.app, this.patterns);
  final String app;
  final List<_UaKeyPattern> patterns;
}

class _UaKeyPattern {
  const _UaKeyPattern(this.key, this.regex);
  final String key;
  final String regex;
}

class _OfflineLlmView extends StatefulWidget {
  const _OfflineLlmView();

  @override
  State<_OfflineLlmView> createState() => _OfflineLlmViewState();
}

class _ChatMessage {
  final String role; // 'user' or 'assistant'
  String content;
  _ChatMessage({required this.role, required this.content});
}

class _ChatInputField extends StatefulWidget {
  const _ChatInputField({
    required this.controller,
    required this.onSubmit,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool enabled;

  @override
  State<_ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<_ChatInputField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onSubmit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        maxLines: 4,
        minLines: 1,
        enabled: widget.enabled,
        decoration: InputDecoration(
          hintText: widget.enabled
              ? 'Type a message... (Enter to send)'
              : 'Start a model first...',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
        ),
        style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
      ),
    );
  }
}

class _OfflineLlmViewState extends State<_OfflineLlmView> {
  final LocalLLMService _service = LocalLLMService();
  final TextEditingController _prompt = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ModelInfo> _models = [];
  final List<_ChatMessage> _messages = [];
  bool _loadingModels = false;
  bool _startingServer = false;
  bool _stoppingServer = false;
  bool _generating = false;
  String? _error;

  ModelPreset? _downloadingPreset;
  double _downloadProgress = 0;
  StreamSubscription<String>? _generationSub;

  int _maxTokens = 256;
  double _temperature = 0.7;

  @override
  void initState() {
    super.initState();
    _refreshModels();
  }

  @override
  void dispose() {
    _generationSub?.cancel();
    unawaited(_service.stopServer());
    _prompt.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshModels() async {
    setState(() {
      _loadingModels = true;
      _error = null;
    });
    try {
      final models = await _service.getAvailableModels();
      models.sort((a, b) => a.name.compareTo(b.name));
      setState(() => _models = models);
    } catch (e) {
      setState(() => _error = 'Failed to load models: $e');
    } finally {
      setState(() => _loadingModels = false);
    }
  }

  Future<void> _startServer(ModelInfo model) async {
    if (_startingServer) return;
    final serverBinary = File(_service.serverBinaryPath);
    final serverDir = Directory(_service.serverBundleDir);
    if (!serverBinary.existsSync() || !serverDir.existsSync()) {
      setState(
        () => _error =
            'Missing server bundle. Expected ${_service.serverBundleDir}',
      );
      return;
    }
    final requiredLibs = ['libllama.dylib', 'libggml.dylib'];
    final missingLibs = requiredLibs
        .where(
          (lib) => !File(p.join(_service.serverBundleDir, lib)).existsSync(),
        )
        .toList();
    if (missingLibs.isNotEmpty) {
      setState(
        () => _error =
            'Server bundle is incomplete (missing ${missingLibs.join(", ")}).',
      );
      return;
    }
    setState(() {
      _startingServer = true;
      _error = null;
    });
    try {
      await _service.startServer(model.path);
      setState(() {});
    } catch (e) {
      setState(() => _error = 'Failed to start server: $e');
    } finally {
      setState(() => _startingServer = false);
    }
  }

  Future<void> _stopServer() async {
    if (_stoppingServer) return;
    setState(() => _stoppingServer = true);
    await _service.stopServer();
    setState(() => _stoppingServer = false);
  }

  Future<void> _downloadPreset(ModelPreset preset) async {
    if (_downloadingPreset != null) return;
    if (_isPresetInstalled(preset)) return;
    setState(() {
      _downloadingPreset = preset;
      _downloadProgress = 0;
      _error = null;
    });
    try {
      await _service.downloadModel(preset, (progress) {
        setState(() => _downloadProgress = progress);
      });
      await _refreshModels();
    } catch (e) {
      setState(() => _error = 'Download failed: $e');
    } finally {
      setState(() {
        _downloadingPreset = null;
        _downloadProgress = 0;
      });
    }
  }

  Future<void> _deleteModel(ModelInfo model) async {
    await _service.deleteModel(model.path);
    await _refreshModels();
  }

  Future<void> _run() async {
    if (_generating) return;
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) return;
    if (!_service.isReady) {
      setState(() => _error = 'Start the server before generating.');
      return;
    }

    // Add user message to history and clear input
    final userMessage = _ChatMessage(role: 'user', content: prompt);
    final assistantMessage = _ChatMessage(role: 'assistant', content: '');

    setState(() {
      _messages.add(userMessage);
      _messages.add(assistantMessage);
      _prompt.clear();
      _generating = true;
      _error = null;
    });

    // Build conversation history for context
    final chatHistory = _messages
        .where((m) => m.content.isNotEmpty || m == assistantMessage)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();
    // Remove the empty assistant message from history sent to API
    if (chatHistory.isNotEmpty && chatHistory.last['content']!.isEmpty) {
      chatHistory.removeLast();
    }

    _scrollToBottom();
    _generationSub?.cancel();
    _generationSub = _service
        .generateChat(
          chatHistory,
          maxTokens: _maxTokens,
          temperature: _temperature,
        )
        .listen(
          (chunk) {
            assistantMessage.content += chunk;
            setState(() {});
            _scrollToBottom();
          },
          onError: (err) {
            setState(() {
              _error = 'Generation failed: $err';
              _generating = false;
            });
          },
          onDone: () {
            setState(() => _generating = false);
          },
        );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearHistory() {
    _generationSub?.cancel();
    setState(() {
      _messages.clear();
      _generating = false;
    });
  }

  Future<void> _stopGeneration() async {
    await _generationSub?.cancel();
    _generationSub = null;
    setState(() => _generating = false);
  }

  bool _isPresetInstalled(ModelPreset preset) {
    return _models.any((model) => p.basename(model.path) == preset.filename);
  }

  bool _isModelActive(ModelInfo model) {
    return _service.isReady && _service.currentModel == model.path;
  }

  String _presetSize(ModelPreset preset) {
    final size = preset.sizeBytes;
    if (size > 1e9) return '${(size / 1e9).toStringAsFixed(1)} GB';
    return '${(size / 1e6).toStringAsFixed(0)} MB';
  }

  Widget _buildCard({
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD5D5D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: Row(
            children: [
              Expanded(
                child: _buildCard(
                  title: 'Installed Models',
                  trailing: _loadingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ToolIconButton(
                          icon: Icons.refresh,
                          tooltip: 'Refresh',
                          onPressed: _refreshModels,
                        ),
                  child: _models.isEmpty
                      ? const Center(child: Text('No models downloaded yet.'))
                      : ListView.separated(
                          itemCount: _models.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 12),
                          itemBuilder: (context, index) {
                            final model = _models[index];
                            final isActive = _isModelActive(model);
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        model.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        model.sizeFormatted,
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
                                      if (isActive)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Running',
                                            style: TextStyle(
                                              color: Color(0xFF2FA866),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ToolButton(
                                  label: isActive ? 'Stop' : 'Start',
                                  onPressed: isActive || _startingServer
                                      ? (isActive ? _stopServer : null)
                                      : () => _startServer(model),
                                ),
                                const SizedBox(width: 6),
                                ToolIconButton(
                                  icon: Icons.delete,
                                  tooltip: 'Delete',
                                  onPressed: isActive
                                      ? null
                                      : () => _deleteModel(model),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCard(
                  title: 'Download Presets',
                  child: ListView.separated(
                    itemCount: kModelPresets.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final preset = kModelPresets[index];
                      final installed = _isPresetInstalled(preset);
                      final downloading = _downloadingPreset == preset;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      preset.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_presetSize(preset)} · ${preset.description}',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ToolButton(
                                label: installed ? 'Installed' : 'Download',
                                onPressed: installed || downloading
                                    ? null
                                    : () => _downloadPreset(preset),
                              ),
                            ],
                          ),
                          if (downloading)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: LinearProgressIndicator(
                                value: _downloadProgress,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Chat history section
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD5D5D5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Conversation',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Tokens', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          SmallDropdown(
                            items: const ['128', '256', '512', '1024', '2048'],
                            initialValue: '$_maxTokens',
                            onChanged: (value) =>
                                setState(() => _maxTokens = int.parse(value)),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Temp', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          SmallDropdown(
                            items: const [
                              '0.2',
                              '0.4',
                              '0.6',
                              '0.7',
                              '0.8',
                              '1.0',
                            ],
                            initialValue: _temperature.toStringAsFixed(1),
                            onChanged: (value) => setState(
                              () => _temperature = double.parse(value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      ToolIconButton(
                        icon: Icons.delete_outline,
                        tooltip: 'Clear history',
                        onPressed: _messages.isEmpty ? null : _clearHistory,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Messages list
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Text(
                            _service.isReady
                                ? 'Start a conversation...'
                                : 'Start a model to begin chatting',
                            style: const TextStyle(color: Colors.black38),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isUser = msg.role == 'user';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: isUser
                                          ? const Color(0xFF2FA866)
                                          : const Color(0xFF6B7280),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      isUser ? Icons.person : Icons.smart_toy,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isUser ? 'You' : 'Assistant',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          msg.content.isEmpty &&
                                                  !isUser &&
                                                  _generating
                                              ? '...'
                                              : msg.content,
                                          style: const TextStyle(
                                            fontFamily: 'Menlo',
                                            fontSize: 12,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Input section
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD5D5D5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _ChatInputField(
                  controller: _prompt,
                  onSubmit: _run,
                  enabled: _service.isReady,
                ),
              ),
              if (_generating)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: IconButton(
                    icon: const Icon(Icons.stop, color: Colors.red),
                    tooltip: 'Stop',
                    onPressed: _stopGeneration,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF2FA866)),
                    tooltip: 'Send',
                    onPressed: _service.isReady ? _run : null,
                  ),
                ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Color(0xFFB00020))),
        ],
      ],
    );
  }
}

class _AntiBotDetectorView extends StatefulWidget {
  const _AntiBotDetectorView();

  @override
  State<_AntiBotDetectorView> createState() => _AntiBotDetectorViewState();
}

class _AntiBotDetectorViewState extends State<_AntiBotDetectorView> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _url.dispose();
    _output.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final rawUrl = _url.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _output.clear();
        _error = null;
      });
      return;
    }
    final normalized = _normalizeUrl(rawUrl);
    if (normalized == null) {
      setState(() => _error = 'Invalid URL');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _output.text = 'Fetching...';
    });
    try {
      final fetched = await _fetchPage(normalized);
      final analysis = _AntiBotDetector.analyze(
        url: fetched.url,
        html: fetched.html,
        headers: fetched.headers,
        cookies: fetched.cookies,
        scripts: fetched.scripts,
        jsVariables: fetched.inlineScripts,
      );
      _output.text = _formatAntiBotResult(analysis, fetched.statusCode);
    } catch (e) {
      _output.clear();
      _error = 'Failed to fetch page: $e';
    } finally {
      setState(() => _loading = false);
    }
  }

  Uri? _normalizeUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    return Uri.tryParse(withScheme);
  }

  Future<_FetchedPage> _fetchPage(Uri uri) async {
    final client = HttpClient();
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml',
    );
    request.headers.set(
      HttpHeaders.userAgentHeader,
      _AntiBotDetector.defaultUserAgent,
    );
    final response = await request.close();
    final statusCode = response.statusCode;
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    final cookies = <String, String>{};
    // Parse cookies from header manually to avoid FormatException with invalid characters
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null) {
      for (final header in setCookieHeaders) {
        try {
          final parts = header.split(';').first.split('=');
          if (parts.length >= 2) {
            cookies[parts[0].trim()] = parts.sublist(1).join('=').trim();
          }
        } catch (_) {
          // Skip malformed cookies
        }
      }
    }
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return _FetchedPage(
      url: uri.toString(),
      statusCode: statusCode,
      headers: headers,
      cookies: cookies,
      html: body,
      scripts: _extractScriptSrc(body),
      inlineScripts: _extractInlineScripts(body),
    );
  }

  List<String> _extractScriptSrc(String html) {
    final matches = RegExp(
      "<script[^>]+src=['\\\"]([^'\\\"]+)['\\\"]",
      caseSensitive: false,
    ).allMatches(html);
    return matches
        .map((match) => match.group(1) ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
  }

  List<String> _extractInlineScripts(String html) {
    final matches = RegExp(
      "<script(?![^>]*\\bsrc=)[^>]*>([\\s\\S]*?)</script>",
      caseSensitive: false,
    ).allMatches(html);
    return matches
        .map((match) => (match.group(1) ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _url.text = text.trim());
  }

  void _setSample() {
    setState(() => _url.text = 'https://example.com');
  }

  void _clear() {
    setState(() {
      _url.clear();
      _output.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // URL input row
        Row(
          children: [
            const Text('URL', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFD5D5D5)),
                ),
                child: TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    hintText: 'https://example.com',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
                  onSubmitted: (_) => _analyze(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ToolButton(label: 'Go', onPressed: _analyze),
            ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
            ToolButton(label: 'Sample', onPressed: _setSample),
            ToolButton(label: 'Clear', onPressed: _clear),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Report output
        Expanded(
          child: EditorPane(
            label: 'Report',
            actions: [
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            placeholder: 'Detection results appear here...',
            readOnly: true,
            controller: _output,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
      ],
    );
  }
}

class _FetchedPage {
  const _FetchedPage({
    required this.url,
    required this.statusCode,
    required this.headers,
    required this.cookies,
    required this.html,
    required this.scripts,
    required this.inlineScripts,
  });

  final String url;
  final int statusCode;
  final Map<String, String> headers;
  final Map<String, String> cookies;
  final String html;
  final List<String> scripts;
  final List<String> inlineScripts;
}

String _formatAntiBotResult(_AntiBotAnalysisResult result, int statusCode) {
  final buffer = StringBuffer();
  buffer.writeln('URL: ${result.url}');
  buffer.writeln('Status: $statusCode');
  buffer.writeln('Risk Level: ${result.riskLevel.label}');
  buffer.writeln();
  buffer.writeln(result.summary);
  buffer.writeln();
  if (result.detections.isEmpty) {
    buffer.writeln('No protection detected.');
    return buffer.toString().trimRight();
  }
  buffer.writeln('Detections:');
  for (final detection in result.detections) {
    final value = detection.matchedValue ?? detection.matchedPattern;
    buffer.writeln(
      '  - ${detection.technology} (${detection.category.label}, ${detection.patternType.label}, ${detection.confidence}%)',
    );
    buffer.writeln('    Match: $value');
  }
  return buffer.toString().trimRight();
}

enum _AntiBotCategory { antiBot, captcha, fingerprinting, waf }

extension _AntiBotCategoryLabel on _AntiBotCategory {
  String get label {
    switch (this) {
      case _AntiBotCategory.antiBot:
        return 'Anti-Bot';
      case _AntiBotCategory.captcha:
        return 'CAPTCHA';
      case _AntiBotCategory.fingerprinting:
        return 'Fingerprinting';
      case _AntiBotCategory.waf:
        return 'WAF/CDN';
    }
  }
}

enum _AntiBotPatternType { cookie, header, script, html, js, url, meta }

extension _AntiBotPatternTypeLabel on _AntiBotPatternType {
  String get label {
    switch (this) {
      case _AntiBotPatternType.cookie:
        return 'cookie';
      case _AntiBotPatternType.header:
        return 'header';
      case _AntiBotPatternType.script:
        return 'script';
      case _AntiBotPatternType.html:
        return 'html';
      case _AntiBotPatternType.js:
        return 'js';
      case _AntiBotPatternType.url:
        return 'url';
      case _AntiBotPatternType.meta:
        return 'meta';
    }
  }
}

class _AntiBotTechnology {
  const _AntiBotTechnology({
    required this.name,
    required this.category,
    required this.website,
    required this.description,
    required this.patterns,
  });

  final String name;
  final _AntiBotCategory category;
  final String website;
  final String description;
  final List<_AntiBotPattern> patterns;
}

class _AntiBotPattern {
  const _AntiBotPattern({
    required this.type,
    required this.key,
    required this.regex,
    required this.confidence,
  });

  final _AntiBotPatternType type;
  final String? key;
  final String regex;
  final int confidence;
}

class _AntiBotDetection {
  const _AntiBotDetection({
    required this.technology,
    required this.category,
    required this.patternType,
    required this.matchedPattern,
    required this.matchedValue,
    required this.confidence,
  });

  final String technology;
  final _AntiBotCategory category;
  final _AntiBotPatternType patternType;
  final String matchedPattern;
  final String? matchedValue;
  final int confidence;
}

class _AntiBotAnalysisResult {
  const _AntiBotAnalysisResult({
    required this.url,
    required this.detections,
    required this.antiBot,
    required this.captcha,
    required this.fingerprinting,
    required this.waf,
    required this.summary,
    required this.riskLevel,
  });

  final String url;
  final List<_AntiBotDetection> detections;
  final List<_AntiBotDetection> antiBot;
  final List<_AntiBotDetection> captcha;
  final List<_AntiBotDetection> fingerprinting;
  final List<_AntiBotDetection> waf;
  final String summary;
  final _AntiBotRiskLevel riskLevel;
}

enum _AntiBotRiskLevel { none, low, medium, high, extreme }

extension _AntiBotRiskLevelLabel on _AntiBotRiskLevel {
  String get label {
    switch (this) {
      case _AntiBotRiskLevel.none:
        return 'None';
      case _AntiBotRiskLevel.low:
        return 'Low';
      case _AntiBotRiskLevel.medium:
        return 'Medium';
      case _AntiBotRiskLevel.high:
        return 'High';
      case _AntiBotRiskLevel.extreme:
        return 'Extreme';
    }
  }
}

class _AntiBotDetector {
  static const String defaultUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.85 Safari/537.36';

  static const List<_AntiBotTechnology> technologies = [
    _AntiBotTechnology(
      name: 'Cloudflare Bot Management',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.cloudflare.com/products/bot-management/',
      description: 'Enterprise bot management solution from Cloudflare',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'cf_clearance',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '__cf_bm',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'cf_ob_info',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_cf_chl',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'cf-ray',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'cf-cache-status',
          regex: '.*',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'server',
          regex: 'cloudflare',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'challenges\\.cloudflare\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: '/cdn-cgi/challenge-platform/',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'Checking your browser',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'cf-browser-verification',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'window._cf_chl_opt',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Akamai Bot Manager',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.akamai.com/products/bot-manager',
      description: 'Advanced bot detection and mitigation from Akamai',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_abck',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'ak_bmsc',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'bm_sz',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'bm_sv',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'bm_mi',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'ak\\.js',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'akamai.*sensor',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'window._cf',
          regex: '.*',
          confidence: 50,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'bmak',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'DataDome',
      category: _AntiBotCategory.antiBot,
      website: 'https://datadome.co/',
      description: 'Real-time bot protection for web, mobile apps and APIs',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'datadome',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'datadome-_zldp',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'datadome-_zldt',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'js\\.datadome\\.co',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'tags\\.datadome\\.co',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-datadome',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-dd-b',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-dd-type',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'window.ddjskey',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'DataDome',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'PerimeterX',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.perimeterx.com/',
      description: 'Bot detection using behavioral analysis',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_px',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_px2',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_px3',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_pxvid',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_pxhd',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_pxde',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'client\\.perimeterx\\.net',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'captcha\\.px-cdn\\.net',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'window._pxAppId',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'PX',
          regex: '.*',
          confidence: 80,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Imperva/Incapsula',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.imperva.com/',
      description: 'Application security and bot management',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'incap_ses_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'visid_incap_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'nlbi_',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'reese84',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-iinfo',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-cdn',
          regex: 'imperva|incapsula',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: '_Incapsula_Resource',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: '/_Incapsula_Resource\\?',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Kasada',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.kasada.io/',
      description: 'Polyform bot defense platform',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'x-kpsdk-ct',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'x-kpsdk-cd',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'x-kpsdk-v',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: '/ips\\.js',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'ct\\.kasada',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-kpsdk-ct',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'KPSDK',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Shape Security',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.f5.com/products/security/shape-security',
      description: 'F5 Shape bot defense (formerly Shape Security)',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_imp_apg_r_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_imp_apg_v_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'shape\\.com',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: '/async/api\\.js',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'shape',
          regex: '.*',
          confidence: 60,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'AWS WAF',
      category: _AntiBotCategory.antiBot,
      website: 'https://aws.amazon.com/waf/',
      description: 'Amazon Web Services Web Application Firewall',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'aws-waf-token',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'awswaf',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-amzn-waf-action',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-amzn-requestid',
          regex: '.*',
          confidence: 50,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'captcha\\.awswaf\\.com',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Distil Networks',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.imperva.com/products/advanced-bot-protection/',
      description: 'Advanced bot protection (now part of Imperva)',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_SID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_IID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_UID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_HID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_ZID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'distil',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'distilIdentificationBlock',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Forter',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.forter.com/',
      description: 'E-commerce fraud prevention',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'forterToken',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'forter\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'ftr__',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Sift',
      category: _AntiBotCategory.antiBot,
      website: 'https://sift.com/',
      description: 'Digital trust and safety platform',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'cdn\\.sift\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'cdn\\.siftscience\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: '_sift',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Netacea',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.netacea.com/',
      description: 'Bot management and attack prevention',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_netacea_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'netacea',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Reblaze',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.reblaze.com/',
      description: 'Cloud-native web security platform',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'rbzid',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'rbzsessionid',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-reblaze-protection',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'reCAPTCHA v2',
      category: _AntiBotCategory.captcha,
      website: 'https://www.google.com/recaptcha/',
      description: 'Google CAPTCHA (checkbox)',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'google\\.com/recaptcha/api\\.js(?!.*render=)',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'www\\.gstatic\\.com/recaptcha',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'g-recaptcha',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'data-sitekey',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'grecaptcha',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'reCAPTCHA v3',
      category: _AntiBotCategory.captcha,
      website: 'https://www.google.com/recaptcha/',
      description: 'Google CAPTCHA (invisible)',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'google\\.com/recaptcha/api\\.js\\?.*render=',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'recaptcha/enterprise\\.js',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'recaptcha-badge',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'grecaptcha.execute',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'hCaptcha',
      category: _AntiBotCategory.captcha,
      website: 'https://www.hcaptcha.com/',
      description: 'Privacy-focused CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'hcaptcha\\.com/1/api\\.js',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'js\\.hcaptcha\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'h-captcha',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'data-hcaptcha',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'hcaptcha',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Cloudflare Turnstile',
      category: _AntiBotCategory.captcha,
      website: 'https://www.cloudflare.com/products/turnstile/',
      description: 'Cloudflare CAPTCHA alternative',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'challenges\\.cloudflare\\.com/turnstile',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'cf-turnstile',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'turnstile',
          regex: '.*',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'FunCaptcha/Arkose Labs',
      category: _AntiBotCategory.captcha,
      website: 'https://www.arkoselabs.com/',
      description: 'Interactive puzzle CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'arkoselabs\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'funcaptcha\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'funcaptcha',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'ArkoseEnforcement',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'GeeTest',
      category: _AntiBotCategory.captcha,
      website: 'https://www.geetest.com/',
      description: 'Behavioral CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'geetest\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'gt\\.js',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'geetest_',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'initGeetest',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'KeyCAPTCHA',
      category: _AntiBotCategory.captcha,
      website: 'https://www.keycaptcha.com/',
      description: 'Puzzle-based CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'keycaptcha\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'keycaptcha',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'FingerprintJS',
      category: _AntiBotCategory.fingerprinting,
      website: 'https://fingerprint.com/',
      description: 'Browser fingerprinting library',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'fpjs\\.io',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'fingerprint\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'fingerprintjs',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'FingerprintJS',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'Fingerprint2',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Canvas Fingerprinting',
      category: _AntiBotCategory.fingerprinting,
      website: '',
      description: 'Browser identification via Canvas API',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'toDataURL',
          regex: '.*',
          confidence: 50,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'canvas.*fingerprint',
          confidence: 70,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'WebGL Fingerprinting',
      category: _AntiBotCategory.fingerprinting,
      website: '',
      description: 'Browser identification via WebGL',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'WEBGL_debug_renderer_info',
          regex: '.*',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'getExtension',
          regex: '.*',
          confidence: 30,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'AudioContext Fingerprinting',
      category: _AntiBotCategory.fingerprinting,
      website: '',
      description: 'Browser identification via Audio API',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'OfflineAudioContext',
          regex: '.*',
          confidence: 60,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'createOscillator',
          regex: '.*',
          confidence: 50,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Cloudflare',
      category: _AntiBotCategory.waf,
      website: 'https://www.cloudflare.com/',
      description: 'CDN and DDoS protection',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'server',
          regex: 'cloudflare',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'cf-ray',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '__cflb',
          regex: '.*',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Akamai',
      category: _AntiBotCategory.waf,
      website: 'https://www.akamai.com/',
      description: 'CDN and web application security',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-akamai-transformed',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'akamai-origin-hop',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'server',
          regex: 'akamai',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Fastly',
      category: _AntiBotCategory.waf,
      website: 'https://www.fastly.com/',
      description: 'Edge cloud platform and CDN',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-served-by',
          regex: 'cache-',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-fastly-request-id',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'via',
          regex: 'varnish',
          confidence: 70,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Sucuri',
      category: _AntiBotCategory.waf,
      website: 'https://sucuri.net/',
      description: 'Website security and WAF',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-sucuri-id',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'server',
          regex: 'sucuri',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-sucuri-cache',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
  ];

  static _AntiBotAnalysisResult analyze({
    required String url,
    String? html,
    Map<String, String> headers = const {},
    Map<String, String> cookies = const {},
    List<String> scripts = const [],
    List<String> jsVariables = const [],
  }) {
    final detections = <_AntiBotDetection>[];
    final headersLower = {
      for (final entry in headers.entries)
        entry.key.toLowerCase(): entry.value.toLowerCase(),
    };
    final cookiesLower = {
      for (final entry in cookies.entries) entry.key.toLowerCase(): entry.value,
    };
    final htmlLower = (html ?? '').toLowerCase();
    final scriptsJoined = scripts.join(' ').toLowerCase();
    final jsJoined = jsVariables.join(' ').toLowerCase();

    for (final tech in technologies) {
      for (final pattern in tech.patterns) {
        var matched = false;
        String? matchedValue;
        final regex = RegExp(pattern.regex, caseSensitive: false);
        switch (pattern.type) {
          case _AntiBotPatternType.cookie:
            if (pattern.key != null) {
              final key = pattern.key!.toLowerCase();
              for (final entry in cookiesLower.entries) {
                if (entry.key == key || entry.key.startsWith(key)) {
                  if (pattern.regex == '.*' || regex.hasMatch(entry.value)) {
                    matched = true;
                    matchedValue = '${entry.key}=${entry.value}';
                    break;
                  }
                }
              }
            }
            break;
          case _AntiBotPatternType.header:
            if (pattern.key != null) {
              final key = pattern.key!.toLowerCase();
              final value = headersLower[key];
              if (value != null &&
                  (pattern.regex == '.*' || regex.hasMatch(value))) {
                matched = true;
                matchedValue = '$key: $value';
              }
            }
            break;
          case _AntiBotPatternType.script:
            if (regex.hasMatch(scriptsJoined)) {
              matched = true;
              matchedValue = pattern.regex;
            }
            break;
          case _AntiBotPatternType.html:
          case _AntiBotPatternType.meta:
            if (regex.hasMatch(htmlLower)) {
              matched = true;
              matchedValue = pattern.regex;
            }
            break;
          case _AntiBotPatternType.js:
            if (pattern.key != null &&
                jsJoined.contains(pattern.key!.toLowerCase())) {
              matched = true;
              matchedValue = pattern.key!.toLowerCase();
            }
            break;
          case _AntiBotPatternType.url:
            if (regex.hasMatch(url.toLowerCase())) {
              matched = true;
              matchedValue = url;
            }
            break;
        }
        if (matched) {
          detections.add(
            _AntiBotDetection(
              technology: tech.name,
              category: tech.category,
              patternType: pattern.type,
              matchedPattern: pattern.regex,
              matchedValue: matchedValue,
              confidence: pattern.confidence,
            ),
          );
        }
      }
    }

    final bestDetections = <String, _AntiBotDetection>{};
    for (final detection in detections) {
      final existing = bestDetections[detection.technology];
      if (existing == null || detection.confidence > existing.confidence) {
        bestDetections[detection.technology] = detection;
      }
    }

    final uniqueDetections = bestDetections.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final antiBot = uniqueDetections
        .where((d) => d.category == _AntiBotCategory.antiBot)
        .toList();
    final captcha = uniqueDetections
        .where((d) => d.category == _AntiBotCategory.captcha)
        .toList();
    final fingerprinting = uniqueDetections
        .where((d) => d.category == _AntiBotCategory.fingerprinting)
        .toList();
    final waf = uniqueDetections
        .where((d) => d.category == _AntiBotCategory.waf)
        .toList();

    final riskLevel = _calculateRiskLevel(antiBot, captcha);
    final summary = _generateSummary(
      antiBot: antiBot,
      captcha: captcha,
      fingerprinting: fingerprinting,
      waf: waf,
      riskLevel: riskLevel,
    );

    return _AntiBotAnalysisResult(
      url: url,
      detections: uniqueDetections,
      antiBot: antiBot,
      captcha: captcha,
      fingerprinting: fingerprinting,
      waf: waf,
      summary: summary,
      riskLevel: riskLevel,
    );
  }

  static _AntiBotRiskLevel _calculateRiskLevel(
    List<_AntiBotDetection> antiBot,
    List<_AntiBotDetection> captcha,
  ) {
    const hardAntiBot = [
      'Akamai Bot Manager',
      'DataDome',
      'PerimeterX',
      'Kasada',
      'Shape Security',
    ];
    const mediumAntiBot = [
      'Cloudflare Bot Management',
      'Imperva/Incapsula',
      'AWS WAF',
    ];
    var score = 0;
    for (final detection in antiBot) {
      if (hardAntiBot.contains(detection.technology)) {
        score += 30;
      } else if (mediumAntiBot.contains(detection.technology)) {
        score += 20;
      } else {
        score += 10;
      }
    }
    for (final detection in captcha) {
      if (detection.technology.contains('reCAPTCHA v3') ||
          detection.technology.contains('Arkose')) {
        score += 15;
      } else {
        score += 10;
      }
    }
    if (score == 0) return _AntiBotRiskLevel.none;
    if (score <= 15) return _AntiBotRiskLevel.low;
    if (score <= 30) return _AntiBotRiskLevel.medium;
    if (score <= 50) return _AntiBotRiskLevel.high;
    return _AntiBotRiskLevel.extreme;
  }

  static String _generateSummary({
    required List<_AntiBotDetection> antiBot,
    required List<_AntiBotDetection> captcha,
    required List<_AntiBotDetection> fingerprinting,
    required List<_AntiBotDetection> waf,
    required _AntiBotRiskLevel riskLevel,
  }) {
    final lines = <String>[];
    if (antiBot.isEmpty && captcha.isEmpty && waf.isEmpty) {
      return 'No anti-bot protection detected.';
    }
    if (antiBot.isNotEmpty) {
      lines.add('Anti-Bot: ${antiBot.map((d) => d.technology).join(', ')}');
    }
    if (captcha.isNotEmpty) {
      lines.add('CAPTCHA: ${captcha.map((d) => d.technology).join(', ')}');
    }
    if (waf.isNotEmpty) {
      lines.add('WAF/CDN: ${waf.map((d) => d.technology).join(', ')}');
    }
    if (fingerprinting.isNotEmpty) {
      lines.add(
        'Fingerprinting: ${fingerprinting.map((d) => d.technology).join(', ')}',
      );
    }
    lines.add('');
    lines.add('Scraping Difficulty: ${riskLevel.label}');
    return lines.join('\n');
  }
}

class _JwtDebuggerView extends StatefulWidget {
  const _JwtDebuggerView();

  @override
  State<_JwtDebuggerView> createState() => _JwtDebuggerViewState();
}

class _JwtDebuggerViewState extends State<_JwtDebuggerView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _header = TextEditingController();
  final TextEditingController _payload = TextEditingController();
  final TextEditingController _secret = TextEditingController();
  String _alg = 'HS256';
  String _status = 'Signature Not Verified';
  Color _statusColor = const Color(0xFFB0B0B0);
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _header.dispose();
    _payload.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _parse() {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _header.clear();
        _payload.clear();
        _status = 'Signature Not Verified';
        _statusColor = const Color(0xFFB0B0B0);
        _error = null;
      });
      return;
    }
    final parts = raw.split('.');
    if (parts.length < 2) {
      setState(() => _error = 'Invalid JWT format.');
      return;
    }
    try {
      final headerJson = utf8.decode(_base64UrlDecode(parts[0]));
      final payloadJson = utf8.decode(_base64UrlDecode(parts[1]));
      _header.text = _prettyJson(headerJson);
      _payload.text = _prettyJson(payloadJson);
      final headerMap = jsonDecode(headerJson);
      if (headerMap is Map && headerMap['alg'] is String) {
        _alg = headerMap['alg'] as String;
      }
      _verifySignature(parts);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _verifySignature(List<String> parts) {
    if (parts.length < 3 || _secret.text.isEmpty) {
      setState(() {
        _status = 'Signature Not Verified';
        _statusColor = const Color(0xFFB0B0B0);
      });
      return;
    }
    final signingInput = '${parts[0]}.${parts[1]}';
    final secret = utf8.encode(_secret.text);
    crypto.Digest digest;
    switch (_alg) {
      case 'HS384':
        digest = crypto.Hmac(
          crypto.sha384,
          secret,
        ).convert(utf8.encode(signingInput));
        break;
      case 'HS512':
        digest = crypto.Hmac(
          crypto.sha512,
          secret,
        ).convert(utf8.encode(signingInput));
        break;
      case 'HS256':
      default:
        digest = crypto.Hmac(
          crypto.sha256,
          secret,
        ).convert(utf8.encode(signingInput));
        break;
    }
    final computed = _base64UrlNoPad(digest.bytes);
    final valid = computed == parts[2];
    setState(() {
      _status = valid ? 'Signature Verified' : 'Signature Mismatch';
      _statusColor = valid ? const Color(0xFF5DBB63) : const Color(0xFFD96B6B);
    });
  }

  String _prettyJson(String input) {
    try {
      final decoded = jsonDecode(input);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return input;
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _parse();
  }

  void _setSample() {
    const header = '{"typ":"JWT","alg":"HS256"}';
    const payload = '{"sub":"1234567890","name":"John Doe","iat":1516239022}';
    final encodedHeader = _base64UrlNoPad(utf8.encode(header));
    final encodedPayload = _base64UrlNoPad(utf8.encode(payload));
    setState(() => _input.text = '$encodedHeader.$encodedPayload.');
    _parse();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _header.clear();
      _payload.clear();
      _error = null;
    });
  }

  Future<void> _copyInput() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
  }

  Future<void> _copyHeader() async {
    await Clipboard.setData(ClipboardData(text: _header.text));
  }

  Future<void> _copyPayload() async {
    await Clipboard.setData(ClipboardData(text: _payload.text));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 980;
        final inputPane = EditorPane(
          label: 'Input',
          actions: [
            ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
            ToolButton(label: 'Sample', onPressed: _setSample),
            ToolButton(label: 'Clear', onPressed: _clearInput),
            const ToolIconButton(icon: Icons.settings),
            SmallDropdown(
              items: const ['HS256', 'HS384', 'HS512'],
              initialValue: _alg,
              onChanged: (value) {
                setState(() => _alg = value);
                _parse();
              },
            ),
          ],
          controller: _input,
          onChanged: (_) => _parse(),
          placeholder: 'Paste JWT here...',
          copyAction: _copyInput,
        );
        final detailPane = ListView(
          padding: EdgeInsets.zero,
          children: [
            EditorPane(
              label: 'Header',
              actions: const [],
              controller: _header,
              readOnly: true,
              placeholder: '{ "typ": "JWT", "alg": "HS256" }',
              expand: false,
              fixedHeight: 110,
              copyAction: _copyHeader,
            ),
            const SizedBox(height: 12),
            EditorPane(
              label: 'Payload',
              actions: const [],
              controller: _payload,
              readOnly: true,
              placeholder: '{ "sub": "1234567890" }',
              expand: false,
              fixedHeight: 110,
              copyAction: _copyPayload,
            ),
            const SizedBox(height: 12),
            const Text(
              'Signature',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('HMACSHA256(', style: TextStyle(fontSize: 11)),
                  Text(
                    '  base64UrlEncode(header) + "." +',
                    style: TextStyle(fontSize: 11),
                  ),
                  Text(
                    '  base64UrlEncode(payload) + "." +',
                    style: TextStyle(fontSize: 11),
                  ),
                  Text('  your-secret', style: TextStyle(fontSize: 11)),
                  Text(')', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _InlineTextField(
              hintText: 'your-secret',
              controller: _secret,
              onChanged: (_) => _parse(),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  _status,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        );
        if (horizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: inputPane),
              const SizedBox(width: 16),
              SizedBox(width: 320, child: detailPane),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: inputPane),
            const SizedBox(height: 16),
            Expanded(child: detailPane),
          ],
        );
      },
    );
  }
}

class _RegExpTesterView extends StatefulWidget {
  const _RegExpTesterView();

  @override
  State<_RegExpTesterView> createState() => _RegExpTesterViewState();
}

class _RegExpTesterViewState extends State<_RegExpTesterView> {
  final TextEditingController _regex = TextEditingController();
  final TextEditingController _text = TextEditingController();
  final TextEditingController _format = TextEditingController(text: r'$0\n');
  final TextEditingController _search = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;
  List<RegExpMatch> _matches = [];

  @override
  void dispose() {
    _regex.dispose();
    _text.dispose();
    _format.dispose();
    _search.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    try {
      final regExp = RegExp(_regex.text);
      _matches = regExp.allMatches(_text.text).toList();
      _output.text = _formatOutput(_matches, _format.text);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _formatOutput(List<RegExpMatch> matches, String format) {
    final formatted = format.replaceAll(r'\n', '\n');
    final buffer = StringBuffer();
    for (final match in matches) {
      var line = formatted;
      for (var i = 0; i <= match.groupCount; i++) {
        line = line.replaceAll('\$$i', match.group(i) ?? '');
      }
      buffer.write(line);
    }
    return buffer.toString();
  }

  Future<void> _pasteRegexClipboard() async {
    final text = await _readClipboardText();
    setState(() => _regex.text = text);
    _run();
  }

  Future<void> _pasteTextClipboard() async {
    final text = await _readClipboardText();
    setState(() => _text.text = text);
    _run();
  }

  void _setSample() {
    setState(() {
      _regex.text = r'([A-Z])\w+';
      _text.text =
          'DevUtils helps you with your tiny daily tasks. It works entirely offline.';
    });
    _run();
  }

  void _clearAll() {
    setState(() {
      _regex.clear();
      _text.clear();
      _output.clear();
      _matches = [];
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  List<RegExpMatch> _filteredMatches() {
    final query = _search.text.toLowerCase();
    if (query.isEmpty) return _matches;
    return _matches.where((match) {
      final text = match.group(0) ?? '';
      return text.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _filteredMatches();

    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'RegExp:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(
                    width: 220,
                    child: _InlineTextField(
                      hintText: r'([A-Z])\w+',
                      controller: _regex,
                      onChanged: (_) => _run(),
                    ),
                  ),
                  ToolButton(
                    label: 'Clipboard',
                    onPressed: _pasteRegexClipboard,
                  ),
                  ToolButton(label: 'Sample', onPressed: _setSample),
                  ToolButton(label: 'Clear', onPressed: _clearAll),
                  const ToolIconButton(icon: Icons.settings),
                  const SizedBox(width: 8),
                  const Text(
                    'Text:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  ToolButton(
                    label: 'Clipboard',
                    onPressed: _pasteTextClipboard,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _text,
                    maxLines: null,
                    onChanged: (_) => _run(),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Output:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(
                    width: 120,
                    child: _InlineTextField(
                      hintText: r'$0\n',
                      controller: _format,
                      onChanged: (_) => _run(),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: _InlineTextField(
                      hintText: 'Search matches...',
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: EditorPane(
                  label: '',
                  actions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
                  controller: _output,
                  readOnly: true,
                  placeholder: '',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  const Spacer(),
                  const Icon(Icons.chevron_left, size: 16),
                  const SizedBox(width: 8),
                  Text('${_matches.length} matches'),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 16),
                ],
              ),
              const SizedBox(height: 8),
              const ToolButton(label: 'Cheat Sheet'),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: ListView.separated(
                    itemCount: matches.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 8),
                    itemBuilder: (context, index) {
                      final match = matches[index];
                      final value = match.group(0) ?? '';
                      return Text('"$value" (${match.start}, ${match.end})');
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HtmlEntityView extends StatefulWidget {
  const _HtmlEntityView();

  @override
  State<_HtmlEntityView> createState() => _HtmlEntityViewState();
}

class _HtmlEntityViewState extends State<_HtmlEntityView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  var _encode = true;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    setState(() {
      _output.text = _encode ? _encodeEntities(text) : _decodeEntities(text);
    });
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(() => _input.text = '<h1>Hello</h1>');
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return buildVerticalEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
        const ToolIconButton(icon: Icons.settings),
        SegmentedToggle(
          options: const ['Encode', 'Decode'],
          initialIndex: _encode ? 0 : 1,
          onChanged: (index) {
            setState(() => _encode = index == 0);
            _run();
          },
        ),
      ],
      outputActions: [
        ToolButton(label: 'Copy', onPressed: _copyOutput),
        const ToolButton(label: 'Use as input'),
      ],
      inputPlaceholder: '<h1>Hello</h1>',
      outputPlaceholder: '&lt;h1&gt;Hello&lt;/h1&gt;',
      inputController: _input,
      outputController: _output,
    );
  }
}

String _encodeEntities(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _decodeEntities(String input) {
  final named = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    '#39': "'",
  };
  return input.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (
    match,
  ) {
    final value = match.group(1) ?? '';
    if (value.startsWith('#x') || value.startsWith('#X')) {
      final hex = value.substring(2);
      final code = int.tryParse(hex, radix: 16);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    if (value.startsWith('#')) {
      final num = int.tryParse(value.substring(1));
      return num == null ? match.group(0)! : String.fromCharCode(num);
    }
    return named[value] ?? match.group(0)!;
  });
}

class _UnixTimeConverterView extends StatefulWidget {
  const _UnixTimeConverterView();

  @override
  State<_UnixTimeConverterView> createState() => _UnixTimeConverterViewState();
}

class _UnixTimeConverterViewState extends State<_UnixTimeConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _local = TextEditingController();
  final TextEditingController _utc = TextEditingController();
  final TextEditingController _relative = TextEditingController();
  final TextEditingController _unix = TextEditingController();
  final TextEditingController _dayOfYear = TextEditingController();
  final TextEditingController _weekOfYear = TextEditingController();
  final TextEditingController _isLeapYear = TextEditingController();
  final TextEditingController _otherLocal = TextEditingController();
  String _format = 'Unix time (seconds since epoch)';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _local.dispose();
    _utc.dispose();
    _relative.dispose();
    _unix.dispose();
    _dayOfYear.dispose();
    _weekOfYear.dispose();
    _isLeapYear.dispose();
    _otherLocal.dispose();
    super.dispose();
  }

  void _applyDate(DateTime utcDate) {
    final local = utcDate.toLocal();
    _local.text = local.toString();
    _utc.text = utcDate.toIso8601String();
    _unix.text = (utcDate.millisecondsSinceEpoch / 1000).round().toString();
    _dayOfYear.text = _calcDayOfYear(local).toString();
    _weekOfYear.text = _calcWeekOfYear(local).toString();
    _isLeapYear.text = _isLeap(local.year) ? 'Yes' : 'No';
    _otherLocal.text = local.toString();
    _relative.text = _relativeFromNow(local);
  }

  void _convert() {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      _clearOutputs();
      setState(() => _error = null);
      return;
    }
    final value = num.tryParse(raw);
    if (value == null) {
      setState(() => _error = 'Invalid number input.');
      return;
    }
    final ms = _format.contains('ms') ? value.round() : (value * 1000).round();
    final date = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    _applyDate(date);
    setState(() => _error = null);
  }

  void _clearOutputs() {
    _local.clear();
    _utc.clear();
    _relative.clear();
    _unix.clear();
    _dayOfYear.clear();
    _weekOfYear.clear();
    _isLeapYear.clear();
    _otherLocal.clear();
  }

  void _setNow() {
    final now = DateTime.now().toUtc();
    setState(() {
      _input.text = _format.contains('ms')
          ? now.millisecondsSinceEpoch.toString()
          : (now.millisecondsSinceEpoch / 1000).round().toString();
    });
    _applyDate(now);
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _convert();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _clearOutputs();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Input:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                ToolButton(label: 'Now', onPressed: _setNow),
                ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
                ToolButton(label: 'Clear', onPressed: _clearInput),
                const ToolIconButton(icon: Icons.settings),
                SmallDropdown(
                  items: const [
                    'Unix time (seconds since epoch)',
                    'Unix time (ms)',
                  ],
                  initialValue: _format,
                  onChanged: (value) {
                    setState(() => _format = value);
                    _convert();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                controller: _input,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (_) => _convert(),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tips: Mathematical operators + - * / are supported',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final leftFields = Column(
                  children: [
                    LabeledField(
                      label: 'Local:',
                      trailing: ToolIconButton(
                        icon: Icons.copy,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _local.text));
                        },
                      ),
                      controller: _local,
                      readOnly: true,
                    ),
                    LabeledField(
                      label: 'UTC (ISO 8601):',
                      trailing: ToolIconButton(
                        icon: Icons.copy,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _utc.text));
                        },
                      ),
                      controller: _utc,
                      readOnly: true,
                    ),
                    LabeledField(
                      label: 'Relative:',
                      trailing: ToolIconButton(
                        icon: Icons.copy,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _relative.text),
                          );
                        },
                      ),
                      controller: _relative,
                      readOnly: true,
                    ),
                    LabeledField(
                      label: 'Unix time:',
                      trailing: ToolIconButton(
                        icon: Icons.copy,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _unix.text));
                        },
                      ),
                      controller: _unix,
                      readOnly: true,
                    ),
                  ],
                );
                final rightFields = Column(
                  children: [
                    LabeledField(
                      label: 'Day of year',
                      trailing: ToolIconButton(
                        icon: Icons.copy,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _dayOfYear.text),
                          );
                        },
                      ),
                      controller: _dayOfYear,
                      readOnly: true,
                    ),
                    LabeledField(
                      label: 'Week of year',
                      trailing: ToolIconButton(
                        icon: Icons.copy,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _weekOfYear.text),
                          );
                        },
                      ),
                      controller: _weekOfYear,
                      readOnly: true,
                    ),
                    LabeledField(
                      label: 'Is leap year?',
                      trailing: ToolIconButton(
                        icon: Icons.copy,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _isLeapYear.text),
                          );
                        },
                      ),
                      controller: _isLeapYear,
                      readOnly: true,
                    ),
                    LabeledField(
                      label: 'Other formats (local)',
                      trailing: ToolIconButton(
                        icon: Icons.copy,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _otherLocal.text),
                          );
                        },
                      ),
                      controller: _otherLocal,
                      readOnly: true,
                    ),
                  ],
                );

                if (constraints.maxWidth < 720) {
                  return Column(
                    children: [
                      leftFields,
                      const SizedBox(height: 8),
                      rightFields,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: leftFields),
                    const SizedBox(width: 24),
                    Expanded(child: rightFields),
                  ],
                );
              },
            ),
            const Divider(height: 32),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Other timezones:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SmallDropdown(
                  items: ['Add timezone...', 'UTC', 'America/Los_Angeles'],
                  initialValue: 'Add timezone...',
                ),
                ToolButton(label: 'Add'),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '(Pick a timezone to get started...)',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isLeap(int year) {
  if (year % 400 == 0) return true;
  if (year % 100 == 0) return false;
  return year % 4 == 0;
}

int _calcDayOfYear(DateTime date) {
  final start = DateTime(date.year, 1, 1);
  return date.difference(start).inDays + 1;
}

int _calcWeekOfYear(DateTime date) {
  final dayOfYear = _calcDayOfYear(date);
  return ((dayOfYear - date.weekday + 10) / 7).floor();
}

class _MimeTypesView extends StatefulWidget {
  const _MimeTypesView();

  @override
  State<_MimeTypesView> createState() => _MimeTypesViewState();
}

class _MimeTypesViewState extends State<_MimeTypesView> {
  final TextEditingController _search = TextEditingController();
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MimeTypeEntry> _filteredEntries() {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return List<MimeTypeEntry>.from(mimeTypeEntries);
    }
    return mimeTypeEntries.where((entry) {
      return entry.name.toLowerCase().contains(query) ||
          entry.mimeType.toLowerCase().contains(query) ||
          entry.extension.toLowerCase().contains(query) ||
          entry.details.toLowerCase().contains(query);
    }).toList();
  }

  int _compareEntries(MimeTypeEntry a, MimeTypeEntry b, int column) {
    String left;
    String right;
    switch (column) {
      case 1:
        left = a.mimeType;
        right = b.mimeType;
        break;
      case 2:
        left = a.extension;
        right = b.extension;
        break;
      case 3:
        left = a.details;
        right = b.details;
        break;
      case 0:
      default:
        left = a.name;
        right = b.name;
        break;
    }
    return left.toLowerCase().compareTo(right.toLowerCase());
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries();
    entries.sort((a, b) {
      final result = _compareEntries(a, b, _sortColumnIndex);
      return _sortAscending ? result : -result;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search name, type, extension, details...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${entries.length} entries',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD5D5D5)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    sortAscending: _sortAscending,
                    sortColumnIndex: _sortColumnIndex,
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF4F4F4),
                    ),
                    columnSpacing: 24,
                    columns: [
                      DataColumn(label: const Text('Name'), onSort: _onSort),
                      DataColumn(
                        label: const Text('MIME Type / Internet Media Type'),
                        onSort: _onSort,
                      ),
                      DataColumn(
                        label: const Text('File Extension'),
                        onSort: _onSort,
                      ),
                      DataColumn(
                        label: const Text('More Details'),
                        onSort: _onSort,
                      ),
                    ],
                    rows: entries
                        .map(
                          (entry) => DataRow(
                            cells: [
                              DataCell(Text(entry.name)),
                              DataCell(SelectableText(entry.mimeType)),
                              DataCell(Text(entry.extension)),
                              DataCell(Text(entry.details)),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _relativeFromNow(DateTime date) {
  final now = DateTime.now();
  final diff = date.difference(now);
  final seconds = diff.inSeconds.abs();
  final minutes = diff.inMinutes.abs();
  final hours = diff.inHours.abs();
  String value;
  if (seconds < 60) {
    value = '$seconds seconds';
  } else if (minutes < 60) {
    value = '$minutes minutes';
  } else {
    value = '$hours hours';
  }
  return diff.isNegative ? '$value ago' : 'in $value';
}

Widget buildUnixTimeConverter() {
  return const _UnixTimeConverterView();
}

Widget buildJsonFormatValidate() {
  return const _JsonFormatValidateView();
}

Widget buildBase64String() {
  return const _Base64StringView();
}

Widget buildBase64Image() {
  return const _Base64ImageView();
}

Widget buildJwtDebugger() {
  return const _JwtDebuggerView();
}

Widget buildRegExpTester() {
  return const _RegExpTesterView();
}

Widget buildUrlEncodeDecode() {
  return const _UrlEncodeDecodeView();
}

Widget buildUrlParser() {
  return const _UrlParserView();
}

Widget buildHtmlEntityEncodeDecode() {
  return const _HtmlEntityView();
}

Widget buildBackslashEscapeUnescape() {
  return const _BackslashEscapeView();
}

Widget buildUuidUlid() {
  return const _UuidUlidView();
}

Widget buildHtmlPreview() {
  return const _HtmlPreviewView();
}

Widget buildTextDiffChecker() {
  return const _TextDiffView();
}

Widget buildYamlToJson() {
  return const _YamlToJsonView();
}

Widget buildJsonToYaml() {
  return const _JsonToYamlView();
}

Widget buildYamlJsonConverter() {
  return const _YamlJsonConverterView();
}

Widget buildNumberBaseConverter() {
  return const _NumberBaseConverterView();
}

Widget buildHtmlBeautifyMinify(String language) {
  if (language == 'JS') {
    return const _JsBeautifyMinifyView();
  }
  if (language == 'HTML') {
    return const _HtmlBeautifyMinifyView();
  }
  return _SimplePassThroughView(
    inputPlaceholder: 'Paste $language here...',
    showIndent: true,
  );
}

Widget buildXmlBeautifyMinify() {
  return _SimplePassThroughView(
    inputPlaceholder: 'Paste XML here...',
    showIndent: true,
    showIncludeComments: true,
  );
}

Widget buildLoremIpsum() {
  return const _LoremIpsumView();
}

Widget buildQrCode() {
  return const _QrCodeView();
}

Widget buildStringInspector() {
  return const _StringInspectorView();
}

Widget buildMimeTypes() {
  return const _MimeTypesView();
}

Widget buildJsonToCsv() {
  return const _JsonToCsvView();
}

Widget buildCsvToJson() {
  return const _CsvToJsonView();
}

Widget buildJsonCsvConverter() {
  return const _JsonCsvConverterView();
}

Widget buildHashGenerator() {
  return const _HashGeneratorView();
}

Widget buildTextEncryption() {
  return const _TextEncryptionView();
}

Widget buildUserAgentTool() {
  return const _UserAgentToolView();
}

Widget buildAntiBotDetection() {
  return const _AntiBotDetectorView();
}

Widget buildOfflineLlm() {
  return const _OfflineLlmView();
}

Widget buildHtmlToJsx() {
  return buildSplitEditors(
    inputActions: const [
      ToolButton(label: 'Go'),
      ToolButton(label: 'Clipboard'),
      ToolButton(label: 'Sample'),
      ToolButton(label: 'Clear'),
    ],
    outputActions: const [ToolButton(label: 'Copy')],
  );
}

Widget buildMarkdownPreview() {
  return const _MarkdownPreviewView();
}

Widget buildSqlFormatter() {
  return const _SqlFormatterView();
}

Widget buildStringCaseConverter() {
  return const _StringCaseConverterView();
}

Widget buildCronJobParser() {
  return const _CronJobParserView();
}

Widget buildColorConverter() {
  return const _ColorConverterView();
}

Widget buildPhpTool(String title) {
  return buildSplitEditors(
    inputActions: const [
      ToolButton(label: 'Go'),
      ToolButton(label: 'Clipboard'),
      ToolButton(label: 'Sample'),
      ToolButton(label: 'Clear'),
      ToolIconButton(icon: Icons.settings),
    ],
    outputActions: const [ToolButton(label: 'Copy')],
    inputPlaceholder: 'Paste $title input...',
    outputPlaceholder: 'Scripts Runtime for this tool is missing (php)',
  );
}

Widget buildPhpJsonConverter() {
  return const _PhpJsonConverterView();
}

Widget buildRandomStringGenerator() {
  return const _RandomStringGeneratorView();
}

Widget buildSvgToCss() {
  return const _SvgToCssView();
}

Widget buildCurlToCode() {
  return const _CurlToCodeView();
}

Widget buildJsonToCode() {
  return const _JsonToCodeView();
}

Widget buildCertificateDecoder() {
  return const _CertificateDecoderView();
}

Widget buildAuthTotp() {
  return const _AuthTotpView();
}

Widget buildHexToAscii() {
  return const _HexToAsciiView();
}

Widget buildAsciiToHex() {
  return const _AsciiToHexView();
}

Widget buildHexAsciiConverter() {
  return const _HexAsciiConverterView();
}

Widget buildLineSortDedupe() {
  return const _LineSortDedupeView();
}

Widget buildPreferencesGeneral() {
  return const _PreferencesGeneralView();
}

Widget buildPreferencesAppearance() {
  return const _PreferencesAppearanceView();
}

Widget buildPreferencesScripting() {
  return const _PreferencesScriptingView();
}

class _PrefCheckbox extends StatelessWidget {
  const _PrefCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: onChanged),
          Text(label),
        ],
      ),
    );
  }
}

class _PreferencesGeneralView extends StatefulWidget {
  const _PreferencesGeneralView();

  @override
  State<_PreferencesGeneralView> createState() =>
      _PreferencesGeneralViewState();
}

class _PreferencesGeneralViewState extends State<_PreferencesGeneralView> {
  bool _hideOnLaunch = false;
  bool _confirmQuit = false;
  bool _shareAnalytics = false;
  bool _writeLogs = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hideOnLaunch = prefs.getBool('pref_hide_on_launch') ?? false;
        _confirmQuit = prefs.getBool('pref_confirm_quit') ?? false;
        _shareAnalytics = prefs.getBool('pref_share_analytics') ?? false;
        _writeLogs = prefs.getBool('pref_write_logs') ?? false;
        _loaded = true;
      });
    });
  }

  Future<void> _setPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _PreferencesShell(
      selectedLabel: 'General',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PrefCheckbox(
            label: 'Always hide the main window at launch',
            value: _hideOnLaunch,
            onChanged: (value) {
              setState(() => _hideOnLaunch = value ?? false);
              _setPref('pref_hide_on_launch', _hideOnLaunch);
            },
          ),
          _PrefCheckbox(
            label: 'Ask to confirm when quitting with Cmd+Q',
            value: _confirmQuit,
            onChanged: (value) {
              setState(() => _confirmQuit = value ?? false);
              _setPref('pref_confirm_quit', _confirmQuit);
            },
          ),
          _PrefCheckbox(
            label: 'Share anonymous crash reports and analytics',
            value: _shareAnalytics,
            onChanged: (value) {
              setState(() => _shareAnalytics = value ?? false);
              _setPref('pref_share_analytics', _shareAnalytics);
            },
          ),
          Row(
            children: [
              Expanded(
                child: _PrefCheckbox(
                  label: 'Write debug logs',
                  value: _writeLogs,
                  onChanged: (value) {
                    setState(() => _writeLogs = value ?? false);
                    _setPref('pref_write_logs', _writeLogs);
                  },
                ),
              ),
              const ToolButton(label: 'Open logs directory'),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Text('Stored preferences location'),
              SizedBox(width: 8),
              ToolButton(label: 'Open'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreferencesAppearanceView extends StatefulWidget {
  const _PreferencesAppearanceView();

  @override
  State<_PreferencesAppearanceView> createState() =>
      _PreferencesAppearanceViewState();
}

class _PreferencesAppearanceViewState
    extends State<_PreferencesAppearanceView> {
  bool _showStatusBar = true;
  bool _showDock = true;
  String _theme = 'System';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _showStatusBar = prefs.getBool('pref_show_status_bar') ?? true;
        _showDock = prefs.getBool('pref_show_dock') ?? true;
        _theme = prefs.getString('pref_theme') ?? 'System';
        _loaded = true;
      });
    });
  }

  Future<void> _setPref(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _PreferencesShell(
      selectedLabel: 'Appearance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PrefCheckbox(
            label: 'Show Status Bar icon',
            value: _showStatusBar,
            onChanged: (value) {
              setState(() => _showStatusBar = value ?? true);
              _setPref('pref_show_status_bar', _showStatusBar);
            },
          ),
          _PrefCheckbox(
            label: 'Show Dock icon',
            value: _showDock,
            onChanged: (value) {
              setState(() => _showDock = value ?? true);
              _setPref('pref_show_dock', _showDock);
            },
          ),
          Row(
            children: [
              const Text('Theme'),
              const SizedBox(width: 12),
              SmallDropdown(
                items: const ['System', 'Light', 'Dark'],
                initialValue: _theme,
                onChanged: (value) {
                  setState(() => _theme = value);
                  _setPref('pref_theme', _theme);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreferencesScriptingView extends StatefulWidget {
  const _PreferencesScriptingView();

  @override
  State<_PreferencesScriptingView> createState() =>
      _PreferencesScriptingViewState();
}

class _PreferencesScriptingViewState extends State<_PreferencesScriptingView> {
  int _segment = 0;
  String _phpPath = 'No Usable PHP Runtime';
  final TextEditingController _whitelist = TextEditingController(
    text: 'serialize,var_export,json_encode,json_decode,unserialize',
  );
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _segment = prefs.getInt('pref_script_segment') ?? 0;
        _phpPath = prefs.getString('pref_php_path') ?? 'No Usable PHP Runtime';
        _whitelist.text =
            prefs.getString('pref_php_whitelist') ??
            'serialize,var_export,json_encode,json_decode,unserialize';
        _loaded = true;
      });
    });
  }

  Future<void> _setPref(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  void dispose() {
    _whitelist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _PreferencesShell(
      selectedLabel: 'Scripting',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToggleButtons(
            isSelected: List<bool>.generate(3, (i) => i == _segment),
            onPressed: (index) {
              setState(() => _segment = index);
              _setPref('pref_script_segment', _segment);
            },
            borderRadius: BorderRadius.circular(6),
            constraints: const BoxConstraints(minHeight: 32, minWidth: 80),
            children: const [Text('PHP'), Text('Open SSL'), Text('Others')],
          ),
          const SizedBox(height: 16),
          const Text('Default command path:'),
          const SizedBox(height: 8),
          SmallDropdown(
            items: [_phpPath],
            initialValue: _phpPath,
            onChanged: (value) => setState(() => _phpPath = value),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              ToolButton(label: 'Add New Path...'),
              SizedBox(width: 12),
              ToolButton(label: 'Remove'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'PHP code is run in safe mode with only whitelisted functions below allowed.',
          ),
          const SizedBox(height: 8),
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _whitelist,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText:
                    'serialize,var_export,json_encode,json_decode,unserialize',
              ),
              onChanged: (value) => _setPref('pref_php_whitelist', value),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferencesShell extends StatelessWidget {
  const _PreferencesShell({required this.child, required this.selectedLabel});

  final Widget child;
  final String selectedLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PrefTab(label: 'General', selected: selectedLabel == 'General'),
            _PrefTab(label: 'Hotkeys', selected: selectedLabel == 'Hotkeys'),
            _PrefTab(
              label: 'Appearance',
              selected: selectedLabel == 'Appearance',
            ),
            _PrefTab(
              label: 'Integrations',
              selected: selectedLabel == 'Integrations',
            ),
            _PrefTab(
              label: 'Scripting',
              selected: selectedLabel == 'Scripting',
            ),
            _PrefTab(label: 'Updates', selected: selectedLabel == 'Updates'),
            _PrefTab(label: 'License', selected: selectedLabel == 'License'),
          ],
        ),
        const Divider(height: 24),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _PrefTab extends StatelessWidget {
  const _PrefTab({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Icon(
            Icons.settings,
            size: 24,
            color: selected ? Colors.blue : Colors.black54,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: selected ? Colors.blue : Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _InlineTextField extends StatelessWidget {
  const _InlineTextField({
    this.hintText,
    this.width,
    this.controller,
    this.onChanged,
  });

  final String? hintText;
  final double? width;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            border: InputBorder.none,
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class _HashField extends StatelessWidget {
  const _HashField({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text('$label:')),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black12),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 28, 6),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        value,
                        softWrap: false,
                        style: const TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_all, size: 16),
                      tooltip: 'Copy',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      splashRadius: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BaseRow extends StatelessWidget {
  const _BaseRow({
    required this.label,
    this.trailing,
    this.actions = const ['Clipboard', 'Clear'],
    this.controller,
    this.onChanged,
  });

  final String label;
  final Widget? trailing;
  final List<String> actions;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (trailing != null) trailing!,
              const Spacer(),
              for (final action in actions) ...[
                ToolButton(
                  label: action,
                  onPressed: () async {
                    if (controller == null) return;
                    if (action == 'Clipboard') {
                      final text = await _readClipboardText();
                      controller!.text = text;
                      onChanged?.call(text);
                    } else if (action == 'Clear') {
                      controller!.clear();
                      onChanged?.call('');
                    } else if (action == 'Sample') {
                      controller!.text = '123';
                      onChanged?.call('123');
                    }
                  },
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 6),
          _InlineTextField(controller: controller, onChanged: onChanged),
        ],
      ),
    );
  }
}
