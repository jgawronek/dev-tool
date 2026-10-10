/// String case converter tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _StringCaseConverterView extends StatefulWidget {
  const _StringCaseConverterView();

  @override
  State<_StringCaseConverterView> createState() =>
      _StringCaseConverterViewState();
}

class _StringCaseConverterViewState extends State<_StringCaseConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _mode = 'camelCase';
  static const _caseModes = [
    'camelCase',
    'PascalCase',
    'snake_case',
    'CONSTANT_CASE',
    'kebab-case',
    'Title Case',
    'Sentence case',
    'lowercase',
    'UPPERCASE',
  ];

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final lines = _input.text.split('\n');
    final converted = lines.map(_convert).join('\n');
    _output.text = converted;
    setState(() {});
  }

  String _convert(String input) {
    final words = _caseWords(input);
    if (words.isEmpty) return '';
    final lowerWords = words.map((word) => word.toLowerCase()).toList();
    switch (_mode) {
      case 'PascalCase':
        return lowerWords.map(_capitalizeWord).join();
      case 'snake_case':
        return lowerWords.join('_');
      case 'CONSTANT_CASE':
        return lowerWords.join('_').toUpperCase();
      case 'kebab-case':
        return lowerWords.join('-');
      case 'Title Case':
        return lowerWords.map(_capitalizeWord).join(' ');
      case 'Sentence case':
        return _capitalizeWord(lowerWords.join(' '));
      case 'lowercase':
        return lowerWords.join(' ');
      case 'UPPERCASE':
        return lowerWords.join(' ').toUpperCase();
      case 'camelCase':
      default:
        final first = lowerWords.first;
        final rest = lowerWords.skip(1).map(_capitalizeWord);
        return ([first, ...rest]).join();
    }
  }

  List<String> _caseWords(String input) {
    final spaced = input
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAll(RegExp(r'[_\-.\/]+'), ' ');
    return spaced
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
  }

  String _capitalizeWord(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: () {
        setState(() => _input.text = 'request URL decoder ID');
        _run();
      },
      child: buildSplitEditors(
        inputActions: [],
        outputActions: [
          SmallDropdown(
            items: _caseModes,
            initialValue: _mode,
            onChanged: (value) {
              setState(() => _mode = value);
              _run();
            },
          ),
          ToolButton(
            label: 'Copy',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _output.text)),
          ),
        ],
        inputController: _input,
        outputController: _output,
        onInputChanged: (_) => _run(),
      ),
    );
  }
}

Widget buildStringCaseConverter() {
  return const _StringCaseConverterView();
}
