/// HTML/CSS/JS/RB beautify/minify tool views.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../services/file_dialog_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _SimplePassThroughView extends StatefulWidget {
  const _SimplePassThroughView({
    required this.inputPlaceholder,
    this.showIndent = false,
  });

  final String inputPlaceholder;
  final bool showIndent;

  @override
  State<_SimplePassThroughView> createState() => _SimplePassThroughViewState();
}

class _SimplePassThroughViewState extends State<_SimplePassThroughView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _indent = '2 spaces';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    setState(() => _output.text = _input.text);
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() => _input.text = text);
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    final outputActions = <Widget>[];
    if (widget.showIndent) {
      outputActions.add(
        SmallDropdown(
          items: const ['2 spaces', '4 spaces', 'Tabs'],
          initialValue: _indent,
          onChanged: (value) {
            setState(() => _indent = value);
            _run();
          },
        ),
      );
    }
    outputActions.add(ToolButton(label: 'Copy', onPressed: _copyOutput));

    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: () {}),
        ToolButton(label: 'Clear', onPressed: _clearInput),
      ],
      outputActions: outputActions,
      inputController: _input,
      outputController: _output,
      inputPlaceholder: widget.inputPlaceholder,
      outputPlaceholder: 'Output...',
    );
  }
}

class _StyleBeautifyMinifyView extends StatefulWidget {
  const _StyleBeautifyMinifyView({required this.language});

  final String language;

  @override
  State<_StyleBeautifyMinifyView> createState() =>
      _StyleBeautifyMinifyViewState();
}

class _StyleBeautifyMinifyViewState extends State<_StyleBeautifyMinifyView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  late final String _dropTargetScope = identityHashCode(this).toRadixString(16);
  String _format = 'Beautify';
  String _indent = '2 spaces';
  String? _sourceFileName;
  String? _error;

  String get _dropTargetId => 'style-source-file-$_dropTargetScope';

  List<String> get _acceptedExtensions {
    final ext = widget.language.toLowerCase();
    return [ext, 'txt'];
  }

  @override
  void dispose() {
    FileDropService.unregisterTarget(_dropTargetId);
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    _output.text = _format == 'Minify'
        ? _minifyStyleSheet(text)
        : _beautifyStyleSheet(text, indentFor(_indent));
    setState(() {});
  }

  Future<void> _pickFile() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: _acceptedExtensions,
    );
    if (path == null || !mounted) return;
    await _loadFile(path);
  }

  Future<void> _copyOutput() async {
    if (_output.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  Future<void> _loadFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('${widget.language} file does not exist');
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

  void _setSample() {
    const sample =
        'body{margin:25px;background-color:rgb(240,240,240);font-size:14px;}'
        'h1{font-size:35px;font-weight:normal;margin-top:5px;}';
    setState(() {
      _sourceFileName = null;
      _error = null;
      _input.text = sample;
    });
    _run();
  }

  void _clearInput() {
    setState(() {
      _sourceFileName = null;
      _error = null;
      _input.clear();
      _output.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controls = _HtmlFormatControls(
      format: _format,
      indent: _indent,
      formats: const ['Beautify', 'Minify'],
      showIndent: _format == 'Beautify',
      onFormatChanged: (value) {
        setState(() => _format = value);
        _run();
      },
      onIndentChanged: (value) {
        setState(() => _indent = value);
        _run();
      },
    );

    final editors = buildSplitEditors(
      inputPlaceholder:
          'Drop a .${widget.language.toLowerCase()} file here '
          'or paste ${widget.language}...',
      outputPlaceholder: 'Output...',
      inputController: _input,
      outputController: _output,
      onInputChanged: (_) {
        _sourceFileName = null;
        _run();
      },
      inputActions: [
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
      ],
      outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
      inputOverlay: SourceFileControls(
        onPickFile: _pickFile,
        fileName: _sourceFileName,
        tooltip: 'Choose ${widget.language} file',
      ),
      outputOverlay: controls,
      showInputHeader: false,
      showOutputHeader: false,
      inputDropTargetId: _dropTargetId,
      onInputDropped: (paths) {
        if (paths.isNotEmpty) unawaited(_loadFile(paths.first));
      },
    );

    if (_error == null) return editors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_error!, style: errorToolTextStyle(context)),
        const SizedBox(height: 8),
        Expanded(child: editors),
      ],
    );
  }
}


