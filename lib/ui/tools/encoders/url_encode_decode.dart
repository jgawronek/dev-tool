/// URL encode/decode tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

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
      _output.clear();
      setState(() => _error = e.toString());
    }
  }

  void _setSample() {
    setState(
      () => _input.text = _encode
          ? r'abc 0123 !@#$'
          : 'abc%200123%20%21%40%23%24',
    );
    _run();
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _useAsInput() {
    setState(() => _input.text = _output.text);
    _run();
  }

  @override
  Widget build(BuildContext context) {
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
              child: Text(_error!, style: errorToolTextStyle(context)),
            ),
          ],
        ],
      ),
    );
  }
}

Widget buildUrlEncodeDecode() {
  return const _UrlEncodeDecodeView();
}
