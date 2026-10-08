/// Password and passphrase generator tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/password_generator_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

class _PasswordGeneratorView extends StatefulWidget {
  const _PasswordGeneratorView();

  @override
  State<_PasswordGeneratorView> createState() => _PasswordGeneratorViewState();
}

class _PasswordGeneratorViewState extends State<_PasswordGeneratorView> {
  final TextEditingController _length = TextEditingController(text: '20');
  final TextEditingController _words = TextEditingController(text: '6');
  final TextEditingController _separator = TextEditingController(text: '-');
  final TextEditingController _value = TextEditingController();

  PasswordStyle _style = PasswordStyle.random;
  bool _includeUpper = true;
  bool _includeDigits = true;
  bool _includeSymbols = false;
  bool _capitalizeWords = false;

  GeneratedSecret _secret = const GeneratedSecret(
    value: '',
    bitsOfEntropy: 0,
    summary: '',
    words: [],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  @override
  void dispose() {
    _length.dispose();
    _words.dispose();
    _separator.dispose();
    _value.dispose();
    super.dispose();
  }

  PasswordOptions get _options => PasswordOptions(
        style: _style,
        length: int.tryParse(_length.text.trim()) ?? 20,
        words: int.tryParse(_words.text.trim()) ?? 4,
        separator: _separator.text.isEmpty ? '-' : _separator.text,
        includeUpper: _includeUpper,
        includeDigits: _includeDigits,
        includeSymbols: _includeSymbols,
        capitalizeWords: _capitalizeWords,
      );

  void _generate() {
    final secret = generateSecret(_options);
    setState(() {
      _secret = secret;
      _value.text = secret.value;
    });
  }

  Future<void> _copy(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final secret = _secret;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResult(context, secret),
          const SizedBox(height: 12),
          Expanded(child: _buildControls(context)),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, GeneratedSecret secret) {
    final appColors = context.appColors;
    final weak = secret.bitsOfEntropy < 40;
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  secret.value.isEmpty ? 'Press Generate' : secret.value,
                  style: TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 14,
                    color: secret.value.isEmpty
                        ? appColors.mutedText
                        : appColors.editorText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ToolButton(label: 'Copy', onPressed: () => _copy(secret.value)),
              ToolButton(label: 'Regenerate', onPressed: _generate),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            secret.summary,
            style: mutedToolTextStyle(context, fontSize: 11.5),
          ),
          if (secret.bitsOfEntropy > 0) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 2,
              children: [
                Text(
                  'Online crack: ${estimateCrackTime(secret.bitsOfEntropy)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: weak ? appColors.warning : appColors.mutedText,
                  ),
                ),
                Text(
                  'Offline (fast hash): '
                  '${estimateOfflineCrackTime(secret.bitsOfEntropy)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: weak ? appColors.warning : appColors.mutedText,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final style = _style;
    return SingleChildScrollView(
      child: Container(
        decoration: toolSurfaceDecoration(context),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Style', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 10),
                Expanded(
                  child: SmallDropdown(
                    items: PasswordStyle.values
                        .map((s) => s.label)
                        .toList(),
                    initialValue: style.label,
                    onChanged: (value) {
                      final match =
                          PasswordStyle.values.where((s) => s.label == value);
                      if (match.isEmpty) return;
                      setState(() => _style = match.first);
                      _generate();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (style == PasswordStyle.random)
              Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: _NumberField(
                      label: 'Length',
                      controller: _length,
                      onChanged: (_) => _generate(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 10,
                    children: [
                      _Toggle(
                        label: 'A-Z',
                        value: _includeUpper,
                        onChanged: (v) {
                          setState(() => _includeUpper = v);
                          _generate();
                        },
                      ),
                      _Toggle(
                        label: '0-9',
                        value: _includeDigits,
                        onChanged: (v) {
                          setState(() => _includeDigits = v);
                          _generate();
                        },
                      ),
                      _Toggle(
                        label: 'Symbols',
                        value: _includeSymbols,
                        onChanged: (v) {
                          setState(() => _includeSymbols = v);
                          _generate();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            if (style == PasswordStyle.passphrase)
              Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: _NumberField(
                      label: 'Words',
                      controller: _words,
                      onChanged: (_) => _generate(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: _SeparatorField(
                      controller: _separator,
                      onChanged: (_) => _generate(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Toggle(
                    label: 'Capitalise',
                    value: _capitalizeWords,
                    onChanged: (v) {
                      setState(() => _capitalizeWords = v);
                      _generate();
                    },
                  ),
                ],
              ),
            if (style == PasswordStyle.pin)
              SizedBox(
                width: 200,
                child: _NumberField(
                  label: 'Digits',
                  controller: _length,
                  onChanged: (_) => _generate(),
                ),
              ),
            if (style == PasswordStyle.uuidToken)
              const Text(
                'A 128-bit random token in UUID format. No options.',
                style: TextStyle(fontSize: 11.5),
              ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      style: TextStyle(
        fontFamily: 'Menlo',
        fontSize: 12,
        color: appColors.editorText,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 11, color: appColors.mutedText),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: appColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: appColors.border),
        ),
      ),
    );
  }
}

class _SeparatorField extends StatelessWidget {
  const _SeparatorField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(
        fontFamily: 'Menlo',
        fontSize: 12,
        color: appColors.editorText,
      ),
      decoration: InputDecoration(
        labelText: 'Separator',
        labelStyle: TextStyle(fontSize: 11, color: appColors.mutedText),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: appColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: appColors.border),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (next) => onChanged(next ?? false),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(label, style: const TextStyle(fontSize: 11.5)),
      ],
    );
  }
}

Widget buildPasswordGenerator() {
  return const _PasswordGeneratorView();
}