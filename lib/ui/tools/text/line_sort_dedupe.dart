/// Line sort/dedupe tool view.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/widgets.dart';
import '../../tool_sample_action.dart';
import '../common/editors.dart';

class _LineSortDedupeView extends StatefulWidget {
  const _LineSortDedupeView();

  @override
  State<_LineSortDedupeView> createState() => _LineSortDedupeViewState();
}

class _LineSortDedupeViewState extends State<_LineSortDedupeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _sort = 'A -> Z (Text)';
  String _dupes = 'With Duplicates';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final lines = _input.text.split(RegExp(r'\r?\n'));
    final cleaned = _dupes == 'With Duplicates'
        ? lines
        : lines.toSet().toList();
    final descending = _sort.startsWith('Z');
    int compare(String a, String b) =>
        descending ? b.compareTo(a) : a.compareTo(b);
    cleaned.sort(compare);
    _output.text = cleaned.join('\n');
    setState(() {});
  }

  void _setSample() {
    _input.text = '1\n11\n2\n22\n22\n33\n5.0\n2.5';
    _run();
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: buildSplitEditors(
        inputActions: [ToolButton(label: 'Go', onPressed: _run)],
        outputActions: [
          SmallDropdown(
            items: const ['A -> Z (Text)', 'Z -> A (Text)'],
            initialValue: _sort,
            onChanged: (value) {
              setState(() => _sort = value);
              _run();
            },
          ),
          SmallDropdown(
            items: const ['With Duplicates', 'Without Duplicates'],
            initialValue: _dupes,
            onChanged: (value) {
              setState(() => _dupes = value);
              _run();
            },
          ),
          ToolButton(label: 'Copy', onPressed: _copyOutput),
        ],
        inputController: _input,
        outputController: _output,
        inputPlaceholder: 'Line 1\nLine 2\nLine 2',
        outputPlaceholder: 'Line 1\nLine 2',
      ),
    );
  }
}

Widget buildLineSortDedupe() {
  return const _LineSortDedupeView();
}
