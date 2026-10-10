/// Password hashing and verification tool view.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/password_hash_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _PasswordHashingView extends StatefulWidget {
  const _PasswordHashingView();

  @override
  State<_PasswordHashingView> createState() => _PasswordHashingViewState();
}

class _PasswordHashingViewState extends State<_PasswordHashingView> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _salt = TextEditingController();
  final TextEditingController _rounds = TextEditingController(text: '10');
  final TextEditingController _iterations = TextEditingController(
    text: '210000',
  );
  final TextEditingController _memory = TextEditingController(text: '19456');
  final TextEditingController _lanes = TextEditingController(text: '1');
  final TextEditingController _scryptN = TextEditingController(text: '16384');
  final TextEditingController _scryptR = TextEditingController(text: '8');
  final TextEditingController _scryptP = TextEditingController(text: '1');
  final TextEditingController _verifyHash = TextEditingController();
  final TextEditingController _output = TextEditingController();

  PasswordHashAlgorithm _algorithm = PasswordHashAlgorithm.bcrypt;
  var _verifying = false;
  var _running = false;
  String _status = '';
  String? _error;
  String? _warning;
  int _token = 0;

  @override
  void dispose() {
    _password.dispose();
    _salt.dispose();
    _rounds.dispose();
    _iterations.dispose();
    _memory.dispose();
    _lanes.dispose();
    _scryptN.dispose();
    _scryptR.dispose();
    _scryptP.dispose();
    _verifyHash.dispose();
    _output.dispose();
    super.dispose();
  }

  PasswordHashParams _params() {
    return PasswordHashParams(
      rounds: _rounds.text.trim().isEmpty ? 10 : int.parse(_rounds.text.trim()),
      iterations: _iterations.text.trim().isEmpty
          ? 210000
          : int.parse(_iterations.text.trim()),
      memoryKiB: _memory.text.trim().isEmpty
          ? 19456
          : int.parse(_memory.text.trim()),
      lanes: _lanes.text.trim().isEmpty ? 1 : int.parse(_lanes.text.trim()),
      scryptN: _scryptN.text.trim().isEmpty
          ? 16384
          : int.parse(_scryptN.text.trim()),
      scryptR: _scryptR.text.trim().isEmpty
          ? 8
          : int.parse(_scryptR.text.trim()),
      scryptP: _scryptP.text.trim().isEmpty
          ? 1
          : int.parse(_scryptP.text.trim()),
      salt: _salt.text.trim().isEmpty ? null : _salt.text.trim(),
    );
  }

  Future<void> _run() async {
    if (_running) return;
    final token = ++_token;
    final password = _password.text;
    final verifying = _verifying;
    final encoded = _verifyHash.text.trim();

    if (password.isEmpty) {
      setState(() {
        _output.text = '';
        _status = '';
        _error = 'Enter a password.';
        _warning = null;
      });
      return;
    }
    if (verifying && encoded.isEmpty) {
      setState(() {
        _output.text = '';
        _status = '';
        _error = 'Paste the hash to verify against.';
        _warning = null;
      });
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _warning = null;
      _status = verifying ? 'Verifying...' : 'Hashing...';
    });

    String? failure;
    String output;
    String status;
    String? warning;
    bool matched = false;
    String? detected;
    try {
      if (verifying) {
        final result = await compute(
          verifyPasswordWorker,
          VerifyRequest(password, encoded),
        );
        matched = result.matched;
        detected = result.algorithm;
        output = result.message;
        final via = detected == null ? '' : ' ($detected)';
        status = result.matched
            ? 'Password matches the supplied hash$via.'
            : 'Password does not match the supplied hash$via.';
      } else {
        final request = PasswordHashRequest(password, _algorithm, _params());
        final result = await compute(hashPasswordWorker, request);
        failure = result.error;
        output = result.error ?? result.encoded;
        status = result.error != null
            ? ''
            : '${_algorithm.label} hashed in ${result.elapsedMs} ms.';
        warning = result.warning;
      }
    } catch (error) {
      // Non-numeric cost fields reach here rather than the service.
      failure = 'Invalid parameter: $error';
      output = '';
      status = '';
    }
    if (!mounted || token != _token) return;

    setState(() {
      _running = false;
      _error = failure ?? (verifying && !matched ? output : null);
      _warning = warning;
      _status = failure != null ? '' : status;
      _output.text = failure != null ? '' : output;
    });
  }

  void _setSample() {
    setState(() {
      if (_verifying) {
        _verifyHash.text =
            r'$2a$10$RzKlsrXtOCkfiDgiI.obXePDzAqZ5Xwx41U/.JhTqI6bXNRlH/P9y';
        _password.text = 'swordfish';
      } else {
        _password.text = 'correct horse battery staple';
        _salt.clear();
      }
    });
    _run();
  }

  void _setAlgorithm(String label) {
    final match = PasswordHashAlgorithm.values.where((a) => a.label == label);
    if (match.isEmpty) return;
    setState(() {
      _algorithm = match.first;
      // Each KDF has its own cost knobs; carry over nothing but the salt.
      _salt.clear();
    });
    if (!_verifying) _run();
  }

  void _setMode(int index) {
    setState(() {
      _verifying = index == 1;
      _output.clear();
      _status = '';
      _error = null;
      _warning = null;
    });
    if (_verifying && _verifyHash.text.isNotEmpty) _run();
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _backToHash() {
    setState(() {
      _verifying = false;
      _output.clear();
      _status = '';
      _error = null;
      _warning = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        children: [
          Expanded(
            child: buildAdaptiveSplit(
              initialRatio: 0.42,
              minSecondExtent: 380,
              first: EditorPane(
                label: 'Password',
                actions: [
                  ToolButton(label: 'Go', onPressed: _run),

                  SegmentedToggle(
                    options: const ['Hash', 'Verify'],
                    initialIndex: _verifying ? 1 : 0,
                    onChanged: _setMode,
                  ),
                ],
                controller: _password,
                onChanged: (_) => _run(),
                placeholder: 'Enter a password...',
              ),
              second: _buildPanel(context),
            ),
          ),
          if (_error != null || _warning != null || _status.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error ?? _warning ?? _status,
                  style: _error != null
                      ? errorToolTextStyle(context)
                      : _warning != null
                      ? TextStyle(color: context.appColors.warning)
                      : mutedToolTextStyle(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_verifying) _buildParams(context),
        if (_verifying) _buildVerifyInput(context),
        const SizedBox(height: 8),
        Expanded(
          child: EditorPane(
            label: _verifying ? 'Result' : 'Hash',
            actions: [
              ToolButton(label: 'Copy', onPressed: _copyOutput),
              if (_verifying)
                ToolButton(label: 'Back to hash', onPressed: _backToHash),
            ],
            controller: _output,
            readOnly: true,
            placeholder: _verifying
                ? 'Verification result...'
                : 'Generated hash...',
          ),
        ),
      ],
    );
  }

  Widget _buildParams(BuildContext context) {
    final algorithm = _algorithm;
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Algorithm'),
              const SizedBox(width: 12),
              Expanded(
                child: SmallDropdown(
                  items: PasswordHashAlgorithm.values
                      .map((a) => a.label)
                      .toList(),
                  initialValue: algorithm.label,
                  onChanged: _setAlgorithm,
                ),
              ),
            ],
          ),
          LabeledField(
            label: 'Salt (optional)',
            hintText: 'Generated randomly when empty',
            controller: _salt,
          ),
          if (algorithm.usesCost)
            LabeledField(label: 'Cost factor (4-31)', controller: _rounds),
          if (algorithm.usesScryptParams) ...[
            LabeledField(label: 'N (power of two)', controller: _scryptN),
            LabeledField(label: 'r (block size)', controller: _scryptR),
            LabeledField(label: 'p (parallelism)', controller: _scryptP),
          ],
          if (algorithm.usesIterations)
            LabeledField(
              label: algorithm.phcPrefix.startsWith('argon2')
                  ? 'Iterations (t)'
                  : 'Iterations',
              controller: _iterations,
            ),
          if (algorithm.usesMemory) ...[
            LabeledField(label: 'Memory (KiB)', controller: _memory),
            LabeledField(label: 'Parallelism (p)', controller: _lanes),
          ],
          if (_running)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Hashing...'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVerifyInput(BuildContext context) {
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Hash to check',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _verifyHash,
            onChanged: (_) => _run(),
            maxLines: 2,
            minLines: 1,
            style: TextStyle(
              color: context.appColors.editorText,
              fontFamily: 'Menlo',
              fontSize: 11.5,
            ),
            decoration: InputDecoration(
              hintText: 'Paste a bcrypt or PHC hash...',
              hintStyle: TextStyle(color: context.appColors.mutedText),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: context.appColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: context.appColors.border),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Algorithm is detected from the hash prefix.',
            style: mutedToolTextStyle(context, fontSize: 11),
          ),
          if (_running)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Verifying...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Widget buildPasswordHashing() {
  return const _PasswordHashingView();
}
