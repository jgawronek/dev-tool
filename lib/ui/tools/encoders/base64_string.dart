/// Base64 string encode/decode tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

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
        final bytes = base64Decode(_normalizeBase64(text));
        _output.text = utf8.decode(bytes, allowMalformed: true);
      }
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  /// Accepts whitespace, a missing `=` padding, and the URL-safe `-`/`_`
  /// alphabet so common hand-pasted input decodes instead of erroring.
  String _normalizeBase64(String input) {
    var value = input.trim().replaceAll(RegExp(r'\s+'), '');
    value = value.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = value.length % 4;
    switch (remainder) {
      case 2:
        value += '==';
      case 3:
        value += '=';
      case 0:
        break;
      default:
        throw const FormatException('Invalid base64 length');
    }
    return value;
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
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
            child: Text(_error!, style: errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

Widget buildBase64String() {
  return const _Base64StringView();
}
