/// Read-only CSV table inspector.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/csv_inspector_service.dart';
import '../../../ui/widgets.dart';
import '../../tool_sample_action.dart';
import '../common/editors.dart';
import '../common/shared.dart';

class _CsvInspectorView extends StatefulWidget {
  const _CsvInspectorView();
  @override
  State<_CsvInspectorView> createState() => _CsvInspectorViewState();
}

class _CsvInspectorViewState extends State<_CsvInspectorView> {
  final _input = TextEditingController();
  final _output = TextEditingController();
  final _filter = TextEditingController();
  String _filterColumn = '';
  String _sortColumn = '';
  bool _descending = false;
  CsvInspectResult _result = const CsvInspectResult();

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _filter.dispose();
    super.dispose();
  }

  void _run() {
    final columns = inspectCsv(_input.text).columns;
    if (!columns.contains(_filterColumn)) _filterColumn = '';
    if (!columns.contains(_sortColumn)) _sortColumn = '';
    final result = inspectCsv(
      _input.text,
      filterColumn: _filterColumn,
      filterText: _filter.text,
      sortColumn: _sortColumn,
      descending: _descending,
    );
    _output.text = result.output;
    setState(() => _result = result);
  }

  void _setSample() {
    _input.text =
        'name,language,score,note\n'
        'Alex,Dart,92,"Enjoys Flutter, too"\n'
        'Sam,Python,85,Builds scripts\n'
        'Riley,Dart,78,Learning widgets\n'
        'Jordan,JavaScript,88,Builds websites';
    _filter.clear();
    _filterColumn = '';
    _sortColumn = '';
    _descending = false;
    _run();
  }

  @override
  Widget build(BuildContext context) => ToolSampleAction(
    onPressed: _setSample,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ToolToolbar(
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: _filter,
                decoration: const InputDecoration(labelText: 'Filter contains'),
                onChanged: (_) => _run(),
              ),
            ),
            if (_result.columns.isNotEmpty) ...[
              const Text('In'),
              SmallDropdown(
                key: ValueKey(
                  'filter-$_filterColumn-${_result.columns.join('|')}',
                ),
                items: ['All columns', ..._result.columns],
                initialValue: _filterColumn.isEmpty
                    ? 'All columns'
                    : _filterColumn,
                onChanged: (value) {
                  _filterColumn = value == 'All columns' ? '' : value;
                  _run();
                },
              ),
              const Text('Sort'),
              SmallDropdown(
                key: ValueKey('sort-$_sortColumn-${_result.columns.join('|')}'),
                items: ['None', ..._result.columns],
                initialValue: _sortColumn.isEmpty ? 'None' : _sortColumn,
                onChanged: (value) {
                  _sortColumn = value == 'None' ? '' : value;
                  _run();
                },
              ),
              CompactCheck(
                label: 'Descending',
                value: _descending,
                onChanged: (value) {
                  _descending = value;
                  _run();
                },
              ),
            ],
            Text(
              _result.error ??
                  '${_result.matchedCount} of ${_result.rowCount} rows',
              style: _result.error == null
                  ? mutedToolTextStyle(context)
                  : errorToolTextStyle(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: buildSplitEditors(
            inputController: _input,
            outputController: _output,
            inputPlaceholder: 'CSV with header row',
            outputPlaceholder: 'Filtered CSV',
            inputActions: [ToolButton(label: 'Go', onPressed: _run)],
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
    ),
  );
}

Widget buildCsvInspector() => const _CsvInspectorView();
