/// PHP Serializer/Unserializer tool views.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

String _phpSerialize(Object? value) {
  if (value == null) return 'N;';
  if (value is bool) return 'b:${value ? 1 : 0};';
  if (value is int) return 'i:$value;';
  if (value is double) {
    return 'd:${value == value.roundToDouble() ? value.toStringAsFixed(1) : value};';
  }
  if (value is num) return 'd:$value;';
  if (value is String) {
    return 's:${utf8.encode(value).length}:"$value";';
  }
  if (value is List) {
    final buffer = StringBuffer('a:${value.length}:{');
    for (var i = 0; i < value.length; i++) {
      buffer.write('i:$i;');
      buffer.write(_phpSerialize(value[i]));
    }
    buffer.write('}');
    return buffer.toString();
  }
  if (value is Map) {
    final buffer = StringBuffer('a:${value.length}:{');
    value.forEach((key, element) {
      buffer.write(_phpSerializeKey(key));
      buffer.write(_phpSerialize(element));
    });
    buffer.write('}');
    return buffer.toString();
  }
  return 'N;';
}

String _phpSerializeKey(Object? key) {
  final keyString = key.toString();
  final asInt = int.tryParse(keyString);
  if (asInt != null && asInt.toString() == keyString) return 'i:$asInt;';
  return 's:${utf8.encode(keyString).length}:"$keyString";';
}

Object? _phpUnserialize(String input) {
  final (value, next) = _phpParse(input, 0);
  final rest = input.substring(next).trim();
  if (rest.isNotEmpty) {
    throw FormatException('Unexpected trailing data at offset $next');
  }
  return value;
}

(Object?, int) _phpParse(String source, int index) {
  if (index >= source.length) {
    throw const FormatException('Unexpected end of input');
  }
  final type = source[index];
  switch (type) {
    case 'N':
      _expect(source, index + 1, ';');
      return (null, index + 2);
    case 'b':
      final semi = source.indexOf(';', index);
      if (semi == -1) throw const FormatException('Malformed boolean');
      return (source.substring(index + 2, semi) == '1', semi + 1);
    case 'i':
      final semi = source.indexOf(';', index);
      if (semi == -1) throw const FormatException('Malformed integer');
      return (int.parse(source.substring(index + 2, semi)), semi + 1);
    case 'd':
      final semi = source.indexOf(';', index);
      if (semi == -1) throw const FormatException('Malformed double');
      return (double.parse(source.substring(index + 2, semi)), semi + 1);
    case 's':
      final colon1 = source.indexOf(':', index);
      final colon2 = source.indexOf(':', colon1 + 1);
      final length = int.parse(source.substring(colon1 + 1, colon2));
      final start = colon2 + 2; // skip :"
      var consumed = 0;
      var cursor = start;
      while (cursor < source.length && consumed < length) {
        consumed += utf8.encode(source[cursor]).length;
        cursor++;
      }
      final text = source.substring(start, cursor);
      _expect(source, cursor, '"');
      _expect(source, cursor + 1, ';');
      return (text, cursor + 2);
    case 'a':
      final colon1 = source.indexOf(':', index);
      final colon2 = source.indexOf(':', colon1 + 1);
      final count = int.parse(source.substring(colon1 + 1, colon2));
      var cursor = colon2 + 2; // skip :{
      final entries = <Object?, Object?>{};
      var isList = true;
      for (var n = 0; n < count; n++) {
        final (key, afterKey) = _phpParse(source, cursor);
        final (element, afterValue) = _phpParse(source, afterKey);
        entries[key] = element;
        if (key != n) isList = false;
        cursor = afterValue;
      }
      _expect(source, cursor, '}');
      cursor += 1;
      if (isList) return (entries.values.toList(), cursor);
      final map = <String, Object?>{};
      entries.forEach((key, element) => map[key.toString()] = element);
      return (map, cursor);
    default:
      throw FormatException('Unsupported PHP type "$type" at offset $index');
  }
}

void _expect(String source, int index, String expected) {
  if (index >= source.length || source[index] != expected) {
    throw FormatException('Expected "$expected" at offset $index');
  }
}

class _PhpSerializerView extends StatefulWidget {
  const _PhpSerializerView({required this.serialize});

  /// `true` for the serializer (JSON -> PHP), `false` for the unserializer.
  final bool serialize;

  @override
  State<_PhpSerializerView> createState() => _PhpSerializerViewState();
}

class _PhpSerializerViewState extends State<_PhpSerializerView> {
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
      if (widget.serialize) {
        final decoded = jsonDecode(text);
        _output.text = _phpSerialize(decoded);
      } else {
        final value = _phpUnserialize(text);
        _output.text = const JsonEncoder.withIndent('  ').convert(value);
      }
    } catch (error) {
      _output.text = widget.serialize
          ? 'Invalid JSON input: $error'
          : 'Invalid PHP serialized input: $error';
    }
    setState(() {});
  }

  void _setSample() {
    setState(() {
      _input.text = widget.serialize
          ? '{"name":"DevUtils","tags":["json","php"],"count":3,"active":true}'
          : 'a:3:{s:4:"name";s:8:"DevUtils";s:5:"count";i:3;s:6:"active";b:1;}';
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: buildSplitEditors(
        inputActions: [ToolButton(label: 'Go', onPressed: _run)],
        outputActions: [
          ToolButton(
            label: 'Copy',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _output.text)),
          ),
        ],
        inputController: _input,
        outputController: _output,
        onInputChanged: (_) => _run(),
        inputPlaceholder: widget.serialize
            ? 'Paste JSON to serialize into a PHP string...'
            : 'Paste a PHP serialized string to decode...',
        outputPlaceholder: widget.serialize
            ? 'PHP serialized output...'
            : 'Decoded JSON output...',
      ),
    );
  }
}

Widget buildPhpTool(String title) {
  return _PhpSerializerView(
    serialize: !title.toLowerCase().contains('unserial'),
  );
}
