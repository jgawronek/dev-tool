/// JS to TS converter tool view.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../services/file_dialog_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _JsToTsConverterView extends StatefulWidget {
  const _JsToTsConverterView();

  @override
  State<_JsToTsConverterView> createState() => _JsToTsConverterViewState();
}

class _JsToTsConverterViewState extends State<_JsToTsConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();

  bool _tsToJs = false;
  bool _addClassFields = true;
  bool _useJsDoc = true;
  bool _rewriteCommonJs = true;
  bool _addAnyFallbacks = true;
  String? _sourceFileName;
  String? _error;
  _JsToTsConversionResult _lastResult = const _JsToTsConversionResult(
    code: '',
    notes: [],
  );

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _convert() {
    try {
      final result = _tsToJs
          ? _convertTypeScriptToJavaScript(_input.text)
          : _convertJavaScriptToTypeScript(
              _input.text,
              addClassFields: _addClassFields,
              useJsDoc: _useJsDoc,
              rewriteCommonJs: _rewriteCommonJs,
              addAnyFallbacks: _addAnyFallbacks,
            );
      setState(() {
        _error = null;
        _lastResult = result;
        _output.text = result.code;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
        _lastResult = const _JsToTsConversionResult(code: '', notes: []);
        _output.clear();
      });
    }
  }

  void _setDirection(bool tsToJs) {
    if (tsToJs == _tsToJs) return;
    setState(() {
      _tsToJs = tsToJs;
      _sourceFileName = null;
      _error = null;
    });
    _convert();
  }

  Future<void> _pickSourceFile() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: _tsToJs
          ? const ['ts', 'tsx', 'mts', 'cts']
          : const ['js', 'jsx', 'mjs', 'cjs'],
    );
    if (path == null || !mounted) return;
    await _loadSourceFile(path);
  }

  Future<void> _loadSourceFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw const FileSystemException('Source file does not exist');
      }
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _sourceFileName = p.basename(path);
        _error = null;
        _input.text = text;
      });
      _convert();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyFileReadError(error));
    }
  }

  void _setExample() {
    _input.text = _tsToJs
        ? '''
import type { Request, Response } from 'express';

interface User {
  name: string;
  createdAt: Date;
}

enum Role {
  Admin,
  Member,
}

function greet(name: string, count: number = 1): string {
  return name.repeat(count);
}

class UserCard {
  private name: string;
  readonly createdAt: Date = new Date();

  constructor(name: string) {
    this.name = name;
  }
}

const role = Role.Admin as Role;'''
        : '''
const express = require('express');

/**
 * @param {string} name
 * @param {number} count
 * @returns {string}
 */
function greet(name, count) {
  return name.repeat(count);
}

greet('DevUtils');

class UserCard {
  constructor(name) {
    this.name = name;
    this.createdAt = new Date();
  }
}

module.exports = { greet, UserCard };''';
    setState(() {
      _sourceFileName = null;
      _error = null;
    });
    _convert();
  }

  void _clear() {
    setState(() {
      _sourceFileName = null;
      _error = null;
      _lastResult = const _JsToTsConversionResult(code: '', notes: []);
      _input.clear();
      _output.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _lastResult.notes.isEmpty
        ? (_tsToJs
              ? 'Paste TypeScript to strip types into plain JavaScript.'
              : 'Paste JavaScript to generate TypeScript migration output.')
        : _lastResult.notes.join('  •  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(_error!, style: errorToolTextStyle(context)),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: buildSplitEditors(
            horizontal: true,
            inputPlaceholder: _tsToJs
                ? 'Choose a .ts/.tsx file or paste TypeScript...'
                : 'Choose a .js/.jsx file or paste JavaScript...',
            outputPlaceholder: _tsToJs
                ? 'JavaScript output...'
                : 'TypeScript output...',
            inputController: _input,
            outputController: _output,
            onInputChanged: (_) {
              _sourceFileName = null;
              _convert();
            },
            inputActions: [
              ToolButton(label: 'Sample', onPressed: _setExample),
              ToolButton(label: 'Clear', onPressed: _clear),
            ],
            outputActions: const [],
            showInputHeader: false,
            showOutputHeader: false,
            inputOverlay: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _JsToTsDirectionToggle(
                  tsToJs: _tsToJs,
                  onChanged: _setDirection,
                ),
                const SizedBox(width: 6),
                SourceFileControls(
                  onPickFile: _pickSourceFile,
                  fileName: _sourceFileName,
                  tooltip: _tsToJs
                      ? 'Choose TypeScript file'
                      : 'Choose JavaScript file',
                ),
              ],
            ),
            outputOverlay: _tsToJs
                ? null
                : _JsToTsOptionsOverlay(
                    addClassFields: _addClassFields,
                    useJsDoc: _useJsDoc,
                    rewriteCommonJs: _rewriteCommonJs,
                    addAnyFallbacks: _addAnyFallbacks,
                    onChanged:
                        ({
                          bool? addClassFields,
                          bool? useJsDoc,
                          bool? rewriteCommonJs,
                          bool? addAnyFallbacks,
                        }) {
                          setState(() {
                            _addClassFields = addClassFields ?? _addClassFields;
                            _useJsDoc = useJsDoc ?? _useJsDoc;
                            _rewriteCommonJs =
                                rewriteCommonJs ?? _rewriteCommonJs;
                            _addAnyFallbacks =
                                addAnyFallbacks ?? _addAnyFallbacks;
                          });
                          _convert();
                        },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(summary, style: mutedToolTextStyle(context, fontSize: 12)),
      ],
    );
  }
}

