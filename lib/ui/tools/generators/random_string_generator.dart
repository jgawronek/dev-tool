/// Random string generator tool view.
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/password_generator_service.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _RandomStringGeneratorView extends StatefulWidget {
  const _RandomStringGeneratorView();

  @override
  State<_RandomStringGeneratorView> createState() =>
      _RandomStringGeneratorViewState();
}

class _RandomStringGeneratorViewState
    extends State<_RandomStringGeneratorView> {
  final TextEditingController _seed = TextEditingController();
  final TextEditingController _upper = TextEditingController(text: '18');
  final TextEditingController _lower = TextEditingController(text: '18');
  final TextEditingController _symbols = TextEditingController(text: '2');
  final TextEditingController _digits = TextEditingController(text: '8');
  final TextEditingController _words = TextEditingController(text: '0');
  final TextEditingController _output = TextEditingController();
  final _separator = TextEditingController();
  final _groupSize = TextEditingController(text: '0');
  final _custom = TextEditingController();
  String? _error;
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
    _separator.dispose();
    _groupSize.dispose();
    _custom.dispose();
    _output.dispose();
    super.dispose();
  }

  void _generate() {
    try {
      int count(TextEditingController field, String name, int maximum) {
        final value = int.tryParse(field.text);
        if (value == null || value < 0 || value > maximum) {
          throw FormatException('$name must be a number from 0 to $maximum.');
        }
        return value;
      }

      final counts = [
        count(_upper, 'Uppercase count', 4096),
        count(_lower, 'Lowercase count', 4096),
        count(_symbols, 'Symbol count', 4096),
        count(_digits, 'Digit count', 4096),
      ];
      final wordCount = count(_words, 'Word count', 100);
      final groupSize = count(_groupSize, 'Group size', 4096);
      final length = counts.reduce((a, b) => a + b);
      if (length > 4096 || length + wordCount == 0) {
        throw const FormatException(
          'Choose at least one character or word, with no more than 4096 characters.',
        );
      }
      final seed = _seed.text.trim();
      final seedValue = int.tryParse(seed);
      if (seed.isNotEmpty && seedValue == null) {
        throw const FormatException(
          'Seed must be a whole number, or leave it empty.',
        );
      }
      final rand = seedValue == null ? Random.secure() : Random(seedValue);
      const alphabets = [
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        'abcdefghijklmnopqrstuvwxyz',
        '!@#\$%^&*',
        '0123456789',
      ];
      final custom = _custom.text.runes.toList();
      final totalCount = int.parse(_count.substring(1));
      final lines = <String>[];
      for (var i = 0; i < totalCount; i++) {
        final chars = <int>[];
        for (var category = 0; category < counts.length; category++) {
          final alphabet = custom.isEmpty
              ? alphabets[category].runes.toList()
              : custom;
          for (var j = 0; j < counts[category]; j++) {
            chars.add(alphabet[rand.nextInt(alphabet.length)]);
          }
        }
        chars.shuffle(rand);
        final separator = _separator.text;
        final groups = <String>[];
        if (chars.isNotEmpty) {
          if (groupSize > 0) {
            for (var j = 0; j < chars.length; j += groupSize) {
              groups.add(
                String.fromCharCodes(
                  chars.sublist(j, min(j + groupSize, chars.length)),
                ),
              );
            }
          } else {
            groups.add(String.fromCharCodes(chars));
          }
        }
        for (var j = 0; j < wordCount; j++) {
          groups.add(
            generateSecret(
              const PasswordOptions(style: PasswordStyle.passphrase, words: 1),
              random: rand,
            ).value,
          );
        }
        lines.add(
          groups.join(separator.isEmpty && wordCount > 0 ? ' ' : separator),
        );
      }
      setState(() {
        _output.text = lines.join('\n');
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _output.clear();
        _error = error.message;
      });
    }
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
      _words.text = '0';
      _custom.clear();
      _groupSize.text = '0';
    });
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _generate,
      child: buildAdaptiveSplit(
        initialRatio: 0.62,
        minFirstExtent: 360,
        minSecondExtent: 320,
        first: ToolPanel(
          title: 'Options',
          child: SingleChildScrollView(
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
                    ],
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Seed (optional)',
                    controller: _seed,
                    hintText: 'Empty = random',
                  ),
                  LabeledField(
                    label: 'Uppercased Characters',
                    controller: _upper,
                  ),
                  LabeledField(
                    label: 'Lowercased Characters',
                    controller: _lower,
                  ),
                  LabeledField(label: 'Symbols', controller: _symbols),
                  LabeledField(label: 'Digits', controller: _digits),
                  LabeledField(label: 'Words', controller: _words),
                  LabeledField(label: 'Separator', controller: _separator),
                  LabeledField(
                    label: 'Separating Group Size',
                    controller: _groupSize,
                  ),
                  LabeledField(
                    label: 'Custom Character Set',
                    controller: _custom,
                  ),
                ],
              ),
            ),
          ),
        ),
        second: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ToolButton(label: 'Generate', onPressed: _generate),
                const Spacer(),
                SmallDropdown(
                  items: const ['x10', 'x20'],
                  initialValue: _count,
                  onChanged: (value) {
                    setState(() => _count = value);
                    _generate();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Text(_error!, style: errorToolTextStyle(context)),
            Expanded(
              child: EditorPane(
                label: 'Generated strings',
                actions: const [],
                controller: _output,
                readOnly: true,
                placeholder: 'Generated strings...',
                copyAction: _copyOutput,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget buildRandomStringGenerator() {
  return const _RandomStringGeneratorView();
}
