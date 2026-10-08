/// RegExp tester tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

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

  Future<void> _pasteRegexClipboard() async {
    final text = await readClipboardText();
    setState(() => _regex.text = text);
    _run();
  }

  Future<void> _pasteTextClipboard() async {
    final text = await readClipboardText();
    setState(() => _text.text = text);
    _run();
  }

  void _setSample() {
    setState(() {
      _regex.text = r'([A-Z])\w+';
      _text.text =
          'DevUtils helps you with your tiny daily tasks. It works entirely offline.';
    });
    _run();
  }

  void _clearAll() {
    setState(() {
      _regex.clear();
      _text.clear();
      _output.clear();
      _matches = [];
      _error = null;
    });
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

    return ResizableSplit(
      horizontal: false,
      initialRatio: 0.66,
      minFirstExtent: 260,
      minSecondExtent: 220,
      first: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'RegExp:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(
                width: 220,
                child: InlineTextField(
                  hintText: r'([A-Z])\w+',
                  controller: _regex,
                  onChanged: (_) => _run(),
                ),
              ),
              ToolButton(label: 'Clipboard', onPressed: _pasteRegexClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearAll),
              const ToolIconButton(icon: Icons.settings),
              const SizedBox(width: 8),
              const Text(
                'Text:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              ToolButton(label: 'Clipboard', onPressed: _pasteTextClipboard),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: toolSurfaceDecoration(context),
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _text,
                maxLines: null,
                onChanged: (_) => _run(),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: TextStyle(color: context.appColors.editorText),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Output:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(
                width: 120,
                child: InlineTextField(
                  hintText: r'$0\n',
                  controller: _format,
                  onChanged: (_) => _run(),
                ),
              ),
              SizedBox(
                width: 200,
                child: InlineTextField(
                  hintText: 'Search matches...',
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EditorPane(
              label: '',
              actions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
              controller: _output,
              readOnly: true,
              placeholder: '',
            ),
          ),
        ],
      ),
      second: Column(
        children: [
          if (_error != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: errorToolTextStyle(context)),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              const Spacer(),
              const Icon(Icons.chevron_left, size: 16),
              const SizedBox(width: 8),
              Text('${_matches.length} matches'),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          const ToolButton(label: 'Cheat Sheet'),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: toolSurfaceDecoration(context),
              padding: const EdgeInsets.all(8),
              child: ListView.separated(
                itemCount: matches.length,
                separatorBuilder: (context, index) => const Divider(height: 8),
                itemBuilder: (context, index) {
                  final match = matches[index];
                  final value = match.group(0) ?? '';
                  return Text('"$value" (${match.start}, ${match.end})');
                },
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
