/// RegExp tester tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _RegExpTesterView extends StatefulWidget {
  const _RegExpTesterView();

  @override
  State<_RegExpTesterView> createState() => _RegExpTesterViewState();
}

class _RegExpTesterViewState extends State<_RegExpTesterView> {
  final TextEditingController _regex = TextEditingController();
  final TextEditingController _text = TextEditingController();
  final TextEditingController _format = TextEditingController(text: r'$0\n');
  final TextEditingController _search = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;
  List<RegExpMatch> _matches = [];

  @override
  void dispose() {
    _regex.dispose();
    _text.dispose();
    _format.dispose();
    _search.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    try {
      final regExp = RegExp(_regex.text);
      _matches = regExp.allMatches(_text.text).toList();
      _output.text = _formatOutput(_matches, _format.text);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _formatOutput(List<RegExpMatch> matches, String format) {
    final formatted = format.replaceAll(r'\n', '\n');
    final buffer = StringBuffer();
    for (final match in matches) {
      var line = formatted;
      for (var i = 0; i <= match.groupCount; i++) {
        line = line.replaceAll('\$$i', match.group(i) ?? '');
      }
      buffer.write(line);
    }
    return buffer.toString();
  }

  void _setSample() {
    setState(() {
      _regex.text = r'([A-Z])\w+';
      _text.text =
          'DevUtils helps you with your tiny daily tasks. It works entirely offline.';
    });
    _run();
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  List<RegExpMatch> _filteredMatches() {
    final query = _search.text.toLowerCase();
    if (query.isEmpty) return _matches;
    return _matches.where((match) {
      final text = match.group(0) ?? '';
      return text.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _filteredMatches();

    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToolToolbar(
            children: [
              const Text('Expression', style: TextStyle(fontSize: 12)),
              SizedBox(
                width: 260,
                child: InlineTextField(
                  height: 32,
                  hintText: r'([A-Z])\w+',
                  controller: _regex,
                  onChanged: (_) => _run(),
                ),
              ),

              const Text('Output format', style: TextStyle(fontSize: 12)),
              SizedBox(
                width: 120,
                child: InlineTextField(
                  height: 32,
                  hintText: r'$0\n',
                  controller: _format,
                  onChanged: (_) => _run(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: errorToolTextStyle(context)),
            ),
          Expanded(
            child: buildAdaptiveSplit(
              first: EditorPane(
                label: 'Text',
                actions: [],
                controller: _text,
                onChanged: (_) => _run(),
                placeholder: 'Enter text to match...',
              ),
              second: Column(
                children: [
                  Expanded(
                    child: ToolPanel(
                      title: 'Matches (${_matches.length})',
                      actions: [
                        SizedBox(
                          width: 170,
                          child: InlineTextField(
                            height: 32,
                            hintText: 'Search matches...',
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                      child: matches.isEmpty
                          ? Center(
                              child: Text(
                                'No matches',
                                style: mutedToolTextStyle(context),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(14),
                              itemCount: matches.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 16),
                              itemBuilder: (context, index) {
                                final match = matches[index];
                                return SelectableText(
                                  '"${match.group(0) ?? ''}" (${match.start}, ${match.end})',
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: EditorPane(
                      label: 'Formatted matches',
                      actions: [
                        ToolButton(label: 'Copy', onPressed: _copyOutput),
                      ],
                      controller: _output,
                      readOnly: true,
                      placeholder: 'Formatted matches will appear here',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildRegExpTester() {
  return const _RegExpTesterView();
}
