/// Backslash escape/unescape tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

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
    final text = await readClipboardText();
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

Widget buildBackslashEscapeUnescape() {
  return const _BackslashEscapeView();
}
