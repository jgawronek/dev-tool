/// Random string generator tool view.
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';

class _RandomStringGeneratorView extends StatefulWidget {
  const _RandomStringGeneratorView();

  @override
  State<_RandomStringGeneratorView> createState() =>
      _RandomStringGeneratorViewState();
}

class _RandomStringGeneratorViewState
    extends State<_RandomStringGeneratorView> {
  final TextEditingController _seed = TextEditingController(
    text: '904731371168665084',
  );
  final TextEditingController _upper = TextEditingController(text: '18');
  final TextEditingController _lower = TextEditingController(text: '18');
  final TextEditingController _symbols = TextEditingController(text: '2');
  final TextEditingController _digits = TextEditingController(text: '8');
  final TextEditingController _words = TextEditingController(text: '0');
  final TextEditingController _output = TextEditingController();
  String _preset = 'Password';
  String _count = 'x10';

  @override
  void dispose() {
    _seed.dispose();
    _upper.dispose();
    _lower.dispose();
    _symbols.dispose();
    _digits.dispose();
    _words.dispose();
    _output.dispose();
    super.dispose();
  }

  void _generate() {
    final rand = Random();
    final uppers = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final lowers = 'abcdefghijklmnopqrstuvwxyz';
    final symbols = '!@#\$%^&*';
    final digits = '0123456789';
    final upCount = int.tryParse(_upper.text) ?? 0;
    final lowCount = int.tryParse(_lower.text) ?? 0;
    final symCount = int.tryParse(_symbols.text) ?? 0;
    final digCount = int.tryParse(_digits.text) ?? 0;
    final totalCount = (int.tryParse(_count.replaceAll('x', '')) ?? 10);
    final lines = <String>[];
    for (var i = 0; i < totalCount; i++) {
      final buffer = StringBuffer();
      for (var j = 0; j < upCount; j++) {
        buffer.write(uppers[rand.nextInt(uppers.length)]);
      }
      for (var j = 0; j < lowCount; j++) {
        buffer.write(lowers[rand.nextInt(lowers.length)]);
      }
      for (var j = 0; j < symCount; j++) {
        buffer.write(symbols[rand.nextInt(symbols.length)]);
      }
      for (var j = 0; j < digCount; j++) {
        buffer.write(digits[rand.nextInt(digits.length)]);
      }
      lines.add(buffer.toString());
    }
    _output.text = lines.join('\n');
    setState(() {});
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _applyPreset(String preset) {
    final values = switch (preset) {
      'API key' => ('0', '32', '0', '16'),
      'PIN' => ('0', '0', '0', '6'),
      'Token' => ('12', '24', '0', '12'),
      'Slug' => ('0', '24', '0', '4'),
      _ => ('4', '14', '4', '6'),
    };
    setState(() {
      _preset = preset;
      _upper.text = values.$1;
      _lower.text = values.$2;
      _symbols.text = values.$3;
      _digits.text = values.$4;
    });
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    return ResizableSplit(
      horizontal: true,
      initialRatio: 0.62,
      minFirstExtent: 360,
      minSecondExtent: 320,
      first: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Presets:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SmallDropdown(
                    items: const [
                      'Password',
                      'API key',
                      'PIN',
                      'Token',
                      'Slug',
                    ],
                    initialValue: _preset,
                    onChanged: _applyPreset,
                  ),
                  ToolButton(label: 'Sample', onPressed: _generate),
                ],
              ),
              const SizedBox(height: 12),
              LabeledField(label: 'Seed', controller: _seed),
              LabeledField(label: 'Uppercased Characters', controller: _upper),
              LabeledField(label: 'Lowercased Characters', controller: _lower),
              LabeledField(label: 'Symbols', controller: _symbols),
              LabeledField(label: 'Digits', controller: _digits),
              LabeledField(label: 'Words', controller: _words),
              const LabeledField(label: 'Separator'),
              const LabeledField(label: 'Separating Group Size'),
              const LabeledField(label: 'Custom Character Set'),
            ],
          ),
        ),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Checkbox(value: true, onChanged: null),
              const Text('Colors'),
              const Spacer(),
              SmallDropdown(
                items: const ['x10', 'x20'],
                initialValue: _count,
                onChanged: (value) => setState(() => _count = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EditorPane(
              label: '',
              actions: const [],
              controller: _output,
              readOnly: true,
              placeholder: 'Generated strings...',
              copyAction: _copyOutput,
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildRandomStringGenerator() {
  return const _RandomStringGeneratorView();
}
