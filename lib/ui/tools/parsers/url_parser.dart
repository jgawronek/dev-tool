/// URL parser tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _UrlParserView extends StatefulWidget {
  const _UrlParserView();

  @override
  State<_UrlParserView> createState() => _UrlParserViewState();
}

class _UrlParserViewState extends State<_UrlParserView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _queryJson = TextEditingController();
  String _protocol = '';
  String _host = '';
  String _path = '';
  String _file = '';
  String _query = '';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _queryJson.dispose();
    super.dispose();
  }

  void _parse() {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _protocol = '';
        _host = '';
        _path = '';
        _file = '';
        _query = '';
        _queryJson.clear();
        _error = null;
      });
      return;
    }
    try {
      final uri = Uri.parse(raw);
      _protocol = uri.scheme;
      _host = uri.host;
      _path = uri.path;
      _file = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      _query = uri.query;
      final queryMap = uri.queryParameters;
      _queryJson.text = const JsonEncoder.withIndent('  ').convert(queryMap);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() => _input.text = text);
    _parse();
  }

  void _setSample() {
    const sample =
        'https://www.google.com/search?q=sample+long+query&src=devutils';
    setState(() => _input.text = sample);
    _parse();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _queryJson.clear();
      _error = null;
    });
  }

  Future<void> _copyQuery() async {
    await Clipboard.setData(ClipboardData(text: _queryJson.text));
  }

  @override
  Widget build(BuildContext context) {
    return ResizableSplit(
      horizontal: false,
      initialRatio: 0.36,
      minFirstExtent: 180,
      minSecondExtent: 320,
      first: EditorPane(
        label: 'Input',
        actions: [
          ToolButton(label: 'Go', onPressed: _parse),
          ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
          ToolButton(label: 'Sample', onPressed: _setSample),
          ToolButton(label: 'Clear', onPressed: _clearInput),
          const ToolIconButton(icon: Icons.settings),
        ],
        controller: _input,
        onChanged: (_) => _parse(),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Field'),
          Container(
            decoration: toolSurfaceDecoration(context),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Protocol: $_protocol'),
                Text('Host: $_host'),
                Text('Path: $_path'),
                Text('File name: $_file'),
                Text('Query: $_query'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: EditorPane(
              label: 'Query string',
              actions: [ToolButton(label: 'Copy', onPressed: _copyQuery)],
              controller: _queryJson,
              readOnly: true,
              placeholder: '{ }',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: errorToolTextStyle(context)),
          ],
        ],
      ),
    );
  }
}

Widget buildUrlParser() {
  return const _UrlParserView();
}
