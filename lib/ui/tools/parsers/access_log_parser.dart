/// Apache/nginx access log parser tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';
import '../../../services/log_parser_service.dart';
import '../../tool_sample_action.dart';

class _AccessLogParserView extends StatefulWidget {
  const _AccessLogParserView();

  @override
  State<_AccessLogParserView> createState() => _AccessLogParserViewState();
}

class _AccessLogParserViewState extends State<_AccessLogParserView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  bool _showTable = true;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final outcome = parseAccessLog(_input.text);
    _output.text = _showTable
        ? renderLogTable(outcome)
        : renderLogSummary(outcome);
    setState(() {});
  }

  void _setSample() {
    setState(() {
      _input.text = const [
        '127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] '
            '"GET /apache_pb.gif HTTP/1.0" 200 2326 '
            '"http://example.com/start" "Mozilla/4.08 [en] (Win98; I ;Nav)"',
        '10.0.0.5 - - [08/Mar/2024:09:12:01 +0000] '
            '"POST /api/login HTTP/2.0" 401 0 "-" "curl/8.4.0"',
        '203.0.113.9 - - [08/Mar/2024:09:12:05 +0000] '
            '"GET /api/users?id=7 HTTP/1.1" 500 512 "-" "curl/8.4.0"',
        '{"time":"2024-03-08T09:12:09Z","remote_addr":"198.51.100.4",'
            '"status":200,"request_uri":"GET /health HTTP/1.1",'
            '"request_time":0.004}',
      ].join('\n');
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = parseAccessLog(_input.text);
    final summary = outcome.summary;
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        children: [
          Expanded(
            child: buildSplitEditors(
              inputActions: [
                ToolButton(label: 'Go', onPressed: _run),

                SegmentedToggle(
                  options: const ['Entries', 'Summary'],
                  initialIndex: _showTable ? 0 : 1,
                  onChanged: (index) {
                    setState(() => _showTable = index == 0);
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
              inputPlaceholder:
                  'Paste Apache common/combined or nginx log lines',
              outputPlaceholder: 'Parsed fields',
            ),
          ),
          if (summary.total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${summary.parsed} parsed, ${summary.unparsed} unrecognised, '
                  '${summary.errors['4xx']} client / ${summary.errors['5xx']} '
                  'server errors.',
                  style: mutedToolTextStyle(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget buildAccessLogParser() => const _AccessLogParserView();
