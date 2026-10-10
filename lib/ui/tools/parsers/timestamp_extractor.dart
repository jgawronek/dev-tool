/// Timestamp extractor tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';
import '../../../services/timestamp_service.dart';
import '../../tool_sample_action.dart';

class _TimestampExtractorView extends StatefulWidget {
  const _TimestampExtractorView();

  @override
  State<_TimestampExtractorView> createState() =>
      _TimestampExtractorViewState();
}

class _TimestampExtractorViewState extends State<_TimestampExtractorView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  TimestampFormat? _format;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final outcome = extractTimestamps(_input.text, format: _format);
    _output.text = outcome.hits.isEmpty
        ? (outcome.error ?? 'No timestamps found.')
        : renderTimestampReport(outcome.hits);
    setState(() {});
  }

  void _setSample() {
    setState(() {
      _input.text = const [
        'Deployment finished at 2026-03-08T09:12:01Z.',
        'Request logged 08/Mar/2024:09:12:05 +0000 by user admin.',
        'syslog line: Mar  8 09:12:09 host sshd[1234]: accepted publickey',
        'Epoch marker 1700000000 and 1700000000123',
        'Article published Mon, 09 Mar 2026 14:03:22 +0100',
      ].join('\n');
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = extractTimestamps(_input.text, format: _format);
    final hits = outcome.hits;
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        children: [
          Expanded(
            child: buildSplitEditors(
              inputActions: [
                ToolButton(label: 'Go', onPressed: _run),

                SegmentedToggle(
                  options: const [
                    'All',
                    'ISO',
                    'Apache',
                    'nginx',
                    'Syslog',
                    'Epoch',
                  ],
                  initialIndex: _format == null ? 0 : _format!.index + 1,
                  onChanged: (index) {
                    setState(() {
                      _format = index == 0
                          ? null
                          : TimestampFormat.values[index - 1];
                    });
                    _run();
                  },
                ),
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
              inputPlaceholder: 'Paste text containing timestamps',
              outputPlaceholder: 'Detected timestamps',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hits.isEmpty
                    ? 'No timestamps detected.'
                    : '${hits.length} timestamp(s) detected'
                          '${_format == null ? '' : ' as ${_format!.label}'}.',
                style: mutedToolTextStyle(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildTimestampExtractor() => const _TimestampExtractorView();
