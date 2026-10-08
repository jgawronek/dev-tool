/// HTML entity encode/decode tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

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
    final text = await readClipboardText();
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
  return input.replaceAllMapped(RegExp(r'&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);'), (
    match,
  ) {
    final value = match.group(1) ?? '';
    final lowerValue = value.toLowerCase();
    if (lowerValue.startsWith('#x')) {
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

Widget buildHtmlEntityEncodeDecode() {
  return const _HtmlEntityView();
}
