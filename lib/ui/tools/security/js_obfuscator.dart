/// JavaScript/TypeScript obfuscator tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';
import '../../../services/js_obfuscator_service.dart';

const _sampleSource = r'''
const config = { apiKey: "sk-live-0123456789", retries: 3 };

async function loadProfile(userId) {
  const response = await fetch(`/api/users/${userId}?full=${deep}`);
  if (!response.ok) throw new Error("request failed");
  const profile = await response.json();
  return { ...profile, label: label(profile) };
}

function label(profile) {
  return `${profile.name} (${profile.age})`;
}

class Store {
  constructor(items) { this.items = items; }
  get first() { return this.items[0]; }
}

console.log("key:", config.apiKey);
''';

class _JsObfuscatorView extends StatefulWidget {
  const _JsObfuscatorView();

  @override
  State<_JsObfuscatorView> createState() => _JsObfuscatorViewState();
}

class _JsObfuscatorViewState extends State<_JsObfuscatorView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  ObfuscatorOptions _options = const ObfuscatorOptions();
  String? _report;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final result = obfuscateJs(_input.text, options: _options);
    _output.text = result.output;
    setState(() {
      _error = result.error;
      _report = result.ok ? result.describe() : null;
    });
  }

  void _setSample() {
    setState(() => _input.text = _sampleSource);
    _run();
  }

  void _clear() {
    setState(() {
      _input.clear();
      _output.clear();
      _report = null;
      _error = null;
    });
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() => _input.text = text);
    _run();
  }

  void _update(ObfuscatorOptions next) {
    setState(() => _options = next);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clear),
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
            inputPlaceholder: 'Paste JavaScript or TypeScript',
            outputPlaceholder: 'Obfuscated source',
          ),
        ),
        _buildOptions(),
      ],
    );
  }

  Widget _buildOptions() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              CompactCheck(
                label: 'Rename identifiers',
                value: _options.mangleIdentifiers,
                onChanged: (value) => _update(
                  _options.copy(mangleIdentifiers: value),
                ),
              ),
              CompactCheck(
                label: 'Hoist strings',
                value: _options.hoistStrings,
                onChanged: (value) => _update(
                  _options.copy(hoistStrings: value),
                ),
              ),
              CompactCheck(
                label: 'Inject dead code',
                value: _options.deadCodeInjection,
                onChanged: (value) => _update(
                  _options.copy(deadCodeInjection: value),
                ),
              ),
              CompactCheck(
                label: 'Self-defending',
                value: _options.selfDefending,
                onChanged: (value) => _update(
                  _options.copy(selfDefending: value),
                ),
              ),
              CompactCheck(
                label: 'Debug protection',
                value: _options.debugProtection,
                onChanged: (value) => _update(
                  _options.copy(debugProtection: value),
                ),
              ),
              CompactCheck(
                label: 'Disable console',
                value: _options.disableConsoleOutput,
                onChanged: (value) => _update(
                  _options.copy(disableConsoleOutput: value),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Text('Name style', style: mutedToolTextStyle(context)),
                const SizedBox(width: 8),
                // The three labels are long, so the toggle takes the remaining
                // width rather than overflowing the panel.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SegmentedToggle(
                        options:
                            ManglerStyle.values.map((s) => s.label).toList(),
                        initialIndex: _options.style.index,
                        onChanged: (index) => _update(
                          _options.copy(style: ManglerStyle.values[index]),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_report != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_report!, style: mutedToolTextStyle(context)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: errorToolTextStyle(context)),
            ),
        ],
      ),
    );
  }
}

Widget buildJsObfuscator() => const _JsObfuscatorView();
