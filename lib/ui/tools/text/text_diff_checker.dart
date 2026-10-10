/// Text diff checker tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
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
      leftParts = left.split(RegExp(r'\s+'));
      rightParts = right.split(RegExp(r'\s+'));
    } else if (_mode == 'Lines') {
      leftParts = left.split('\n');
      rightParts = right.split('\n');
    } else {
      leftParts = left.split('');
      rightParts = right.split('');
    }
    final removed = leftParts
        .where((item) => !rightParts.contains(item))
        .toList();
    final added = rightParts
        .where((item) => !leftParts.contains(item))
        .toList();
    final buffer = StringBuffer();
    for (final item in removed) {
      buffer.writeln('- $item');
    }
    for (final item in added) {
      buffer.writeln('+ $item');
    }
    setState(() => _output.text = buffer.toString().trimRight());
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
            const SmallDropdown(
              items: ['Formatted Text', 'Plain Text'],
              initialValue: 'Formatted Text',
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
