/// Date/time difference calculator.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/date_difference_service.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

class _DateDifferenceView extends StatefulWidget {
  const _DateDifferenceView();
  @override
  State<_DateDifferenceView> createState() => _DateDifferenceViewState();
}

class _DateDifferenceViewState extends State<_DateDifferenceView> {
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _output = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final result = dateDifference(_start.text, _end.text);
    _output.text = result.report ?? '';
    setState(() => _error = result.error);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ToolToolbar(
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _start,
              decoration: const InputDecoration(
                labelText: 'Start (ISO 8601 + zone)',
                hintText: '2024-03-08T09:00:00Z',
              ),
              onChanged: (_) => _run(),
            ),
          ),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _end,
              decoration: const InputDecoration(
                labelText: 'End (ISO 8601 + zone)',
                hintText: '2024-03-09T10:30:00+01:00',
              ),
              onChanged: (_) => _run(),
            ),
          ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, style: errorToolTextStyle(context)),
        ),
      const SizedBox(height: 8),
      Expanded(
        child: EditorPane(
          label: 'Difference',
          actions: [
            ToolButton(
              label: 'Copy',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _output.text)),
            ),
          ],
          controller: _output,
          readOnly: true,
          placeholder: 'Elapsed time and UTC instants',
        ),
      ),
    ],
  );
}

Widget buildDateDifference() => const _DateDifferenceView();
