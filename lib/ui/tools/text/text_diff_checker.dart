/// Text diff checker tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/diff.dart';
import '../../app_colors.dart';
import '../../../ui/widgets.dart';
import '../../../services/text_diff_service.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _TextDiffView extends StatefulWidget {
  const _TextDiffView();

  @override
  State<_TextDiffView> createState() => _TextDiffViewState();
}

class _TextDiffViewState extends State<_TextDiffView> {
  final TextEditingController _left = TextEditingController();
  final TextEditingController _right = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _mode = 'Characters';
  String _outputMode = 'Formatted Text';

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final left = _left.text;
    final right = _right.text;
    List<String> leftParts;
    List<String> rightParts;
    if (_mode == 'Words') {
      leftParts = RegExp(r'\S+').allMatches(left).map((match) => match.group(0)!).toList();
      rightParts = RegExp(r'\S+').allMatches(right).map((match) => match.group(0)!).toList();
    } else if (_mode == 'Lines') {
      leftParts = left.isEmpty ? [] : left.split('\n');
      rightParts = right.isEmpty ? [] : right.split('\n');
    } else {
      leftParts = left.characters.toList();
      rightParts = right.characters.toList();
    }
    final buffer = StringBuffer();
    for (final change in sequenceChanges(leftParts, rightParts)) {
      buffer.writeln('${change.added ? '+' : '-'} ${change.value}');
    }
    // Remove the formatting newline, preserving whitespace in the changed token.
    setState(() => _output.text = buffer.toString().replaceFirst(RegExp(r'\n$'), ''));
  }

  void _swap() {
    final temp = _left.text;
    _left.text = _right.text;
    _right.text = temp;
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final inputComparison = buildAdaptiveSplit(
      first: EditorPane(
        label: 'Input 1',
        actions: [],
        controller: _left,
        onChanged: (_) => _run(),
      ),
      second: EditorPane(
        label: 'Input 2',
        actions: [ToolButton(label: 'Swap Inputs', onPressed: _swap)],
        controller: _right,
        onChanged: (_) => _run(),
      ),
    );

    final outputPane = Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Diff mode:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SegmentedToggle(
              options: const ['Characters', 'Words', 'Lines'],
              initialIndex: 0,
              onChanged: (index) {
                setState(
                  () => _mode = const ['Characters', 'Words', 'Lines'][index],
                );
                _run();
              },
            ),
            const SizedBox(width: 8),
            const Text(
              'Output:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SmallDropdown(
              items: const ['Formatted Text', 'Plain Text'],
              initialValue: _outputMode,
              onChanged: (value) => setState(() => _outputMode = value),
            ),
            const Icon(Icons.chevron_left, size: 16),
            Text(
              '${_output.text.split('\n').where((line) => line.isNotEmpty).length}',
            ),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: EditorPane(
            label: 'Differences',
            actions: [
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            controller: _output,
            readOnly: true,
            placeholder: 'Diff output...',
            highlightTheme: _outputMode == 'Plain Text'
                ? null
                : CodeHighlightTheme(
                    languages: {'diff': CodeHighlightThemeMode(mode: langDiff)},
                    theme: {
                      'root': TextStyle(color: context.appColors.editorText),
                      'addition': TextStyle(color: context.appColors.success),
                      'deletion': TextStyle(color: context.appColors.error),
                    },
                  ),
          ),
        ),
      ],
    );

    return ToolSampleAction(
      onPressed: () {
        setState(() => _left.text = 'Line one\nLine two');
        _run();
      },
      child: ResizableSplit(
        horizontal: false,
        initialRatio: 0.66,
        first: inputComparison,
        second: outputPane,
      ),
    );
  }
}

Widget buildTextDiffChecker() {
  return const _TextDiffView();
}