class _JsToTsDirectionToggle extends StatelessWidget {
  const _JsToTsDirectionToggle({required this.tsToJs, required this.onChanged});

  final bool tsToJs;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appColors.panelElevated.withAlpha(236),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _JsToTsDirectionChip(
              label: 'JS → TS',
              selected: !tsToJs,
              onTap: () => onChanged(false),
            ),
            const SizedBox(width: 2),
            _JsToTsDirectionChip(
              label: 'TS → JS',
              selected: tsToJs,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _JsToTsDirectionChip extends StatelessWidget {
  const _JsToTsDirectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? appColors.accent.withAlpha(48)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? appColors.accent : appColors.mutedText,
            ),
          ),
        ),
      ),
    );
  }
}

typedef _JsToTsOptionsChanged =
    void Function({
      bool? addClassFields,
      bool? useJsDoc,
      bool? rewriteCommonJs,
      bool? addAnyFallbacks,
    });

class _JsToTsOptionsOverlay extends StatelessWidget {
  const _JsToTsOptionsOverlay({
    required this.addClassFields,
    required this.useJsDoc,
    required this.rewriteCommonJs,
    required this.addAnyFallbacks,
    required this.onChanged,
  });

  final bool addClassFields;
  final bool useJsDoc;
  final bool rewriteCommonJs;
  final bool addAnyFallbacks;
  final _JsToTsOptionsChanged onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appColors.panelElevated.withAlpha(236),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CompactCheck(
                label: 'class fields',
                value: addClassFields,
                onChanged: (value) => onChanged(addClassFields: value),
              ),
              CompactCheck(
                label: 'JSDoc',
                value: useJsDoc,
                onChanged: (value) => onChanged(useJsDoc: value),
              ),
              CompactCheck(
                label: 'CommonJS',
                value: rewriteCommonJs,
                onChanged: (value) => onChanged(rewriteCommonJs: value),
              ),
              CompactCheck(
                label: ': any',
                value: addAnyFallbacks,
                onChanged: (value) => onChanged(addAnyFallbacks: value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
String convertJavaScriptToTypeScriptForPreview(String input) {
  return _convertJavaScriptToTypeScript(input).code;
}

class _JsToTsConversionResult {
  const _JsToTsConversionResult({required this.code, required this.notes});

  final String code;
  final List<String> notes;
}

class _JsDocInfo {
  const _JsDocInfo({required this.params, this.returnType});

  final Map<String, String> params;
  final String? returnType;
}

class _JsClassInfo {
  const _JsClassInfo({
    required this.name,
    required this.openBraceIndex,
    required this.closeBraceIndex,
    required this.properties,
    this.extendsName,
  });

  final String name;
  final String? extendsName;
  final int openBraceIndex;
  final int closeBraceIndex;
  final Set<String> properties;
}

_JsToTsConversionResult _convertJavaScriptToTypeScript(
  String input, {
  bool addClassFields = true,
  bool useJsDoc = true,
  bool rewriteCommonJs = true,
  bool addAnyFallbacks = true,
}) {
  var output = input.replaceAll('\r\n', '\n').trim();
  if (output.isEmpty) {
    return const _JsToTsConversionResult(code: '', notes: []);
  }

  final notes = <String>[];
  final optionalParams = _findOptionalFunctionParameters(output);

  if (useJsDoc) {
    final annotated = _applyJsDocTypes(
      output,
      optionalParams,
      addAnyFallbacks: addAnyFallbacks,
    );
    output = annotated.$1;
    if (annotated.$2 > 0) {
      notes.add('${annotated.$2} function signature(s) annotated');
    }
  } else if (addAnyFallbacks || optionalParams.isNotEmpty) {
    final annotated = _applyAnyFallbacks(output, optionalParams);
    output = annotated.$1;
    if (annotated.$2 > 0) {
      notes.add('${annotated.$2} function signature(s) normalized');
    }
  }

  if (addClassFields) {
    final withFields = _addClassPropertyDeclarations(output);
    output = withFields.$1;
    if (withFields.$2 > 0) {
      notes.add('${withFields.$2} class field declaration(s) added');
    }
  }

  if (rewriteCommonJs) {
    final rewritten = _rewriteCommonJsModuleSyntax(output);
    output = rewritten.$1;
    if (rewritten.$2 > 0) {
      notes.add('${rewritten.$2} CommonJS statement(s) rewritten');
    }
  }

  if (optionalParams.isNotEmpty) {
    notes.add('under-supplied call sites marked with optional parameters');
  }

  return _JsToTsConversionResult(code: output.trim(), notes: notes);
}

@visibleForTesting
String convertTypeScriptToJavaScriptForPreview(String input) {
  return _convertTypeScriptToJavaScript(input).code;
}

/// Best-effort TypeScript → JavaScript transpile by stripping type syntax.
/// This is a heuristic (regex-based) strip, not a full `tsc` compile, so the
/// returned notes flag that complex generics/overloads should be reviewed.
_JsToTsConversionResult _convertTypeScriptToJavaScript(String input) {
  var output = input.replaceAll('\r\n', '\n');
  if (output.trim().isEmpty) {
    return const _JsToTsConversionResult(code: '', notes: []);
  }

  final notes = <String>[];

  // Type-only imports/exports: `import type … ;`, `export type { … } …;`.
  var typeImports = 0;
  output = output.replaceAllMapped(
    RegExp(r'^[ \t]*(?:import|export)\s+type\s+[^\n]*\n?', multiLine: true),
    (_) {
      typeImports++;
      return '';
    },
  );
  // Inline `type` modifier inside named imports/exports: `{ type A, B }`.
  output = output.replaceAll(RegExp(r'([{,]\s*)type\s+(?=[A-Za-z_$])'), r'$1');

  // `interface … { … }` blocks.
  final interfaces = _removeBalancedBlocks(
    output,
    RegExp(
      r'(?:export\s+)?(?:declare\s+)?interface\s+[A-Za-z_$][\w$]*\s*'
      r'(?:<[^>]*>)?\s*(?:extends\s+[^{]+)?\{',
    ),
  );
  output = interfaces.$1;

  // `enum … { … }` → frozen plain object.
  final enums = _convertTsEnums(output);
  output = enums.$1;

  // `type X = …;` aliases.
  final aliases = _removeTsTypeAliases(output);
  output = aliases.$1;

  // `declare …` statements.
  output = output.replaceAll(
    RegExp(r'^[ \t]*declare\s+[^\n]*\n?', multiLine: true),
    '',
  );

  // Class member modifiers and `implements` clauses.
  output = output.replaceAll(
    RegExp(r'\b(?:public|private|protected|readonly|abstract|override)\s+'),
    '',
  );
  output = output.replaceAll(RegExp(r'\s+implements\s+[^{]+(?=\{)'), ' ');

  // `as Type` / `as const` / `satisfies Type` expression casts.
  output = output.replaceAll(
    RegExp(r'\s+as\s+(?:const\b|[A-Za-z_$][\w$.]*(?:<[^>]*>)?(?:\[\])*)'),
    '',
  );
  output = output.replaceAll(
    RegExp(r'\s+satisfies\s+[A-Za-z_$][\w$.]*(?:<[^>]*>)?'),
    '',
  );

  // Generic type parameters on function/class declarations and call sites.
  output = output.replaceAllMapped(
    RegExp(
      r'\b(function\s+[A-Za-z_$][\w$]*|class\s+[A-Za-z_$][\w$]*)\s*<[^>]*>',
    ),
    (m) => m.group(1)!,
  );
  output = output.replaceAllMapped(
    RegExp(r'([A-Za-z_$][\w$]*)\s*<[^<>;()]*>(?=\s*\()'),
    (m) => m.group(1)!,
  );

  // Definite-assignment assertion: `name!: T` → `name: T`.
  output = output.replaceAll(RegExp(r'([A-Za-z_$][\w$]*)!(?=\s*:)'), r'$1');

  // Function/method return types: `): T {` / `): T =>` / `): T;`.
  output = output.replaceAllMapped(
    RegExp(r'\)\s*:\s*[A-Za-z_$\{\[][^=;{}\n]*?(\s*(?:=>|\{|;))'),
    (m) => ')${m.group(1)}',
  );

  // Variable declarations: `const x: T = …` / `let y: T;`.
  output = output.replaceAllMapped(
    RegExp(r'\b(const|let|var)\s+([A-Za-z_$][\w$]*)\s*:\s*[^=;\n]+?(\s*[=;])'),
    (m) => '${m.group(1)} ${m.group(2)}${m.group(3)}',
  );

  // Parameter annotations (anchored on `(`/`,`), optional then required.
  output = output.replaceAllMapped(
    RegExp(
      r'([(,]\s*(?:\.\.\.)?[A-Za-z_$][\w$]*)\s*\?\s*:\s*[^,)=]+?(?=\s*[,)=])',
    ),
    (m) => m.group(1)!,
  );
  output = output.replaceAllMapped(
    RegExp(r'([(,]\s*(?:\.\.\.)?[A-Za-z_$][\w$]*)\s*:\s*[^,)=]+?(?=\s*[,)=])'),
    (m) => m.group(1)!,
  );

  // Class field declarations: `name?: T;` / `name: T = …`.
  output = output.replaceAllMapped(
    RegExp(
      r'^([ \t]*)([A-Za-z_$][\w$]*)\s*\??\s*:\s*[^=;\n]+?(\s*[=;])',
      multiLine: true,
    ),
    (m) => '${m.group(1)}${m.group(2)}${m.group(3)}',
  );

  // Non-null assertions: `foo!.bar`, `value!)`.
  output = output.replaceAll(RegExp(r'!(?=\s*[.;,)\]}])'), '');

  output = output.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  output = output.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

  if (typeImports > 0) {
    notes.add('$typeImports type-only import(s) removed');
  }
  if (interfaces.$2 > 0) {
    notes.add('${interfaces.$2} interface(s) removed');
  }
  if (enums.$2 > 0) {
    notes.add('${enums.$2} enum(s) converted to objects');
  }
  if (aliases.$2 > 0) {
    notes.add('${aliases.$2} type alias(es) removed');
  }
  notes.add('type annotations stripped (heuristic — review complex generics)');

  return _JsToTsConversionResult(code: output, notes: notes);
}

int _matchClosingBrace(String source, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < source.length; i++) {
    final char = source[i];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

(String, int) _removeBalancedBlocks(String source, RegExp header) {
  var src = source;
  var count = 0;
  while (true) {
    final match = header.firstMatch(src);
    if (match == null) break;
    final braceStart = src.indexOf('{', match.start);
    if (braceStart == -1) break;
    final end = _matchClosingBrace(src, braceStart);
    if (end == -1) break;
    var after = end + 1;
    if (after < src.length && src[after] == ';') after++;
    src = src.substring(0, match.start) + src.substring(after);
    count++;
  }
  return (src, count);
}

(String, int) _convertTsEnums(String source) {
  final header = RegExp(
    r'(?:export\s+)?(?:const\s+)?enum\s+([A-Za-z_$][\w$]*)\s*\{',
  );
  var src = source;
  var count = 0;
  while (true) {
    final match = header.firstMatch(src);
    if (match == null) break;
    final name = match.group(1)!;
    final braceStart = src.indexOf('{', match.start);
    final end = _matchClosingBrace(src, braceStart);
    if (end == -1) break;
    final body = src.substring(braceStart + 1, end);
    final members = <String>[];
    var auto = 0;
    for (final rawPart in body.split(',')) {
      final part = rawPart.trim();
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq == -1) {
        members.add('  $part: $auto');
        auto++;
      } else {
        final key = part.substring(0, eq).trim();
        final value = part.substring(eq + 1).trim();
        members.add('  $key: $value');
        final asInt = int.tryParse(value);
        if (asInt != null) auto = asInt + 1;
      }
    }
    final keepExport = src
        .substring(match.start, braceStart)
        .contains('export');
    final prefix = keepExport ? 'export const' : 'const';
    final replacement =
        '$prefix $name = Object.freeze({\n${members.join(',\n')}\n});';
    var after = end + 1;
    if (after < src.length && src[after] == ';') after++;
    src = src.substring(0, match.start) + replacement + src.substring(after);
    count++;
  }
  return (src, count);
}

(String, int) _removeTsTypeAliases(String source) {
  final header = RegExp(
    r'(?:export\s+)?type\s+[A-Za-z_$][\w$]*\s*(?:<[^=]*?>)?\s*=',
  );
  var src = source;
  var count = 0;
  while (true) {
    final match = header.firstMatch(src);
    if (match == null) break;
    var depth = 0;
    var lastMeaningful = '=';
    var endIdx = -1;
    for (var i = match.end; i < src.length; i++) {
      final char = src[i];
      if (char == '<' || char == '{' || char == '(' || char == '[') {
        depth++;
      } else if (char == '>' || char == '}' || char == ')' || char == ']') {
        if (depth > 0) depth--;
      } else if (char == ';' && depth == 0) {
        endIdx = i + 1;
        break;
      } else if (char == '\n' && depth == 0) {
        var j = i + 1;
        while (j < src.length &&
            (src[j] == ' ' || src[j] == '\t' || src[j] == '\n')) {
          j++;
        }
        final next = j < src.length ? src[j] : '';
        const continuations = {'|', '&', '=', ',', '(', '[', '.'};
        if (continuations.contains(lastMeaningful) ||
            next == '|' ||
            next == '&') {
          continue;
        }
        endIdx = i;
        break;
      }
      if (char != ' ' && char != '\t') lastMeaningful = char;
    }
    if (endIdx == -1) endIdx = src.length;
    src = src.substring(0, match.start) + src.substring(endIdx);
    count++;
  }
  return (src, count);
}

Map<String, Set<String>> _findOptionalFunctionParameters(String source) {
  final definitions = <String, List<String>>{};
  final functionPattern = RegExp(
    r'\bfunction\s+([A-Za-z_$][\w$]*)\s*\(([^)]*)\)',
  );
  final arrowPattern = RegExp(
    r'\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\(([^)]*)\)\s*=>',
  );

  for (final match in functionPattern.allMatches(source)) {
    definitions[match.group(1)!] = _parameterNames(match.group(2)!);
  }
  for (final match in arrowPattern.allMatches(source)) {
    definitions[match.group(1)!] = _parameterNames(match.group(2)!);
  }

  final optional = <String, Set<String>>{};
  for (final entry in definitions.entries) {
    final name = entry.key;
    final params = entry.value;
    if (params.isEmpty) continue;
    var minimumCallCount = params.length;
    var sawUnderSuppliedCall = false;
    final callPattern = RegExp('\\b${RegExp.escape(name)}\\s*\\(([^)]*)\\)');
    for (final match in callPattern.allMatches(source)) {
      if (_isFunctionDefinitionAt(source, match.start, name)) continue;
      final argCount = _countTopLevelArguments(match.group(1)!);
      if (argCount < params.length) {
        sawUnderSuppliedCall = true;
        minimumCallCount = min(minimumCallCount, argCount);
      }
    }
    if (sawUnderSuppliedCall) {
      optional[name] = params.skip(minimumCallCount).toSet();
    }
  }
  return optional;
}

bool _isFunctionDefinitionAt(String source, int start, String name) {
  final before = source.substring(max(0, start - 32), start);
  return RegExp('function\\s+$name\\s*\$').hasMatch(before) ||
      RegExp(
        '(const|let|var)\\s+$name\\s*=\\s*(async\\s*)?\$',
      ).hasMatch(before);
}

List<String> _parameterNames(String rawParams) {
  return _splitTopLevel(rawParams, ',')
      .map((param) {
        var text = param.trim();
        if (text.startsWith('...')) text = text.substring(3).trim();
        final equalsIndex = text.indexOf('=');
        if (equalsIndex >= 0) text = text.substring(0, equalsIndex).trim();
        final match = RegExp(r'^([A-Za-z_$][\w$]*)').firstMatch(text);
        return match?.group(1) ?? '';
      })
      .where((name) => name.isNotEmpty)
      .toList();
}

int _countTopLevelArguments(String rawArgs) {
  final trimmed = rawArgs.trim();
  if (trimmed.isEmpty) return 0;
  return _splitTopLevel(trimmed, ',').length;
}

(String, int) _applyJsDocTypes(
  String source,
  Map<String, Set<String>> optionalParams, {
  required bool addAnyFallbacks,
}) {
  final lines = source.split('\n');
  final output = <String>[];
  final docBuffer = <String>[];
  _JsDocInfo? pendingDoc;
  var inDoc = false;
  var changed = 0;

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('/**')) {
      inDoc = true;
      docBuffer
        ..clear()
        ..add(line);
      if (trimmed.contains('*/')) {
        inDoc = false;
        pendingDoc = _parseJsDoc(docBuffer.join('\n'));
      }
      output.add(line);
      continue;
    }

    if (inDoc) {
      docBuffer.add(line);
      output.add(line);
      if (trimmed.contains('*/')) {
        inDoc = false;
        pendingDoc = _parseJsDoc(docBuffer.join('\n'));
      }
      continue;
    }

    if (pendingDoc != null && trimmed.isEmpty) {
      output.add(line);
      continue;
    }

    if (pendingDoc != null) {
      final converted = _applyFunctionTypesToLine(
        line,
        pendingDoc,
        optionalParams,
        addAnyFallbacks: addAnyFallbacks,
      );
      if (converted != null) {
        output.add(converted);
        changed += 1;
        pendingDoc = null;
        continue;
      }
      if (!trimmed.startsWith('*') && trimmed.isNotEmpty) {
        pendingDoc = null;
      }
    }

    output.add(line);
  }

  return (output.join('\n'), changed);
}

(String, int) _applyAnyFallbacks(
  String source,
  Map<String, Set<String>> optionalParams,
) {
  final lines = source.split('\n');
  var changed = 0;
  final converted = lines
      .map((line) {
        final next = _applyFunctionTypesToLine(
          line,
          const _JsDocInfo(params: {}),
          optionalParams,
          addAnyFallbacks: true,
        );
        if (next != null && next != line) {
          changed += 1;
          return next;
        }
        return line;
      })
      .join('\n');
  return (converted, changed);
}

_JsDocInfo _parseJsDoc(String block) {
  final params = <String, String>{};
  final paramPattern = RegExp(
    r'@param\s+\{([^}]+)\}\s+(\[?[A-Za-z_$][\w$]*(?:=[^\]]+)?\]?)',
  );
  for (final match in paramPattern.allMatches(block)) {
    var name = match.group(2)!;
    if (name.startsWith('[')) name = name.substring(1);
    if (name.endsWith(']')) name = name.substring(0, name.length - 1);
    final equals = name.indexOf('=');
    if (equals >= 0) name = name.substring(0, equals);
    params[name] = _jsDocTypeToTs(match.group(1)!);
  }
  final returnMatch = RegExp(r'@returns?\s+\{([^}]+)\}').firstMatch(block);
  return _JsDocInfo(
    params: params,
    returnType: returnMatch == null
        ? null
        : _jsDocTypeToTs(returnMatch.group(1)!),
  );
}

String? _applyFunctionTypesToLine(
  String line,
  _JsDocInfo doc,
  Map<String, Set<String>> optionalParams, {
  required bool addAnyFallbacks,
}) {
  const ident = r'[A-Za-z_$][\w$]*';
  final functionMatch = RegExp(
    '^(\\s*)((?:export\\s+)?(?:async\\s+)?)function\\s+($ident)\\s*\\(([^)]*)\\)(.*)\$',
  ).firstMatch(line);
  if (functionMatch != null) {
    final name = functionMatch.group(3)!;
    final params = _annotateParamList(
      functionMatch.group(4)!,
      doc.params,
      optionalParams[name] ?? const <String>{},
      addAnyFallbacks: addAnyFallbacks,
    );
    final returnType = _lineAlreadyHasReturnType(functionMatch.group(5)!)
        ? ''
        : _returnTypeSuffix(doc.returnType);
    return '${functionMatch.group(1)}${functionMatch.group(2)}function $name($params)$returnType${functionMatch.group(5)}';
  }

  final arrowMatch = RegExp(
    '^(\\s*)((?:export\\s+)?(?:const|let|var)\\s+($ident)\\s*=\\s*(?:async\\s*)?)\\(([^)]*)\\)(\\s*=>\\s*.*)\$',
  ).firstMatch(line);
  if (arrowMatch != null) {
    final name = arrowMatch.group(3)!;
    final params = _annotateParamList(
      arrowMatch.group(4)!,
      doc.params,
      optionalParams[name] ?? const <String>{},
      addAnyFallbacks: addAnyFallbacks,
    );
    final returnType = _returnTypeSuffix(doc.returnType);
    return '${arrowMatch.group(1)}${arrowMatch.group(2)}($params)$returnType${arrowMatch.group(5)}';
  }

  return null;
}

bool _lineAlreadyHasReturnType(String suffix) {
  return suffix.trimLeft().startsWith(':');
}

String _returnTypeSuffix(String? returnType) {
  if (returnType == null || returnType.isEmpty) return '';
  return ': $returnType';
}

String _annotateParamList(
  String rawParams,
  Map<String, String> jsDocTypes,
  Set<String> optionalNames, {
  required bool addAnyFallbacks,
}) {
  final params = _splitTopLevel(rawParams, ',');
  return params
      .map((param) {
        final original = param.trim();
        if (original.isEmpty || original.contains(':')) return original;
        final rest = original.startsWith('...');
        var working = rest ? original.substring(3).trim() : original;
        final defaultIndex = working.indexOf('=');
        final defaultValue = defaultIndex >= 0
            ? working.substring(defaultIndex).trim()
            : '';
        if (defaultIndex >= 0) {
          working = working.substring(0, defaultIndex).trim();
        }
        final nameMatch = RegExp(r'^([A-Za-z_$][\w$]*)$').firstMatch(working);
        if (nameMatch == null) return original;
        final name = nameMatch.group(1)!;
        var type = jsDocTypes[name];
        if (type == null && addAnyFallbacks) type = 'any';
        if (type == null) return original;
        if (rest && !type.endsWith('[]')) type = '$type[]';
        final optionalMarker =
            optionalNames.contains(name) && defaultValue.isEmpty ? '?' : '';
        final prefix = rest ? '...' : '';
        return '$prefix$name$optionalMarker: $type${defaultValue.isEmpty ? '' : ' $defaultValue'}';
      })
      .join(', ');
}

String _jsDocTypeToTs(String type) {
  var value = type.trim();
  var nullable = false;
  if (value.startsWith('?')) {
    nullable = true;
    value = value.substring(1);
  }
  value = value
      .replaceAll('String', 'string')
      .replaceAll('Number', 'number')
      .replaceAll('Boolean', 'boolean')
      .replaceAll('Object', 'Record<string, any>')
      .replaceAll('*', 'any');
  value = value.replaceAllMapped(
    RegExp(r'Array\.<([^>]+)>'),
    (match) => '${_jsDocTypeToTs(match.group(1)!)}[]',
  );
  value = value.replaceAllMapped(
    RegExp(r'Promise\.<([^>]+)>'),
    (match) => 'Promise<${_jsDocTypeToTs(match.group(1)!)}>',
  );
  value = value.replaceAll('|', ' | ');
  if (nullable) value = '$value | null';
  return value;
}

(String, int) _addClassPropertyDeclarations(String source) {
  final classes = _findJsClasses(source);
  if (classes.isEmpty) return (source, 0);
  final byName = {for (final info in classes) info.name: info};
  var output = source;
  var added = 0;

  for (final info in classes.reversed) {
    final inherited = _inheritedClassProperties(info, byName);
    final properties =
        info.properties
            .where((property) => !inherited.contains(property))
            .where(
              (property) =>
                  !_classAlreadyDeclaresProperty(source, info, property),
            )
            .toList()
          ..sort();
    if (properties.isEmpty) continue;
    final indent = _classPropertyIndent(source, info.openBraceIndex);
    final declarations = properties
        .map((property) => '$indent public $property: any;')
        .join('\n');
    output = output.replaceRange(
      info.openBraceIndex + 1,
      info.openBraceIndex + 1,
      '\n$declarations\n',
    );
    added += properties.length;
  }

  return (output, added);
}

List<_JsClassInfo> _findJsClasses(String source) {
  final classes = <_JsClassInfo>[];
  final classPattern = RegExp(
    r'\bclass\s+([A-Za-z_$][\w$]*)(?:\s+extends\s+([A-Za-z_$][\w$]*))?\s*\{',
  );
  for (final match in classPattern.allMatches(source)) {
    final openBraceIndex = source.indexOf('{', match.start);
    final closeBraceIndex = _matchingBraceIndex(source, openBraceIndex);
    if (openBraceIndex < 0 || closeBraceIndex < 0) continue;
    final body = source.substring(openBraceIndex + 1, closeBraceIndex);
    classes.add(
      _JsClassInfo(
        name: match.group(1)!,
        extendsName: match.group(2),
        openBraceIndex: openBraceIndex,
        closeBraceIndex: closeBraceIndex,
        properties: _classPropertiesFromBody(body),
      ),
    );
  }
  return classes;
}

Set<String> _classPropertiesFromBody(String body) {
  final properties = <String>{};
  for (final match in RegExp(r'\bthis\.([A-Za-z_$][\w$]*)').allMatches(body)) {
    properties.add(match.group(1)!);
  }
  final aliases = RegExp(
    r'\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*this\b',
  ).allMatches(body).map((match) => match.group(1)!);
  for (final alias in aliases) {
    final aliasPattern = RegExp(
      r'\b' + RegExp.escape(alias) + r'\.([A-Za-z_$][\w$]*)',
    );
    for (final match in aliasPattern.allMatches(body)) {
      properties.add(match.group(1)!);
    }
  }
  return properties;
}

Set<String> _inheritedClassProperties(
  _JsClassInfo info,
  Map<String, _JsClassInfo> classes,
) {
  final inherited = <String>{};
  var parent = info.extendsName == null ? null : classes[info.extendsName!];
  while (parent != null) {
    inherited.addAll(parent.properties);
    parent = parent.extendsName == null ? null : classes[parent.extendsName!];
  }
  return inherited;
}

bool _classAlreadyDeclaresProperty(
  String source,
  _JsClassInfo info,
  String property,
) {
  final body = source.substring(info.openBraceIndex + 1, info.closeBraceIndex);
  return RegExp(
    '(^|\\n)\\s*(public\\s+|private\\s+|protected\\s+|readonly\\s+|static\\s+)*${RegExp.escape(property)}\\s*[:=;]',
  ).hasMatch(body);
}

String _classPropertyIndent(String source, int openBraceIndex) {
  final lineStart = source.lastIndexOf('\n', openBraceIndex);
  final baseIndent = lineStart < 0
      ? ''
      : RegExp(r'^\s*')
                .firstMatch(source.substring(lineStart + 1, openBraceIndex))
                ?.group(0) ??
            '';
  return '$baseIndent  ';
}

int _matchingBraceIndex(String source, int openBraceIndex) {
  if (openBraceIndex < 0 || openBraceIndex >= source.length) return -1;
  var depth = 0;
  String? quote;
  var inLineComment = false;
  var inBlockComment = false;
  for (var i = openBraceIndex; i < source.length; i++) {
    final char = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (inLineComment) {
      if (char == '\n') inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (char == '*' && next == '/') {
        inBlockComment = false;
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (char == quote && (i == 0 || source[i - 1] != '\\')) quote = null;
      continue;
    }
    if (char == '/' && next == '/') {
      inLineComment = true;
      i++;
      continue;
    }
    if (char == '/' && next == '*') {
      inBlockComment = true;
      i++;
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      continue;
    }
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

(String, int) _rewriteCommonJsModuleSyntax(String source) {
  final lines = source.split('\n');
  var changed = 0;
  final output = lines
      .map((line) {
        final destructured = RegExp(
          r"""^(\s*)(?:const|let|var)\s+\{([^}]+)\}\s*=\s*require\((['"][^'"]+['"])\);?\s*$""",
        ).firstMatch(line);
        if (destructured != null) {
          changed += 1;
          final imports = _commonJsDestructuredImports(destructured.group(2)!);
          return '${destructured.group(1)}import { $imports } from ${destructured.group(3)};';
        }

        final defaultImport = RegExp(
          r"""^(\s*)(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\((['"][^'"]+['"])\);?\s*$""",
        ).firstMatch(line);
        if (defaultImport != null) {
          changed += 1;
          return '${defaultImport.group(1)}import ${defaultImport.group(2)} from ${defaultImport.group(3)};';
        }

        final objectExport = RegExp(
          r'^(\s*)module\.exports\s*=\s*\{([^}]+)\};?\s*$',
        ).firstMatch(line);
        if (objectExport != null) {
          changed += 1;
          return '${objectExport.group(1)}export { ${objectExport.group(2)!.trim()} };';
        }

        final defaultExport = RegExp(
          r'^(\s*)module\.exports\s*=\s*([A-Za-z_$][\w$]*);?\s*$',
        ).firstMatch(line);
        if (defaultExport != null) {
          changed += 1;
          return '${defaultExport.group(1)}export default ${defaultExport.group(2)};';
        }

        final namedExport = RegExp(
          r'^(\s*)exports\.([A-Za-z_$][\w$]*)\s*=\s*([A-Za-z_$][\w$]*);?\s*$',
        ).firstMatch(line);
        if (namedExport != null) {
          changed += 1;
          final name = namedExport.group(2)!;
          final value = namedExport.group(3)!;
          if (name == value) return '${namedExport.group(1)}export { $name };';
          return '${namedExport.group(1)}export const $name = $value;';
        }

        return line;
      })
      .join('\n');
  return (output, changed);
}

String _commonJsDestructuredImports(String raw) {
  return _splitTopLevel(raw, ',')
      .map((part) {
        final segments = part.split(':').map((item) => item.trim()).toList();
        if (segments.length == 2) return '${segments[0]} as ${segments[1]}';
        return part.trim();
      })
      .join(', ');
}

List<String> _splitTopLevel(String source, String separator) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var square = 0;
  var curly = 0;
  var paren = 0;
  String? quote;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      buffer.write(char);
      if (char == quote && (i == 0 || source[i - 1] != '\\')) quote = null;
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      buffer.write(char);
      continue;
    }
    if (char == '[') square++;
    if (char == ']') square = max(0, square - 1);
    if (char == '{') curly++;
    if (char == '}') curly = max(0, curly - 1);
    if (char == '(') paren++;
    if (char == ')') paren = max(0, paren - 1);
    if (char == separator && square == 0 && curly == 0 && paren == 0) {
      parts.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  final finalPart = buffer.toString().trim();
  if (finalPart.isNotEmpty) parts.add(finalPart);
  return parts;
}

Widget buildJsToTsConverter() {
  return const _JsToTsConverterView();
}