/// Adds a missing space after a declaration's property colon
/// (`color:red` -> `color: red`) without touching URLs or selectors.
String _spaceDeclarationColon(String line) {
  final colon = line.indexOf(':');
  if (colon <= 0 || colon + 1 >= line.length) return line;
  if (line[colon + 1] == ' ') return line;
  final property = line.substring(0, colon);
  if (!RegExp(r'^[-a-zA-Z]+$').hasMatch(property)) return line;
  return '${line.substring(0, colon)}: ${line.substring(colon + 1)}';
}

String _beautifyStyleSheet(String source, String indentString) {
  final input = source.trim();
  if (input.isEmpty) return '';

  final lines = <String>[];
  final buffer = StringBuffer();
  var indentLevel = 0;
  String? quote;
  var inComment = false;
  var previousWasSpace = false;

  String indent() => List.filled(indentLevel, indentString).join();

  void writeBuffered({bool suffixSemicolon = false}) {
    final text = buffer.toString().trim();
    buffer.clear();
    previousWasSpace = false;
    if (text.isEmpty) return;
    lines.add('${indent()}${_spaceDeclarationColon(text)}${suffixSemicolon ? ';' : ''}');
  }

  void writeComment(String comment) {
    final text = comment.trim();
    if (text.isEmpty) return;
    final commentLines = text.split('\n');
    for (final line in commentLines) {
      final trimmed = line.trimRight();
      if (trimmed.isNotEmpty) lines.add('${indent()}$trimmed');
    }
  }

  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    final next = i + 1 < input.length ? input[i + 1] : '';

    if (inComment) {
      buffer.write(char);
      if (char == '*' && next == '/') {
        buffer.write('/');
        i++;
        inComment = false;
        writeComment(buffer.toString());
        buffer.clear();
      }
      continue;
    }

    if (quote != null) {
      buffer.write(char);
      if (char == quote && (i == 0 || input[i - 1] != '\\')) {
        quote = null;
      }
      continue;
    }

    if ((char == '"' || char == "'")) {
      quote = char;
      buffer.write(char);
      previousWasSpace = false;
      continue;
    }

    if (char == '/' && next == '*') {
      writeBuffered();
      inComment = true;
      buffer.write('/*');
      i++;
      continue;
    }

    if (char == '{') {
      final selector = buffer.toString().trim();
      buffer.clear();
      if (selector.isNotEmpty) {
        lines.add('${indent()}$selector {');
      } else {
        lines.add('${indent()}{');
      }
      indentLevel += 1;
      previousWasSpace = false;
      continue;
    }

    if (char == '}') {
      writeBuffered();
      indentLevel = max(0, indentLevel - 1);
      lines.add('${indent()}}');
      previousWasSpace = false;
      continue;
    }

    if (char == ';') {
      writeBuffered(suffixSemicolon: true);
      continue;
    }

    if (RegExp(r'\s').hasMatch(char)) {
      if (!previousWasSpace && buffer.isNotEmpty) {
        buffer.write(' ');
        previousWasSpace = true;
      }
      continue;
    }

    buffer.write(char);
    previousWasSpace = false;
  }

  if (inComment) {
    writeComment(buffer.toString());
  } else {
    writeBuffered();
  }

  return lines.join('\n');
}

String _minifyStyleSheet(String source) {
  var output = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  output = output.replaceAll(RegExp(r'\s+'), ' ');
  output = output.replaceAllMapped(
    RegExp(r'\s*([{}:;,>+~])\s*'),
    (match) => match.group(1)!,
  );
  output = output.replaceAll(RegExp(r';}'), '}');
  return output.trim();
}

class _HtmlBeautifyMinifyView extends StatefulWidget {
  const _HtmlBeautifyMinifyView();

  @override
  State<_HtmlBeautifyMinifyView> createState() =>
      _HtmlBeautifyMinifyViewState();
}

