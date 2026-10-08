/// JSON ↔ CSV converter tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/file_dialog_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _JsonStatusPill extends StatelessWidget {
  const _JsonStatusPill({required this.statusListenable});

  final ValueListenable<JsonToolStatus> statusListenable;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return ValueListenableBuilder<JsonToolStatus>(
      valueListenable: statusListenable,
      builder: (context, status, _) {
        if (!status.hasMessage) return const SizedBox.shrink();
        final hasError = status.error != null;
        return Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasError
                ? appColors.error.withAlpha(28)
                : appColors.success.withAlpha(24),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: hasError ? appColors.error : appColors.success,
            ),
          ),
          child: Text(
            status.error ?? status.summary ?? '',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasError ? appColors.error : appColors.success,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}

class _CsvToJsonView extends StatefulWidget {
  const _CsvToJsonView();

  @override
  State<_CsvToJsonView> createState() => _CsvToJsonViewState();
}

class _CsvToJsonViewState extends State<_CsvToJsonView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _indent = '2 spaces';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      final rows = _parseCsv(text);
      if (rows.isEmpty) {
        setState(() {
          _output.text = '[]';
          _error = null;
        });
        return;
      }
      final headers = rows.first;
      final data = <Map<String, String>>[];
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        final map = <String, String>{};
        for (var j = 0; j < headers.length; j++) {
          map[headers[j]] = j < row.length ? row[j] : '';
        }
        data.add(map);
      }
      final encoder = JsonEncoder.withIndent(indentFor(_indent));
      _output.text = encoder.convert(data);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() {
      _input.text = text;
    });
  }

  void _setSample() {
    const sample =
        'id,name,note\n1,DevUtils,"Sample row"\n2,Example,"Escaped ""string"""';
    setState(() {
      _input.text = sample;
    });
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
            ],
            outputActions: [
              SmallDropdown(
                items: const ['2 spaces', '4 spaces', 'Tabs'],
                initialValue: _indent,
                onChanged: (value) {
                  setState(() => _indent = value);
                  _run();
                },
              ),
              ToolButton(label: 'Copy', onPressed: _copyOutput),
            ],
            inputPlaceholder: 'id,name,note',
            outputPlaceholder: '[]',
            inputController: _input,
            outputController: _output,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!, style: errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  final row = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (inQuotes) {
      if (char == '"') {
        final next = i + 1 < input.length ? input[i + 1] : '';
        if (next == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(char);
      }
    } else {
      if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        row.add(buffer.toString());
        buffer.clear();
      } else if (char == '\n') {
        row.add(buffer.toString());
        buffer.clear();
        rows.add(List<String>.from(row));
        row.clear();
      } else if (char == '\r') {
        if (i + 1 < input.length && input[i + 1] == '\n') {
          i++;
        }
        row.add(buffer.toString());
        buffer.clear();
        rows.add(List<String>.from(row));
        row.clear();
      } else {
        buffer.write(char);
      }
    }
  }

  if (buffer.isNotEmpty || row.isNotEmpty) {
    row.add(buffer.toString());
    rows.add(List<String>.from(row));
  }

  return rows;
}

class _JsonToCsvView extends StatefulWidget {
  const _JsonToCsvView();

  @override
  State<_JsonToCsvView> createState() => _JsonToCsvViewState();
}

class _JsonToCsvViewState extends State<_JsonToCsvView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      final decoded = jsonDecode(text);
      final rows = _jsonToCsvRows(decoded);
      final buffer = StringBuffer();
      for (final row in rows) {
        buffer.writeln(row.map(_escapeCsv).join(','));
      }
      _output.text = buffer.toString().trimRight();
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    const sample =
        '{"data":[{"id":1,"name":"JSON Formatter","deep":{"nested":1,"value":2}}]}';
    setState(() => _input.text = sample);
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
            ],
            outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: '{"data":[{"id":1,"name":"JSON Formatter"}]}',
            outputPlaceholder: 'id,name',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!, style: errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

