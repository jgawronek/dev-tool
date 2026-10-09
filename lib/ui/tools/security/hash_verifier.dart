/// Text digest and HMAC verifier tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/hash_verifier_service.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';

class _HashVerifierView extends StatefulWidget {
  const _HashVerifierView();

  @override
  State<_HashVerifierView> createState() => _HashVerifierViewState();
}

class _HashVerifierViewState extends State<_HashVerifierView> {
  final _input = TextEditingController();
  final _output = TextEditingController();
  final _expected = TextEditingController();
  final _key = TextEditingController();
  VerifyAlgorithm _algorithm = VerifyAlgorithm.sha256;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _expected.dispose();
    _key.dispose();
    super.dispose();
  }

  void _run() {
    final result = verifyTextHash(
      text: _input.text,
      expected: _expected.text,
      key: _key.text,
      algorithm: _algorithm,
    );
    _output.text = [
      if (result.computed != null) 'Computed: ${result.computed}',
      if (result.error != null) result.error!,
      if (result.matches != null) result.matches! ? 'Match' : 'No match',
    ].join('\n');
    setState(() {});
  }

  void _clear() {
    _input.clear();
    _expected.clear();
    _key.clear();
    _output.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Algorithm'),
          SmallDropdown(
            items: VerifyAlgorithm.values.map((value) => value.label).toList(),
            initialValue: _algorithm.label,
            onChanged: (label) {
              setState(
                () => _algorithm = VerifyAlgorithm.values.firstWhere(
                  (value) => value.label == label,
                ),
              );
              _run();
            },
          ),
          if (_algorithm.keyed)
            SizedBox(
              width: 220,
              child: TextField(
                controller: _key,
                decoration: const InputDecoration(labelText: 'HMAC key'),
                onChanged: (_) => _run(),
              ),
            ),
          SizedBox(
            width: 310,
            child: TextField(
              controller: _expected,
              decoration: const InputDecoration(
                labelText: 'Expected hex digest',
              ),
              onChanged: (_) => _run(),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Expanded(
        child: buildSplitEditors(
          inputController: _input,
          outputController: _output,
          inputPlaceholder: 'Text to verify (UTF-8)',
          outputPlaceholder: 'Digest verification',
          inputActions: [
            ToolButton(label: 'Go', onPressed: _run),
            ToolButton(label: 'Clear', onPressed: _clear),
          ],
          outputActions: [
            ToolButton(
              label: 'Copy',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _output.text)),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget buildHashVerifier() => const _HashVerifierView();