class _HtmlBeautifyMinifyViewState extends State<_HtmlBeautifyMinifyView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _format = 'Beautify';
  String _indent = '2 spaces';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    switch (_format) {
      case 'Minify':
        _output.text = _minifyHtml(text);
        break;
      case 'Preview':
        _output.text = '';
        break;
      case 'Beautify':
      default:
        _output.text = _beautifyHtml(text, indentFor(_indent));
        break;
    }
    setState(() {});
  }

  String _beautifyHtml(String html, String indentString) {
    if (html.trim().isEmpty) return '';
    final tokens = RegExp(r'<!--[\s\S]*?-->|<[^>]+>|[^<]+').allMatches(html);
    final lines = <String>[];
    var level = 0;

    for (final match in tokens) {
      final token = match.group(0) ?? '';
      final trimmed = token.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('<')) {
        final tagName = _htmlTagName(trimmed);
        final closing = trimmed.startsWith('</');
        final declaration =
            trimmed.startsWith('<!') || trimmed.startsWith('<?');
        final selfClosing =
            declaration ||
            trimmed.endsWith('/>') ||
            (tagName != null && _htmlVoidTags.contains(tagName));

        if (closing) level = max(0, level - 1);
        lines.add('${List.filled(level, indentString).join()}$trimmed');
        if (!closing &&
            !selfClosing &&
            tagName != null &&
            !_htmlInlineTags.contains(tagName)) {
          level += 1;
        }
      } else {
        final text = trimmed.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isNotEmpty) {
          lines.add('${List.filled(level, indentString).join()}$text');
        }
      }
    }

    return lines.join('\n');
  }

  String _minifyHtml(String html) {
    var result = html;
    result = result.replaceAll(RegExp(r'<!--(?!\[if)[\s\S]*?-->'), '');
    result = result.replaceAll(RegExp(r'>\s+<'), '><');
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ');
    result = result.replaceAll(RegExp(r'\s*=\s*'), '=');
    return result.trim();
  }

  void _setSample() {
    const sample = '<div class="card">\n  <h1>Hello</h1>\n</div>';
    setState(() => _input.text = sample);
    _run();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    final outputControls = _HtmlFormatControls(
      format: _format,
      indent: _indent,
      showIndent: _format == 'Beautify',
      onFormatChanged: (value) {
        setState(() => _format = value);
        _run();
      },
      onIndentChanged: (value) {
        setState(() => _indent = value);
        _run();
      },
    );

    return ResizableSplit(
      horizontal: false,
      first: EditorPane(
        label: 'Input',
        actions: [
          ToolButton(label: 'Sample', onPressed: _setSample),
          ToolButton(label: 'Clear', onPressed: _clearInput),
        ],
        controller: _input,
        onChanged: (_) => _run(),
        placeholder: 'Paste HTML here...',
        showHeader: false,
      ),
      second: _format == 'Preview'
          ? HtmlRenderedPreview(html: _input.text, overlay: outputControls)
          : EditorPane(
              label: 'Output',
              actions: const [],
              controller: _output,
              readOnly: true,
              placeholder: 'Output...',
              copyAction: _copyOutput,
              showHeader: false,
              overlay: outputControls,
            ),
    );
  }
}

class _HtmlFormatControls extends StatelessWidget {
  const _HtmlFormatControls({
    required this.format,
    required this.indent,
    required this.showIndent,
    required this.onFormatChanged,
    required this.onIndentChanged,
    this.formats = const ['Beautify', 'Minify', 'Preview'],
  });

