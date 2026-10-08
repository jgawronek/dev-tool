/// Cipher decoder tool view: identify, decode, and brute force.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/cipher_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _CipherDecoderView extends StatefulWidget {
  const _CipherDecoderView();

  @override
  State<_CipherDecoderView> createState() => _CipherDecoderViewState();
}

class _CipherDecoderViewState extends State<_CipherDecoderView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  final TextEditingController _shift = TextEditingController(text: '13');
  final TextEditingController _key = TextEditingController(text: 'LEMON');
  final TextEditingController _rails = TextEditingController(text: '3');

  CipherKind _kind = CipherKind.rot13;
  var _mode = 0;
  String _status = '';
  String? _error;
  List<CipherCandidate> _candidates = const [];
  var _running = false;
  int _token = 0;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _shift.dispose();
    _key.dispose();
    _rails.dispose();
    super.dispose();
  }

  CipherOptions get _options => CipherOptions(
        shift: int.tryParse(_shift.text.trim()) ?? 13,
        key: _key.text,
        rails: int.tryParse(_rails.text.trim()) ?? 3,
        baconVariant: 'Classic 24',
      );

  Future<void> _run() async {
    final text = _input.text;
    if (text.trim().isEmpty) {
      setState(() {
        _output.text = '';
        _candidates = const [];
        _status = '';
        _error = null;
      });
      return;
    }

    final token = ++_token;
    final kind = _kind;
    final options = _options;
    final mode = _mode;

    if (mode == 2) {
      setState(() {
        _running = true;
        _error = null;
        _status = 'Trying keys...';
      });
    }

    String? failure;
    String output = '';
    var candidates = <CipherCandidate>[];
    try {
      if (mode == 0) {
        // Identify runs at most ten decodes, which is fast enough to stay on
        // the UI thread so results appear immediately.
        candidates = identifyCipher(text);
        output = candidates.isEmpty ? '' : candidates.first.output;
        _status = candidates.isEmpty
            ? 'No single-step cipher produced readable text.'
            : '${candidates.length} readable result(s); best is '
                '${candidates.first.cipher} at ${candidates.first.scoreLabel}.';
      } else if (mode == 1) {
        output = decodeCipher(text, kind, options);
        final score = readability(output);
        candidates = [
          CipherCandidate(cipher: kind.label, output: output, score: score),
        ];
        _status = '${kind.label} · readability ${(score * 100).round()}%';
      } else {
        final result = await compute(_bruteForceWorker, (text, kind.index));
        candidates = result;
        output = candidates.isEmpty ? '' : candidates.first.output;
        _status = candidates.isEmpty
            ? 'Nothing scored above the readability threshold.'
            : '${candidates.length} result(s); best is '
                '${candidates.first.cipher} at ${candidates.first.scoreLabel}.';
      }
    } catch (error) {
      failure = '$error';
    }
    if (!mounted || token != _token) return;

    setState(() {
      _running = false;
      _error = failure;
      _candidates = failure == null ? candidates : const [];
      _output.text = failure == null ? output : '';
      if (failure != null) _status = '';
    });
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() => _input.text = text);
    _run();
  }

  void _setSample() {
    setState(() {
      _input.text = switch (_mode) {
        2 => 'uryyb' // "hello" with Caesar 13
            '',
        1 => 'uryyb 32',
        _ => 'uryyb 32',
      };
    });
    _run();
  }

  void _clear() {
    setState(() {
      _input.clear();
      _output.clear();
      _candidates = const [];
      _status = '';
      _error = null;
    });
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
      _mode = index;
      _output.clear();
      _candidates = const [];
      _status = '';
      _error = null;
    });
    _run();
  }

  void _setCipher(String label) {
    final match = CipherKind.values.where((c) => c.label == label);
    if (match.isEmpty) return;
    setState(() => _kind = match.first);
    _run();
  }

  /// Loads a candidate into the decode pane so it can be refined further.
  void _exploreCandidate(CipherCandidate candidate) {
    setState(() {
      _mode = 1;
      _kind = CipherKind.values.firstWhere(
        (c) => c.label == candidate.cipher,
        orElse: () => _kind,
      );
      _output.text = candidate.output;
      _candidates = const [];
      _status = 'Loaded ${candidate.cipher}. Refine with the controls.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final labels = CipherKind.values.map((c) => c.label).toList();
    return Column(
      children: [
        Expanded(
          child: buildVerticalEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clear),
              SegmentedToggle(
                options: const ['Identify', 'Decode', 'Brute force'],
                initialIndex: _mode,
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
            inputPlaceholder: 'Ciphertext...',
            outputPlaceholder: 'Plaintext...',
            outputOverlay: _buildControls(context, labels),
          ),
        ),
        if (_candidates.length > 1) _buildCandidateList(context),
        if (_error != null || _status.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error ?? _status,
                style: _error != null
                    ? errorToolTextStyle(context)
                    : mutedToolTextStyle(context),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, List<String> labels) {
    final showCipher = _mode == 1;
    final kind = _kind;
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showCipher) ...[
            SmallDropdown(
              items: labels,
              initialValue: kind.label,
              onChanged: _setCipher,
            ),
            const SizedBox(width: 6),
            if (kind.needsShift) ...[
              const Text('Shift', style: TextStyle(fontSize: 11.5)),
              const SizedBox(width: 4),
              SizedBox(width: 46, child: _MiniField(controller: _shift)),
              const SizedBox(width: 8),
            ],
            if (kind.needsKey) ...[
              const Text('Key', style: TextStyle(fontSize: 11.5)),
              const SizedBox(width: 4),
              SizedBox(width: 96, child: _MiniField(controller: _key)),
              const SizedBox(width: 8),
            ],
            if (kind == CipherKind.railFence) ...[
              const Text('Rails', style: TextStyle(fontSize: 11.5)),
              const SizedBox(width: 4),
              SizedBox(width: 40, child: _MiniField(controller: _rails)),
              const SizedBox(width: 8),
            ],
          ] else
            Text(
              _mode == 0
                  ? 'Tries every single-step cipher'
                  : 'All Caesar shifts, ROT47, Vigenere, and XOR keys',
              style: mutedToolTextStyle(context, fontSize: 11.5),
            ),
          if (_running) ...[
            const SizedBox(width: 6),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
    );
  }

  Widget _buildCandidateList(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      height: 118,
      margin: const EdgeInsets.only(top: 8),
      decoration: toolSurfaceDecoration(context),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: _candidates.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final candidate = _candidates[index];
          return InkWell(
            onTap: () => _exploreCandidate(candidate),
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      candidate.cipher,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      candidate.scoreLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Menlo',
                        color: candidate.score >= 0.6
                            ? appColors.success
                            : appColors.mutedText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      candidate.output.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 11.5,
                        color: appColors.editorText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  const _MiniField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return TextField(
      controller: controller,
      style: TextStyle(
        fontFamily: 'Menlo',
        fontSize: 11.5,
        color: appColors.editorText,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: appColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: appColors.border),
        ),
      ),
    );
  }
}

/// Top-level worker so brute force does not block the UI thread.
List<CipherCandidate> _bruteForceWorker((String, int) args) =>
    bruteForceCipher(args.$1);

Widget buildCipherDecoder() {
  return const _CipherDecoderView();
}