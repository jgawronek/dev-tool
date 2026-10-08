/// YAML ↔ JSON converter tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

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
      final encoder = JsonEncoder.withIndent(indentFor(_indent));
      _output.text = encoder.convert(normalized);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
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
            child: Text(_error!, style: errorToolTextStyle(context)),
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
        final encoder = JsonEncoder.withIndent(indentFor(_indent));
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
    final text = await readClipboardText();
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
            child: Text(_error!, style: errorToolTextStyle(context)),
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
    final text = await readClipboardText();
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
            child: Text(_error!, style: errorToolTextStyle(context)),
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

Widget buildYamlToJson() {
  return const _YamlToJsonView();
}

Widget buildJsonToYaml() {
  return const _JsonToYamlView();
}

Widget buildYamlJsonConverter() {
  return const _YamlJsonConverterView();
}