List<List<String>> _jsonToCsvRows(dynamic decoded) {
  dynamic data = decoded;
  if (decoded is Map && decoded['data'] is List) {
    data = decoded['data'];
  }
  if (data is Map) data = [data];
  if (data is! List) throw ArgumentError('Expected a JSON object or array.');
  final flattened = <Map<String, dynamic>>[];
  final headers = <String>{};
  for (final item in data) {
    if (item is Map) {
      final map = _flattenJson(item);
      flattened.add(map);
      headers.addAll(map.keys);
    } else {
      throw ArgumentError('Each row must be an object.');
    }
  }
  final headerList = headers.toList()..sort();
  final rows = <List<String>>[];
  rows.add(headerList);
  for (final item in flattened) {
    rows.add(headerList.map((key) => _csvCellValue(item[key])).toList());
  }
  return rows;
}

Map<String, dynamic> _flattenJson(
  Map<dynamic, dynamic> input, {
  String prefix = '',
}) {
  final result = <String, dynamic>{};
  input.forEach((key, value) {
    final fullKey = prefix.isEmpty ? '$key' : '$prefix.$key';
    if (value is Map) {
      result.addAll(_flattenJson(value, prefix: fullKey));
    } else {
      result[fullKey] = value;
    }
  });
  return result;
}

String _escapeCsv(String value) {
  if (value.contains('"')) {
    value = value.replaceAll('"', '""');
  }
  if (value.contains(',') || value.contains('\n') || value.contains('\r')) {
    return '"$value"';
  }
  return value;
}

String _csvCellValue(Object? value) {
  if (value == null) return '';
  if (value is String || value is num || value is bool) return '$value';
  return jsonEncode(value);
}

bool _looksLikeJsonInput(String value) {
  final trimmed = value.trimLeft();
  return trimmed.startsWith('{') || trimmed.startsWith('[');
}

bool _looksLikeCsvInput(String value) {
  final trimmed = value.trim();
  return trimmed.contains(',') ||
      trimmed.contains('\n') ||
      trimmed.contains('\r');
}

class _JsonCsvConverterView extends StatefulWidget {
  const _JsonCsvConverterView();

  @override
  State<_JsonCsvConverterView> createState() => _JsonCsvConverterViewState();
}

class _JsonCsvConverterViewState extends State<_JsonCsvConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  final ScrollController _inputScroll = ScrollController();
  final ScrollController _outputScroll = ScrollController();
  final ValueNotifier<JsonToolStatus> _status = ValueNotifier<JsonToolStatus>(
    JsonToolStatus.empty,
  );
  bool _csvToJson = true;
  bool _outputWrap = true;
  String _indent = '2 spaces';
  double _inputRatio = 0.5;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _output.dispose();
    _inputScroll.dispose();
    _outputScroll.dispose();
    _status.dispose();
    super.dispose();
  }

  void _scheduleRun() {
    // Debounce conversion while typing so large documents aren't re-parsed and
    // re-serialized on every keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _export() async {
    if (_output.text.isEmpty) return;
    final extension = _csvToJson ? 'json' : 'csv';
    final path = await FileDialogService.saveFile(
      suggestedName: 'export.$extension',
      allowedExtensions: [extension],
    );
    if (path == null) return;
    await File(path).writeAsString(_output.text);
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _output.text = '';
      _status.value = JsonToolStatus.empty;
      return;
    }
    try {
      final effectiveCsvToJson = _looksLikeJsonInput(text)
          ? false
          : (_looksLikeCsvInput(text) ? true : _csvToJson);
      if (effectiveCsvToJson != _csvToJson) {
        setState(() => _csvToJson = effectiveCsvToJson);
      }

      if (effectiveCsvToJson) {
        final rows = _parseCsv(text);
        if (rows.isEmpty) {
          _output.text = '[]';
        } else {
          final headers = rows.first;
          final data = <Map<String, String>>[];
          for (var i = 1; i < rows.length; i++) {
            final row = rows[i];
            final map = <String, String>{};
            for (var j = 0; j < headers.length; j++) {
              map[headers[j]] = j < row.length ? row[j] : '';
            }
            data.add(map);
          }
          final encoder = JsonEncoder.withIndent(indentFor(_indent));
          _output.text = encoder.convert(data);
        }
        _status.value = JsonToolStatus(
          summary: 'CSV → JSON · ${max(0, rows.length - 1)} rows',
        );
      } else {
        final decoded = jsonDecode(text);
        final rows = _jsonToCsvRows(decoded);
        final buffer = StringBuffer();
        for (final row in rows) {
          buffer.writeln(row.map(_escapeCsv).join(','));
        }
        _output.text = buffer.toString().trimRight();
        _status.value = JsonToolStatus(
          summary: 'JSON → CSV · ${max(0, rows.length - 1)} rows',
        );
      }
    } catch (e) {
      _output.clear();
      _status.value = JsonToolStatus(error: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return JsonSplitEditors(
      inputController: _input,
      outputController: _output,
      inputScrollController: _inputScroll,
      outputScrollController: _outputScroll,
      inputMarkedLines: const <int>{},
      inputRatio: _inputRatio,
      outputSoftWrap: _outputWrap,
      onInputRatioChanged: (value) => setState(() => _inputRatio = value),
      onInputChanged: (_) => _scheduleRun(),
      inputPlaceholder: _csvToJson ? 'id,name,note' : '{"data":[{"id":1}]}',
      outputPlaceholder: _csvToJson ? '[]' : 'id,name',
      inputActions: const [],
      outputActions: const [],
      showInputHeader: false,
      showOutputHeader: false,
      inputOverlay: _CsvJsonDirectionOverlay(
        csvToJson: _csvToJson,
        onChanged: (value) {
          setState(() => _csvToJson = value);
          _run();
        },
      ),
      outputOverlay: _JsonCsvOutputOverlay(
        csvToJson: _csvToJson,
        indent: _indent,
        wrap: _outputWrap,
        statusListenable: _status,
        onIndentChanged: (value) {
          setState(() => _indent = value);
          _run();
        },
        onWrapChanged: (value) => setState(() => _outputWrap = value),
        onExport: _export,
      ),
    );
  }
}

