/// JSON to Code generator tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../services/file_dialog_service.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _JsonToCodeView extends StatefulWidget {
  const _JsonToCodeView();

  @override
  State<_JsonToCodeView> createState() => _JsonToCodeViewState();
}

class _JsonToCodeViewState extends State<_JsonToCodeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  late final String _dropTargetScope = identityHashCode(this).toRadixString(16);
  String _lang = 'Swift';
  bool _plainTypes = false;
  bool _initializers = true;
  bool _codingKeys = true;
  String? _sourceFileName;
  String? _error;

  String get _dropTargetId => 'json-to-code-source-$_dropTargetScope';

  @override
  void dispose() {
    FileDropService.unregisterTarget(_dropTargetId);
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: const ['json', 'txt'],
    );
    if (path == null || !mounted) return;
    await _loadFile(path);
  }

  Future<void> _loadFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw const FileSystemException('JSON file does not exist');
      }
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _sourceFileName = p.basename(path);
        _error = null;
        _input.text = text;
      });
      _run();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyFileReadError(error));
    }
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _output.clear();
      setState(() {});
      return;
    }
    try {
      final decoded = jsonDecode(text);
      _output.text = _generateCodeFromJson(
        _lang,
        decoded,
        _JsonCodeOptions(
          plainTypes: _plainTypes,
          initializers: _initializers,
          codingKeys: _codingKeys,
        ),
      );
      _error = null;
    } catch (e) {
      _output.text = 'Invalid JSON: $e';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final swiftSelected = _lang == 'Swift';
    final optionsPanel = ToolPanel(
      title: 'Options',
      expand: false,
      child: Container(
        padding: const EdgeInsets.all(12),

        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (swiftSelected) ...[
                CheckboxListTile(
                  value: _plainTypes,
                  onChanged: (value) {
                    setState(() => _plainTypes = value ?? false);
                    _run();
                  },
                  title: const Text('Plain types only (no Codable)'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                CheckboxListTile(
                  value: _initializers,
                  onChanged: (value) {
                    setState(() => _initializers = value ?? false);
                    _run();
                  },
                  title: const Text('Generate memberwise initializers'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                CheckboxListTile(
                  value: _codingKeys,
                  onChanged: _plainTypes
                      ? null
                      : (value) {
                          setState(() => _codingKeys = value ?? false);
                          _run();
                        },
                  title: const Text('Explicit CodingKeys'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 8),
                ToolButton(
                  label: 'Reset to Defaults',
                  onPressed: () {
                    setState(() {
                      _plainTypes = false;
                      _initializers = true;
                      _codingKeys = true;
                    });
                    _run();
                  },
                ),
              ] else
                Text(
                  'No options for $_lang output.',
                  style: mutedToolTextStyle(context, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final editors = buildAdaptiveSplit(
          first: FileDropTargetRegion(
            targetId: _dropTargetId,
            onDropped: (paths) {
              if (paths.isNotEmpty) unawaited(_loadFile(paths.first));
            },
            child: EditorPane(
              label: 'Input',
              actions: [
                const SmallDropdown(items: ['JSON'], initialValue: 'JSON'),
              ],
              controller: _input,
              onChanged: (_) {
                _sourceFileName = null;
                _run();
              },
              placeholder: 'Drop a .json file here or enter your text...',
              enableFileDrop: false,
              overlay: SourceFileControls(
                onPickFile: _pickFile,
                fileName: _sourceFileName,
                tooltip: 'Choose JSON file',
              ),
            ),
          ),
          second: EditorPane(
            label: 'Output',
            actions: [
              SmallDropdown(
                items: const ['Swift', 'TypeScript', 'Kotlin'],
                initialValue: _lang,
                onChanged: (value) {
                  setState(() => _lang = value);
                  _run();
                },
              ),
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            controller: _output,
            readOnly: true,
            placeholder: '- Right click -> Save to file...',
          ),
        );
        final options = SingleChildScrollView(child: optionsPanel);
        if (wide) {
          return ResizableSplit(
            horizontal: true,
            initialRatio: 0.76,
            minSecondExtent: 260,
            first: editors,
            second: options,
          );
        }
        return ResizableSplit(
          horizontal: false,
          initialRatio: 0.72,
          minSecondExtent: 220,
          first: editors,
          second: options,
        );
      },
    );

    if (_error == null) {
      return ToolSampleAction(
        onPressed: () {
          setState(() {
            _sourceFileName = null;
            _input.text = '{"name":"DevUtils"}';
          });
          _run();
        },
        child: body,
      );
    }
    return ToolSampleAction(
      onPressed: () {
        setState(() {
          _sourceFileName = null;
          _input.text = '{"name":"DevUtils"}';
        });
        _run();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error!, style: errorToolTextStyle(context)),
          const SizedBox(height: 8),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _JsonCodeOptions {
  const _JsonCodeOptions({
    this.plainTypes = false,
    this.initializers = true,
    this.codingKeys = true,
  });

  final bool plainTypes;
  final bool initializers;
  final bool codingKeys;
}

class _JsonIrType {
  _JsonIrType._(this.kind, {this.scalar, this.objectName, this.element});

  factory _JsonIrType.scalar(String scalar) =>
      _JsonIrType._('scalar', scalar: scalar);
  factory _JsonIrType.object(String name) =>
      _JsonIrType._('object', objectName: name);
  factory _JsonIrType.list(_JsonIrType element) =>
      _JsonIrType._('list', element: element);
  factory _JsonIrType.any() => _JsonIrType._('any');

  final String kind;
  final String? scalar;
  final String? objectName;
  final _JsonIrType? element;
}

class _JsonIrField {
  _JsonIrField(this.jsonKey, this.type, this.optional);
  final String jsonKey;
  final _JsonIrType type;
  final bool optional;
}

class _JsonIrObject {
  _JsonIrObject(this.name);
  final String name;
  final List<_JsonIrField> fields = [];
}

class _JsonCodeModel {
  final List<_JsonIrObject> objects = [];
  final Set<String> _names = {};
  bool usedLooseType = false;

  String reserveName(String base) {
    final root = base.isEmpty ? 'Root' : base;
    if (_names.add(root)) return root;
    var i = 2;
    while (!_names.add('$root$i')) {
      i++;
    }
    return '$root$i';
  }
}

String _generateCodeFromJson(
  String lang,
  Object? root,
  _JsonCodeOptions options,
) {
  final model = _JsonCodeModel();
  final rootType = _buildJsonIr([root], 'Root', model);
  if (model.objects.isEmpty) {
    return '// Top-level JSON is not an object.\n'
        '// Inferred type: ${_jsonTypeRef(lang, rootType)}';
  }

  String body;
  switch (lang) {
    case 'TypeScript':
      body = _emitTypeScript(model);
      break;
    case 'Kotlin':
      body = _emitKotlin(model);
      break;
    case 'Swift':
    default:
      body = _emitSwift(model, options);
      break;
  }

  final prefix = StringBuffer();
  if (model.usedLooseType) {
    prefix.writeln(
      '// Note: some fields were null/empty/mixed and were typed loosely.',
    );
  }
  if (rootType.kind == 'list') {
    final inner = _jsonTypeRef(lang, rootType.element!);
    final alias = switch (lang) {
      'TypeScript' => 'export type Root = $inner[];',
      'Kotlin' => 'typealias Root = List<$inner>',
      _ => 'typealias Root = [$inner]',
    };
    prefix.writeln(alias);
    prefix.writeln();
  }
  return '${prefix.toString()}$body'.trimRight();
}

_JsonIrType _buildJsonIr(
  List<Object?> values,
  String nameHint,
  _JsonCodeModel model,
) {
  final nonNull = values.where((v) => v != null).toList();
  if (nonNull.isEmpty) {
    model.usedLooseType = true;
    return _JsonIrType.any();
  }
  if (nonNull.every((v) => v is Map)) {
    return _buildJsonObjectIr(nonNull.cast<Map>(), nameHint, model);
  }
  if (nonNull.every((v) => v is List)) {
    final merged = <Object?>[];
    for (final list in nonNull) {
      merged.addAll(list as List);
    }
    return _JsonIrType.list(
      _buildJsonIr(merged, _singularName(nameHint), model),
    );
  }
  return _scalarJsonIr(nonNull, model);
}

_JsonIrType _buildJsonObjectIr(
  List<Map> maps,
  String nameHint,
  _JsonCodeModel model,
) {
  final object = _JsonIrObject(model.reserveName(_pascalCaseIdent(nameHint)));
  model.objects.add(object);
  final keys = <String>[];
  for (final map in maps) {
    for (final key in map.keys) {
      final keyString = key.toString();
      if (!keys.contains(keyString)) keys.add(keyString);
    }
  }
  for (final key in keys) {
    final present = maps.where((m) => m.containsKey(key)).toList();
    final values = present.map((m) => m[key]).toList();
    final optional =
        present.length != maps.length || values.any((v) => v == null);
    final fieldType = _buildJsonIr(values, key, model);
    object.fields.add(_JsonIrField(key, fieldType, optional));
  }
  return _JsonIrType.object(object.name);
}

_JsonIrType _scalarJsonIr(List<Object?> values, _JsonCodeModel model) {
  var allBool = true, allInt = true, allNum = true, allString = true;
  for (final value in values) {
    if (value is! bool) allBool = false;
    if (value is! int) allInt = false;
    if (value is! num) allNum = false;
    if (value is! String) allString = false;
  }
  if (allBool) return _JsonIrType.scalar('Bool');
  if (allInt) return _JsonIrType.scalar('Int');
  if (allNum) return _JsonIrType.scalar('Double');
  if (allString) return _JsonIrType.scalar('String');
  model.usedLooseType = true;
  return _JsonIrType.any();
}

String _jsonTypeRef(String lang, _JsonIrType type) {
  switch (lang) {
    case 'TypeScript':
      switch (type.kind) {
        case 'scalar':
          return const {
            'String': 'string',
            'Int': 'number',
            'Double': 'number',
            'Bool': 'boolean',
          }[type.scalar]!;
        case 'object':
          return type.objectName!;
        case 'list':
          return '${_jsonTypeRef(lang, type.element!)}[]';
        default:
          return 'any';
      }
    case 'Kotlin':
      switch (type.kind) {
        case 'scalar':
          return const {
            'String': 'String',
            'Int': 'Int',
            'Double': 'Double',
            'Bool': 'Boolean',
          }[type.scalar]!;
        case 'object':
          return type.objectName!;
        case 'list':
          return 'List<${_jsonTypeRef(lang, type.element!)}>';
        default:
          return 'Any';
      }
    case 'Swift':
    default:
      switch (type.kind) {
        case 'scalar':
          return type.scalar!;
        case 'object':
          return type.objectName!;
        case 'list':
          return '[${_jsonTypeRef(lang, type.element!)}]';
        default:
          return 'String';
      }
  }
}

String _emitSwift(_JsonCodeModel model, _JsonCodeOptions options) {
  final buffer = StringBuffer();
  for (var i = 0; i < model.objects.length; i++) {
    final object = model.objects[i];
    if (i > 0) buffer.writeln();
    final conformance = options.plainTypes ? '' : ': Codable';
    buffer.writeln('struct ${object.name}$conformance {');
    for (final field in object.fields) {
      final name = _camelCaseIdent(field.jsonKey);
      final type = _jsonTypeRef('Swift', field.type);
      buffer.writeln('    let $name: $type${field.optional ? '?' : ''}');
    }
    final needsKeys =
        !options.plainTypes &&
        options.codingKeys &&
        object.fields.any((f) => _camelCaseIdent(f.jsonKey) != f.jsonKey);
    if (needsKeys) {
      buffer.writeln();
      buffer.writeln('    enum CodingKeys: String, CodingKey {');
      for (final field in object.fields) {
        final name = _camelCaseIdent(field.jsonKey);
        if (name == field.jsonKey) {
          buffer.writeln('        case $name');
        } else {
          buffer.writeln('        case $name = "${field.jsonKey}"');
        }
      }
      buffer.writeln('    }');
    }
    if (options.initializers && object.fields.isNotEmpty) {
      buffer.writeln();
      final params = object.fields
          .map((f) {
            final name = _camelCaseIdent(f.jsonKey);
            final type =
                _jsonTypeRef('Swift', f.type) + (f.optional ? '?' : '');
            return '$name: $type';
          })
          .join(', ');
      buffer.writeln('    init($params) {');
      for (final field in object.fields) {
        final name = _camelCaseIdent(field.jsonKey);
        buffer.writeln('        self.$name = $name');
      }
      buffer.writeln('    }');
    }
    buffer.writeln('}');
  }
  return buffer.toString();
}

String _emitTypeScript(_JsonCodeModel model) {
  final buffer = StringBuffer();
  for (var i = 0; i < model.objects.length; i++) {
    final object = model.objects[i];
    if (i > 0) buffer.writeln();
    buffer.writeln('export interface ${object.name} {');
    for (final field in object.fields) {
      final key = _isValidIdent(field.jsonKey)
          ? field.jsonKey
          : "'${field.jsonKey}'";
      final type = _jsonTypeRef('TypeScript', field.type);
      buffer.writeln('  $key${field.optional ? '?' : ''}: $type;');
    }
    buffer.writeln('}');
  }
  return buffer.toString();
}

String _emitKotlin(_JsonCodeModel model) {
  final buffer = StringBuffer();
  var usedSerializedName = false;
  final body = StringBuffer();
  for (var i = 0; i < model.objects.length; i++) {
    final object = model.objects[i];
    if (i > 0) body.writeln();
    body.writeln('data class ${object.name}(');
    for (var j = 0; j < object.fields.length; j++) {
      final field = object.fields[j];
      final name = _camelCaseIdent(field.jsonKey);
      final type = _jsonTypeRef('Kotlin', field.type);
      final annotation = name != field.jsonKey
          ? '@SerializedName("${field.jsonKey}") '
          : '';
      if (annotation.isNotEmpty) usedSerializedName = true;
      final suffix = field.optional ? '? = null' : '';
      final comma = j == object.fields.length - 1 ? '' : ',';
      body.writeln('    ${annotation}val $name: $type$suffix$comma');
    }
    body.writeln(')');
  }
  if (usedSerializedName) {
    buffer.writeln('import com.google.gson.annotations.SerializedName');
    buffer.writeln();
  }
  buffer.write(body.toString());
  return buffer.toString();
}

String _camelCaseIdent(String key) {
  final parts = key
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'field';
  final head = parts.first;
  final buffer = StringBuffer(head[0].toLowerCase() + head.substring(1));
  for (final part in parts.skip(1)) {
    buffer.write(part[0].toUpperCase() + part.substring(1));
  }
  var result = buffer.toString();
  if (RegExp(r'^[0-9]').hasMatch(result)) result = 'n$result';
  return result;
}

String _pascalCaseIdent(String key) {
  final camel = _camelCaseIdent(key);
  return camel[0].toUpperCase() + camel.substring(1);
}

String _singularName(String name) {
  if (name.length > 1 && name.endsWith('s') && !name.endsWith('ss')) {
    return name.substring(0, name.length - 1);
  }
  return name;
}

bool _isValidIdent(String value) =>
    RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(value);

Widget buildJsonToCode() {
  return const _JsonToCodeView();
}
