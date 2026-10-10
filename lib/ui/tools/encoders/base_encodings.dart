/// Base32/Base58/Base62/Base85/Bech32 tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/base_encoding_service.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _BaseEncodingsView extends StatefulWidget {
  const _BaseEncodingsView();

  @override
  State<_BaseEncodingsView> createState() => _BaseEncodingsViewState();
}

class _BaseEncodingsViewState extends State<_BaseEncodingsView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();

  BaseEncoding _encoding = BaseEncoding.base32;
  var _encode = true;
  String _summary = '';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    if (text.trim().isEmpty) {
      setState(() {
        _output.text = '';
        _summary = '';
        _error = null;
      });
      return;
    }
    final outcome = _encode
        ? encodeBaseSync(text, _encoding)
        : decodeBaseSync(text, _encoding);
    setState(() {
      _error = outcome.error;
      _summary = outcome.error == null ? outcome.summary : '';
      _output.text = outcome.error == null ? outcome.output : '';
    });
  }

  void _setSample() {
    setState(() {
      _input.text = _encode
          ? 'Hello Base Encodings! 123'
          : _sampleFor(_encoding);
    });
    _run();
  }

  String _sampleFor(BaseEncoding encoding) {
    switch (encoding) {
      case BaseEncoding.base32:
        return 'JBSWY3DPEBBGC43FEBCW4Y3PMRUW4Z3TEEQDCMRT';
      case BaseEncoding.base58:
        return 'W8ai2bWL3ES4EBR6XrWC2BeLBoipvb4Ee6';
      case BaseEncoding.base62:
        return '3DxS6Aewsy2NoshD9KlFnx4uVE7NHNvWj5';
      case BaseEncoding.base85:
        return '87cURD]hATF(HI_DI[TqBl7R)+WrKp1B';
      case BaseEncoding.bech32:
        return 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
    }
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _useAsInput() {
    setState(() => _input.text = _output.text);
    _run();
  }

  void _setMode(int index) {
    setState(() {
      _encode = index == 0;
      _output.clear();
      _summary = '';
      _error = null;
    });
    _run();
  }

  void _setEncoding(String label) {
    final match = BaseEncoding.values.where((e) => e.label == label);
    if (match.isEmpty) return;
    setState(() => _encoding = match.first);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final labels = BaseEncoding.values.map((e) => e.label).toList();
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        children: [
          Expanded(
            child: buildVerticalEditors(
              inputActions: [
                ToolButton(label: 'Go', onPressed: _run),

                SegmentedToggle(
                  options: const ['Encode', 'Decode'],
                  initialIndex: _encode ? 0 : 1,
                  onChanged: _setMode,
                ),
              ],
              outputActions: [
                ToolButton(label: 'Copy', onPressed: _copyOutput),
                ToolButton(label: 'Use as input', onPressed: _useAsInput),
              ],
              inputController: _input,
              outputController: _output,
              onInputChanged: (_) => _run(),
              inputPlaceholder: _encode
                  ? 'Text to encode...'
                  : 'Paste ${_encoding.label} to decode...',
              outputPlaceholder: _encode
                  ? '${_encoding.label} output...'
                  : 'Decoded text...',
              outputOverlay: SmallDropdown(
                items: labels,
                initialValue: _encoding.label,
                onChanged: _setEncoding,
              ),
            ),
          ),
          if (_error != null || _summary.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error ?? _summary,
                  style: _error != null
                      ? errorToolTextStyle(context)
                      : mutedToolTextStyle(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget buildBaseEncodings() {
  return const _BaseEncodingsView();
}