class _CsvJsonDirectionOverlay extends StatelessWidget {
  const _CsvJsonDirectionOverlay({
    required this.csvToJson,
    required this.onChanged,
  });

  final bool csvToJson;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return ToggleButtons(
      isSelected: [csvToJson, !csvToJson],
      onPressed: (index) => onChanged(index == 0),
      borderRadius: BorderRadius.circular(6),
      borderColor: appColors.border,
      selectedBorderColor: appColors.accent,
      fillColor: appColors.accentSoft,
      selectedColor: appColors.accent,
      color: appColors.editorText,
      constraints: const BoxConstraints(minHeight: 30, minWidth: 88),
      children: const [
        Text('CSV → JSON', style: TextStyle(fontSize: 12)),
        Text('JSON → CSV', style: TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _JsonCsvOutputOverlay extends StatelessWidget {
  const _JsonCsvOutputOverlay({
    required this.csvToJson,
    required this.indent,
    required this.wrap,
    required this.statusListenable,
    required this.onIndentChanged,
    required this.onWrapChanged,
    required this.onExport,
  });

  final bool csvToJson;
  final String indent;
  final bool wrap;
  final ValueListenable<JsonToolStatus> statusListenable;
  final ValueChanged<String> onIndentChanged;
  final ValueChanged<bool> onWrapChanged;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _JsonStatusPill(statusListenable: statusListenable)),
        const SizedBox(width: 8),
        SmallDropdown(
          items: const ['Wrap', 'No wrap'],
          initialValue: wrap ? 'Wrap' : 'No wrap',
          onChanged: (value) => onWrapChanged(value == 'Wrap'),
        ),
        if (csvToJson) ...[
          const SizedBox(width: 8),
          SmallDropdown(
            items: const ['2 spaces', '4 spaces', 'Tabs'],
            initialValue: indent,
            onChanged: onIndentChanged,
          ),
        ],
        const SizedBox(width: 8),
        ToolButton(
          label: csvToJson ? 'Export JSON' : 'Export CSV',
          icon: Icons.download,
          onPressed: onExport,
        ),
      ],
    );
  }
}

Widget buildJsonToCsv() {
  return const _JsonToCsvView();
}

Widget buildCsvToJson() {
  return const _CsvToJsonView();
}

Widget buildJsonCsvConverter() {
  return const _JsonCsvConverterView();
}