  final String format;
  final String indent;
  final bool showIndent;
  final ValueChanged<String> onFormatChanged;
  final ValueChanged<String> onIndentChanged;
  final List<String> formats;

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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Format',
              style: TextStyle(
                color: appColors.editorText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            SmallDropdown(
              items: formats,
              initialValue: format,
              onChanged: onFormatChanged,
            ),
            if (showIndent) ...[
              const SizedBox(width: 6),
              SmallDropdown(
                items: const ['2 spaces', '4 spaces', 'Tabs'],
                initialValue: indent,
                onChanged: onIndentChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _htmlTagName(String tag) {
  final match = RegExp(r'^</?\s*([a-zA-Z0-9:-]+)').firstMatch(tag);
  return match?.group(1)?.toLowerCase();
}

const _htmlVoidTags = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

const _htmlInlineTags = {
  'a',
  'abbr',
  'b',
  'bdi',
  'bdo',
  'br',
  'button',
  'cite',
  'code',
  'data',
  'dfn',
  'em',
  'i',
  'img',
  'input',
  'kbd',
  'label',
  'mark',
  'q',
  's',
  'samp',
  'small',
  'span',
  'strong',
  'sub',
  'sup',
  'textarea',
  'time',
  'u',
  'var',
};

class _JsBeautifyMinifyView extends StatefulWidget {
  const _JsBeautifyMinifyView();

  @override
  State<_JsBeautifyMinifyView> createState() => _JsBeautifyMinifyViewState();
}

class _JsBeautifyMinifyViewState extends State<_JsBeautifyMinifyView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _format = 'Beautify';
  String _indent = '2 spaces';

  static const Set<String> _jsKeywords = {
    'break',
    'case',
    'catch',
    'continue',
    'debugger',
    'default',
    'delete',
    'do',
    'else',
    'finally',
    'for',
    'function',
    'if',
    'in',
    'instanceof',
    'new',
    'return',
    'switch',
    'this',
    'throw',
    'try',
    'typeof',
    'var',
    'void',
    'while',
    'with',
    'class',
    'const',
    'enum',
    'export',
    'extends',
    'import',
    'super',
    'implements',
    'interface',
    'let',
    'package',
    'private',
    'protected',
    'public',
    'static',
    'yield',
    'async',
    'await',
    'of',
    'true',
    'false',
    'null',
    'undefined',
    'nan',
    'infinity',
  };

  static const Set<String> _tsKeywords = {
    'type',
    'interface',
    'namespace',
    'module',
    'declare',
    'abstract',
    'as',
    'asserts',
    'any',
    'boolean',
    'constructor',
    'get',
    'set',
    'infer',
    'is',
    'keyof',
    'never',
    'readonly',
    'require',
    'number',
    'object',
    'string',
    'symbol',
    'unique',
    'unknown',
    'from',
    'global',
    'bigint',
    'override',
    'satisfies',
  };

  static final Set<String> _allKeywords = {..._jsKeywords, ..._tsKeywords};

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    switch (_format) {
      case 'Minify':
        _output.text = _minifyJs(text);
        break;
      case 'Obfuscate':
        _output.text = _obfuscateJs(text);
        break;
      case 'Verify':
        _output.text = _formatKeywordTypos(text);
        break;
      case 'Beautify':
      default:
        _output.text = _beautifyJs(text, indentFor(_indent));
        break;
    }
    setState(() {});
  }

  String _beautifyJs(String code, String indentString) {
    if (code.trim().isEmpty) return '';
    var result = '';
    var indentLevel = 0;
    String? inString;
    var inSingleLineComment = false;
    var inMultiLineComment = false;
    var genericDepth = 0;
    var lastChar = ' ';
    var lastNonWhitespace = ' ';
    final chars = code.split('');
    var i = 0;

    const genericKeywords = {
      'Array',
      'Map',
      'Set',
      'Promise',
      'Record',
      'Partial',
      'Required',
      'Pick',
      'Omit',
      'Exclude',
      'Extract',
      'ReturnType',
      'Parameters',
      'InstanceType',
      'Readonly',
      'NonNullable',
    };
    const typeKeywords = {
      'extends',
      'implements',
      'type',
      'interface',
      'as',
      'is',
      'keyof',
      'typeof',
      'infer',
    };

    String indent() => List.filled(indentLevel, indentString).join();

    void addNewline() {
      result = _trimTrailingWhitespace(result);
      if (!result.endsWith('\n')) {
        result += '\n';
      }
    }

    String? peek([int offset = 1]) {
      final idx = i + offset;
      return idx < chars.length ? chars[idx] : null;
    }

    String extractLastToken() {
      var token = '';
      for (final char in result.split('').reversed) {
        if (_isTokenChar(char)) {
          token = char + token;
        } else {
          break;
        }
      }
      return token;
    }

    while (i < chars.length) {
      final char = chars[i];
      final next = peek();

      if (inString == null &&
          !inMultiLineComment &&
          char == '/' &&
          next == '/') {
        result += '//';
        i += 2;
        inSingleLineComment = true;
        continue;
      }

      if (inSingleLineComment) {
        result += char;
        if (char == '\n') {
          inSingleLineComment = false;
          result += indent();
        }
        i += 1;
        continue;
      }

      if (inString == null && char == '/' && next == '*') {
        result += '/*';
        i += 2;
        inMultiLineComment = true;
        continue;
      }

      if (inMultiLineComment) {
        result += char;
        if (char == '*' && next == '/') {
          result += '/';
          inMultiLineComment = false;
          i += 2;
          continue;
        }
        i += 1;
        continue;
      }

      if ((char == '"' || char == "'" || char == '`') && lastChar != '\\') {
        if (inString == char) {
          inString = null;
        } else {
          inString ??= char;
        }
        result += char;
        lastChar = char;
        lastNonWhitespace = char;
        i += 1;
        continue;
      }

      if (inString != null) {
        result += char;
        lastChar = char;
        i += 1;
        continue;
      }

      switch (char) {
        case '{':
          if (!result.endsWith(' ') &&
              !result.endsWith('\n') &&
              !result.endsWith('(')) {
            result += ' ';
          }
          result += '{';
          indentLevel += 1;
          addNewline();
          result += indent();
          break;
        case '}':
          indentLevel = max(0, indentLevel - 1);
          addNewline();
          result += indent();
          result += '}';
          if (next != null &&
              next != ',' &&
              next != ';' &&
              next != ')' &&
              next != '}' &&
              next != ']' &&
              next != '.' &&
              next != '>') {
            addNewline();
            result += indent();
          }
          break;
        case '[':
          result += char;
          if (next == '{' || next == '[') {
            indentLevel += 1;
            addNewline();
            result += indent();
          }
          break;
        case ']':
          if (lastNonWhitespace == '}' || lastNonWhitespace == ']') {
            indentLevel = max(0, indentLevel - 1);
            addNewline();
            result += indent();
          }
          result += char;
          break;
        case '<':
          final token = extractLastToken();
          final isGeneric =
              genericKeywords.contains(token) ||
              typeKeywords.contains(token) ||
              (token.isNotEmpty && _startsWithUppercase(token)) ||
              lastNonWhitespace == ':' ||
              genericDepth > 0;
          if (isGeneric) {
            genericDepth += 1;
            result += char;
          } else {
            if (!result.endsWith(' ')) {
              result += ' ';
            }
            result += char;
            if (next == '=') {
              result += '=';
              i += 1;
            }
            result += ' ';
          }
          break;
        case '>':
          if (genericDepth > 0) {
            genericDepth -= 1;
            result += char;
          } else {
            if (!result.endsWith(' ') && !result.endsWith('=')) {
              result += ' ';
            }
            result += char;
            if (next == '=') {
              result += '=';
              i += 1;
            }
            if (!result.endsWith(' ')) {
              result += ' ';
            }
          }
          break;
        case ';':
          result += char;
          if (next != null && next != '}') {
            addNewline();
            result += indent();
          }
          break;
        case ',':
          result += char;
          if (lastNonWhitespace == '}' || lastNonWhitespace == ']') {
            addNewline();
            result += indent();
          } else {
            result += ' ';
          }
          break;
        case ':':
          result += ': ';
          break;
        case '@':
          if (result.isNotEmpty && !RegExp(r'\s$').hasMatch(result)) {
            addNewline();
            result += indent();
          }
          result += char;
          break;
        case '(':
        case ')':
          result += char;
          break;
        case '=':
          if (!result.endsWith(' ') &&
              !result.endsWith('!') &&
              !result.endsWith('<') &&
              !result.endsWith('>')) {
            result += ' ';
          }
          result += char;
          if (next == '=') {
            result += '=';
            i += 1;
            if (peek() == '=') {
              result += '=';
              i += 1;
            }
          } else if (next == '>') {
            result += '>';
            i += 1;
          }
          result += ' ';
          break;
        case '+':
        case '-':
        case '*':
        case '/':
        case '%':
          if (char == '/' &&
              (lastNonWhitespace == '(' ||
                  lastNonWhitespace == '=' ||
                  lastNonWhitespace == ',')) {
            result += char;
          } else {
            if (!result.endsWith(' ') &&
                !result.endsWith('\n') &&
                !result.endsWith('(')) {
              result += ' ';
            }
            result += char;
            if (next == '=' || next == char) {
              result += next!;
              i += 1;
            }
            result += ' ';
          }
          break;
        case '!':
        case '&':
        case '|':
        case '?':
          result += char;
          if (next == char ||
              next == '=' ||
              (char == '?' && next == '.') ||
              (char == '?' && next == '?')) {
            result += next!;
            i += 1;
          }
          if (char == '&' || char == '|') {
            result += ' ';
          }
          break;
        case ' ':
        case '\t':
        case '\n':
        case '\r':
          if (result.isNotEmpty &&
              !result.endsWith(' ') &&
              !result.endsWith('\n')) {
            result += ' ';
          }
          break;
        default:
          result += char;
      }

      lastChar = char;
      if (!RegExp(r'\s').hasMatch(char)) {
        lastNonWhitespace = char;
      }
      i += 1;
    }

    return _cleanupJsBeautify(result, indentString);
  }

  String _cleanupJsBeautify(String input, String indentString) {
    var result = input;
    const replacements = {
      '  ': ' ',
      ' \n': '\n',
      '( ': '(',
      ' )': ')',
      '[ ': '[',
      ' ]': ']',
      ' ;': ';',
      ' ,': ',',
      '< ': '<',
      ' >': '>',
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in replacements.entries) {
        if (result.contains(entry.key)) {
          result = result.replaceAll(entry.key, entry.value);
          changed = true;
        }
      }
    }

    final lines = result.split('\n');
    final finalLines = <String>[];
    var indent = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('}') || trimmed.startsWith(']')) {
        indent = max(0, indent - 1);
      }
      if (trimmed.isNotEmpty) {
        finalLines.add(List.filled(indent, indentString).join() + trimmed);
      } else {
        finalLines.add('');
      }
      if (trimmed.endsWith('{') ||
          (trimmed.endsWith('[') && !trimmed.contains(']'))) {
        indent += 1;
      }
    }

