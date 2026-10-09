/// URL query parameter editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/query_editor_service.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';

class _QueryEditorView extends StatefulWidget {
  const _QueryEditorView();

  @override
  State<_QueryEditorView> createState() => _QueryEditorViewState();
}

class _QueryEditorViewState extends State<_QueryEditorView> {
  final _input = TextEditingController();
  final _output = TextEditingController();
  final _key = TextEditingController();
  final _value = TextEditingController();
  QueryEdit _edit = QueryEdit.inspect;
  String _status = '';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  void _run() {
    final result = editQuery(
      _input.text,
      edit: _edit,
      key: _key.text,
      value: _value.text,
    );
    _output.text = result.output ?? '';
    setState(
      () => _status = result.error ?? '${result.fields.length} parameters',
    );
  }

  void _clear() {
    _input.clear();
    _output.clear();
    _key.clear();
    _value.clear();
    setState(() => _status = '');
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Action'),
          SmallDropdown(
            items: const ['Inspect', 'Add', 'Replace', 'Remove', 'Sort'],
            initialValue: const [
              'Inspect',
              'Add',
              'Replace',
              'Remove',
              'Sort',
            ][_edit.index],
            onChanged: (value) {
              setState(
                () => _edit =
                    QueryEdit.values[const [
                      'Inspect',
                      'Add',
                      'Replace',
                      'Remove',
                      'Sort',
                    ].indexOf(value)],
              );
              _run();
            },
          ),
          if (_edit == QueryEdit.add ||
              _edit == QueryEdit.replace ||
              _edit == QueryEdit.remove)
            SizedBox(
              width: 190,
              child: TextField(
                controller: _key,
                decoration: const InputDecoration(labelText: 'Parameter name'),
                onChanged: (_) => _run(),
              ),
            ),
          if (_edit == QueryEdit.add || _edit == QueryEdit.replace)
            SizedBox(
              width: 190,
              child: TextField(
                controller: _value,
                decoration: const InputDecoration(labelText: 'Value'),
                onChanged: (_) => _run(),
              ),
            ),
          if (_status.isNotEmpty)
            Text(_status, style: mutedToolTextStyle(context)),
        ],
      ),
      const SizedBox(height: 8),
      Expanded(
        child: buildSplitEditors(
          inputController: _input,
          outputController: _output,
          inputPlaceholder: 'URL or query string',
          outputPlaceholder: 'Edited URL or query',
          inputActions: [
            ToolButton(label: 'Go', onPressed: _run),
            ToolButton(label: 'Clear', onPressed: _clear),
          ],
          outputActions: [
            ToolButton(
              label: 'Copy',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _output.text)),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget buildQueryEditor() => const _QueryEditorView();
