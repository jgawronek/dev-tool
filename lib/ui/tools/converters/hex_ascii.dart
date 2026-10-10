/// Hex ↔ ASCII converter tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

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
      _output.text = utf8.decode(bytes, allowMalformed: true);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _setSample() {
    setState(() {
      _input.text = '48 65 6C 6C 6F 20 66 72 6F 6D 20 44 65 76 55 74 69 6C 73';
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        children: [
          Expanded(
            child: buildSplitEditors(
              inputActions: [ToolButton(label: 'Go', onPressed: _run)],
              outputActions: [
                ToolButton(label: 'Copy', onPressed: _copyOutput),
              ],
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
              child: Text(_error!, style: errorToolTextStyle(context)),
            ),
          ],
        ],
      ),
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

  void _setSample() {
    setState(() => _input.text = 'Hello from DevUtils');
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: buildSplitEditors(
        inputActions: [ToolButton(label: 'Go', onPressed: _run)],
        outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
        inputPlaceholder: 'Hello from DevUtils',
        outputPlaceholder: '48 65 6C 6C 6F',
        inputController: _input,
        outputController: _output,
      ),
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
        _output.text = utf8.decode(bytes, allowMalformed: true);
      } else {
        final bytes = utf8.encode(text);
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
    return ToolSampleAction(
      onPressed: () {
        setState(() => _input.text = _hexToAscii ? '48 65 6C 6C 6F' : 'Hello');
        _run();
      },
      child: Column(
        children: [
          Expanded(
            child: buildSplitEditors(
              inputActions: [
                ToolButton(label: 'Go', onPressed: _run),

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
              child: Text(_error!, style: errorToolTextStyle(context)),
            ),
          ],
        ],
      ),
    );
  }
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