    return finalLines.join('\n').trim();
  }

  bool _isTokenChar(String value) {
    return RegExp(r'[A-Za-z0-9_]').hasMatch(value);
  }

  bool _startsWithUppercase(String value) {
    if (value.isEmpty) return false;
    final first = value[0];
    return first.toUpperCase() == first && first.toLowerCase() != first;
  }

  String _trimTrailingWhitespace(String value) {
    var result = value;
    while (result.isNotEmpty &&
        RegExp(r'\s').hasMatch(result[result.length - 1])) {
      if (result.endsWith('\n')) {
        break;
      }
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  String _minifyJs(String text) {
    var output = text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    output = output.replaceAll(RegExp(r'//.*'), '');
    output = output.replaceAll(RegExp(r'\s+'), ' ');
    output = output.replaceAllMapped(
      RegExp(r'\s*([{}();,:])\s*'),
      (match) => match.group(1)!,
    );
    return output.trim();
  }

  String _obfuscateJs(String text) {
    if (text.trim().isEmpty) return '';
    final encoded = base64.encode(utf8.encode(text));
    return [
      '(function(){',
      '  const _d = typeof atob === "function"',
      '    ? atob',
      '    : (s) => Buffer.from(s, "base64").toString("utf8");',
      '  eval(_d("$encoded"));',
      '})();',
    ].join('\n');
  }

  String _formatKeywordTypos(String text) {
    final typos = _findKeywordTypos(text);
    if (typos.isEmpty) {
      return 'No keyword typos found.';
    }
    return typos
        .map(
          (typo) =>
              'Line ${typo.line}, Col ${typo.column}: \'${typo.found}\' -> did you mean \'${typo.suggestion}\'?',
        )
        .join('\n');
  }

  List<_KeywordTypo> _findKeywordTypos(String code, {int maxDistance = 2}) {
    final tokens = _extractTokens(code);
    final typos = <_KeywordTypo>[];
    for (final token in tokens) {
      final value = token.value;
      final lower = value.toLowerCase();
      if (_allKeywords.contains(lower)) {
        continue;
      }
      if (value.length < 2 || value.length > 12) {
        continue;
      }
      if (value.isNotEmpty && value[0].toUpperCase() == value[0]) {
        continue;
      }
      final closest = _findClosestKeyword(lower, maxDistance: maxDistance);
      if (closest != null) {
        typos.add(
          _KeywordTypo(
            found: value,
            suggestion: closest.keyword,
            line: token.line,
            column: token.column,
            distance: closest.distance,
          ),
        );
      }
    }
    return typos;
  }

  List<_Token> _extractTokens(String code) {
    final tokens = <_Token>[];
    final chars = code.split('');
    var current = StringBuffer();
    int? tokenLine;
    int? tokenColumn;
    var line = 1;
    var col = 1;
    String? inString;
    var inLineComment = false;
    var inBlockComment = false;

    void flushToken() {
      if (current.isEmpty || tokenLine == null || tokenColumn == null) return;
      tokens.add(_Token(current.toString(), tokenLine!, tokenColumn!));
      current = StringBuffer();
      tokenLine = null;
      tokenColumn = null;
    }

    for (var i = 0; i < chars.length; i++) {
      final char = chars[i];
      final next = i + 1 < chars.length ? chars[i + 1] : null;
      final prev = i > 0 ? chars[i - 1] : null;

      if (char == '\n') {
        flushToken();
        line += 1;
        col = 1;
        inLineComment = false;
        continue;
      }

      if (inString == null && !inBlockComment && char == '/' && next == '/') {
        inLineComment = true;
      }
      if (inString == null && !inLineComment && char == '/' && next == '*') {
        inBlockComment = true;
      }
      if (inBlockComment && char == '*' && next == '/') {
        inBlockComment = false;
        i += 1;
        col += 2;
        continue;
      }

      if (inLineComment || inBlockComment) {
        col += 1;
        continue;
      }

      if ((char == '"' || char == "'" || char == '`') && prev != '\\') {
        if (inString == char) {
          inString = null;
        } else {
          inString ??= char;
        }
        col += 1;
        continue;
      }

      if (inString != null) {
        col += 1;
        continue;
      }

      final isTokenChar = RegExp(r'[A-Za-z0-9_]').hasMatch(char);
      final isStartChar = RegExp(r'[A-Za-z_]').hasMatch(char);

      if (isTokenChar && (current.isNotEmpty || isStartChar)) {
        if (current.isEmpty) {
          tokenLine = line;
          tokenColumn = col;
        }
        current.write(char);
      } else {
        flushToken();
      }

      col += 1;
    }

    flushToken();
    return tokens;
  }

  _KeywordCandidate? _findClosestKeyword(
    String word, {
    required int maxDistance,
  }) {
    _KeywordCandidate? best;
    for (final keyword in _allKeywords) {
      if ((keyword.length - word.length).abs() > maxDistance) continue;
      final distance = _levenshteinDistance(word, keyword);
      if (distance > 0 && distance <= maxDistance) {
        if (best == null || distance < best.distance) {
          best = _KeywordCandidate(keyword, distance);
        }
      }
    }
    return best;
  }

  int _levenshteinDistance(String s1, String s2) {
    final a = s1.split('');
    final b = s2.split('');
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final matrix = List.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return matrix[a.length][b.length];
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() => _input.text = text);
    _run();
  }

  void _setSample() {
    const sample =
        '// program to generate fibonacci series up to n terms\n'
        '\n'
        '// take input from the user\n'
        "const number = parseInt(prompt('Enter the number of terms: '));\n"
        'let n1 = 0, n2 = 1, nextTerm;\n'
        '\n'
        "console.log('Fibonacci Series:');\n"
        '\n'
        'for (let i = 1; i <= number; i++) {\n'
        '    console.log(n1);\n'
        '    nextTerm = n1 + n2;\n'
        '    n1 = n2;\n'
        '    n2 = nextTerm;\n'
        '}\n';
    setState(() => _input.text = sample);
    _run();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
      ],
      outputActions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Format...',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            SmallDropdown(
              items: const ['Beautify', 'Minify', 'Obfuscate', 'Verify'],
              initialValue: _format,
              onChanged: (value) {
                setState(() => _format = value);
                _run();
              },
            ),
          ],
        ),
        if (_format == 'Beautify')
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
      inputController: _input,
      outputController: _output,
      inputPlaceholder: 'Paste JavaScript or TypeScript here...',
      outputPlaceholder: 'Output...',
    );
  }
}

