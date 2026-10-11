/// Compress/decompress tool view.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/compression_service.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

/// Inputs past this size move to a background isolate; compressing a few MB
/// of text synchronously would stall the editor's caret.
const _isolateThreshold = 200000;

class _CompressionView extends StatefulWidget {
  const _CompressionView();

  @override
  State<_CompressionView> createState() => _CompressionViewState();
}

class _CompressionViewState extends State<_CompressionView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();

  CompressionCodec _codec = CompressionCodec.gzip;
  var _compressing = true;
  String _summary = '';
  String? _error;
  int _token = 0;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  bool get _modeCompress => _compressing;

  Future<void> _run() async {
    final token = ++_token;
    final text = _input.text;
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _summary = '';
        _error = null;
      });
      return;
    }

    // A newer keystroke supersedes this run.
    final codec = _codec;
    final compressing = _compressing;

    CompressionOutcome outcome;
    try {
      if (compressing) {
        outcome = text.length > _isolateThreshold
            ? await compute(compressWorker, (text, codec.index))
            : compressSync(text, codec);
      } else {
        outcome = text.length > _isolateThreshold
            ? await compute(decompressWorker, (text, codec.index))
            : decompressPayload(text, codec);
      }
    } catch (error) {
      outcome = CompressionOutcome.failure('$error');
    }
    if (!mounted || token != _token) return;

    setState(() {
      _error = outcome.error;
      _summary = outcome.error == null ? outcome.summary : '';
      _output.text = outcome.error == null ? outcome.output : '';
    });
  }

  void _setSample() {
    setState(() {
      _input.text = _modeCompress
          ? 'DevUtils compression sample. '
                'The quick brown fox jumps over the lazy dog. '
                'The quick brown fox jumps over the lazy dog.'
          : 'H4sIAAAAAAAAA8tIzcnJBwCGphA2BQAAAA==';
    });
    _run();
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _useAsInput() {
    setState(() => _input.text = _output.text);
    _run();
  }

  /// Flipping direction is only meaningful with data already in the input,
  /// so the same bytes are re-run through the other operation.
  void _setMode(int index) {
    setState(() => _compressing = index == 0);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final labels = CompressionCodec.values.map((c) => c.label).toList();
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToolToolbar(
            children: [
              SegmentedToggle(
                options: const ['Compress', 'Decompress'],
                initialIndex: _compressing ? 0 : 1,
                onChanged: _setMode,
              ),
              const Text('Format'),
              SmallDropdown(
                items: labels,
                initialValue: _codec.label,
                onChanged: (value) {
                  final index = labels.indexOf(value);
                  if (index < 0) return;
                  setState(() => _codec = CompressionCodec.values[index]);
                  _run();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: buildVerticalEditors(
              inputLabel: _modeCompress ? 'Text' : 'Archive',
              outputLabel: _modeCompress
                  ? 'Base64 archive'
                  : 'Decompressed text',
              inputActions: [],
              outputActions: [
                ToolButton(
                  label: 'Use as input',
                  onPressed: _output.text.isEmpty ? null : _useAsInput,
                ),
                ToolButton(label: 'Copy', onPressed: _copyOutput),
              ],
              inputController: _input,
              outputController: _output,
              onInputChanged: (_) => _run(),
              inputPlaceholder: _modeCompress
                  ? 'Enter text to compress…'
                  : 'Paste Base64 or hex archive data…',
              outputPlaceholder: _modeCompress
                  ? 'Compressed archive will appear here'
                  : 'Decompressed text will appear here',
            ),
          ),
          if (_error != null || _summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error ?? _summary,
                style: _error != null
                    ? errorToolTextStyle(context)
                    : mutedToolTextStyle(context),
              ),
            ),
        ],
      ),
    );
  }
}

Widget buildCompression() {
  return const _CompressionView();
}