class _Token {
  const _Token(this.value, this.line, this.column);

  final String value;
  final int line;
  final int column;
}

class _KeywordTypo {
  const _KeywordTypo({
    required this.found,
    required this.suggestion,
    required this.line,
    required this.column,
    required this.distance,
  });

  final String found;
  final String suggestion;
  final int line;
  final int column;
  final int distance;
}

class _KeywordCandidate {
  const _KeywordCandidate(this.keyword, this.distance);

  final String keyword;
  final int distance;
}

// Re-indents Ruby source by keyword/`end` block structure. Each line is
// trimmed and re-indented from a running level, so it works on flat input.
String _beautifyRuby(String source, String indent) {
  if (source.trim().isEmpty) return '';
  final lines = source.split('\n');
  final out = <String>[];
  var level = 0;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      out.add('');
      continue;
    }
    final closes = RegExp(r'^(end\b|\}|\]|\))').hasMatch(line);
    final continuation = RegExp(
      r'^(else\b|elsif\b|when\b|in\b|rescue\b|ensure\b)',
    ).hasMatch(line);
    if (closes || continuation) level = max(0, level - 1);
    out.add('${List.filled(level, indent).join()}$line');
    if (continuation) {
      level += 1;
    } else if (!closes && _rubyOpensBlock(line)) {
      level += 1;
    }
  }
  return out.join('\n').trimRight();
}

bool _rubyOpensBlock(String line) {
  // Strip a trailing line comment that isn't inside a string.
  final code = line.replaceFirst(RegExp(r'\s+#(?![{]).*$'), '').trimRight();
  if (RegExp(r'^(def|class|module|begin)\b').hasMatch(code)) return true;
  if (RegExp(r'^(if|unless|while|until|for|case)\b').hasMatch(code)) {
    // Exclude one-line forms like `if x then y end`.
    return !RegExp(r'\bend\b').hasMatch(code);
  }
  if (RegExp(r'\bdo\b(\s*\|[^|]*\|)?\s*$').hasMatch(code)) return true;
  if (code.endsWith('{') || RegExp(r'\{\s*\|[^|]*\|\s*$').hasMatch(code)) {
    return true;
  }
  return false;
}

String _minifyRuby(String source, bool keepComments) {
  // Ruby is newline-significant, so "minify" just strips blank lines, full-line
  // comments, and leading/trailing whitespace.
  final lines = source.split('\n');
  final out = <String>[];
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (!keepComments && line.startsWith('#')) continue;
    out.add(line);
  }
  return out.join('\n');
}

Widget buildHtmlBeautifyMinify(String language) {
  if (language == 'JS') {
    return const _JsBeautifyMinifyView();
  }
  if (language == 'HTML') {
    return const _HtmlBeautifyMinifyView();
  }
  if (language == 'CSS') {
    return _StyleBeautifyMinifyView(language: language);
  }
  if (language == 'RB') {
    return const MarkupBeautifyMinifyView(
      language: 'RB',
      beautify: _beautifyRuby,
      minify: _minifyRuby,
    );
  }
  return _SimplePassThroughView(
    inputPlaceholder: 'Paste $language here...',
    showIndent: true,
  );
}
