/// HTML to JSX converter tool view.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _HtmlToJsxView extends StatefulWidget {
  const _HtmlToJsxView();

  @override
  State<_HtmlToJsxView> createState() => _HtmlToJsxViewState();
}

class _HtmlToJsxViewState extends State<_HtmlToJsxView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _convert() {
    try {
      final converted = _convertHtmlToJsx(_input.text);
      setState(() {
        _error = null;
        _output.text = converted;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
        _output.clear();
      });
    }
  }

  void _setExample() {
    _input.text = '''
<form class="login-form">
  <label for="email">Email</label>
  <input type="email" id="email" disabled>
  <button type="submit" class="btn">Submit</button>
</form>

<!-- Footer -->
<footer style="margin-top: 20px; padding: 10px; background-color: #333;">
  <p>Copyright 2026</p>
</footer>''';
    _convert();
  }

  void _clear() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(_error!, style: errorToolTextStyle(context)),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: buildSplitEditors(
            inputPlaceholder: 'Paste HTML here...',
            outputPlaceholder: 'JSX output...',
            inputController: _input,
            outputController: _output,
            onInputChanged: (_) => _convert(),
            inputActions: [
              ToolButton(label: 'Sample', onPressed: _setExample),
              ToolButton(label: 'Clear', onPressed: _clear),
            ],
            outputActions: const [],
            showInputHeader: false,
            showOutputHeader: false,
          ),
        ),
      ],
    );
  }
}

String _convertHtmlToJsx(String input) {
  var output = input.trim();
  if (output.isEmpty) return '';

  output = output.replaceAll(
    RegExp(r'<!doctype[^>]*>', caseSensitive: false),
    '',
  );
  output = output.replaceAllMapped(
    RegExp(r'<!--([\s\S]*?)-->'),
    (match) => '{/* ${match.group(1)!.trim()} */}',
  );

  final attrMap = <String, String>{
    'class': 'className',
    'for': 'htmlFor',
    'tabindex': 'tabIndex',
    'readonly': 'readOnly',
    'maxlength': 'maxLength',
    'minlength': 'minLength',
    'colspan': 'colSpan',
    'rowspan': 'rowSpan',
    'autofocus': 'autoFocus',
    'autocomplete': 'autoComplete',
    'contenteditable': 'contentEditable',
    'spellcheck': 'spellCheck',
    'srcset': 'srcSet',
    'crossorigin': 'crossOrigin',
    'enctype': 'encType',
    'novalidate': 'noValidate',
    'accept-charset': 'acceptCharset',
    'http-equiv': 'httpEquiv',
  };

  for (final entry in attrMap.entries) {
    output = output.replaceAllMapped(
      RegExp(
        '(^|\\s)${RegExp.escape(entry.key)}(?=\\s*=|\\s|>|/)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}${entry.value}',
    );
  }

  output = output.replaceAllMapped(
    RegExp(r'style\s*=\s*"([^"]*)"', caseSensitive: false),
    (match) => 'style={${_cssStyleToJsxObject(match.group(1)!)}}',
  );
  output = output.replaceAllMapped(
    RegExp(r"style\s*=\s*'([^']*)'", caseSensitive: false),
    (match) => 'style={${_cssStyleToJsxObject(match.group(1)!)}}',
  );

  const booleanAttributes = {
    'allowFullScreen',
    'async',
    'autoFocus',
    'autoPlay',
    'checked',
    'controls',
    'default',
    'defer',
    'disabled',
    'formNoValidate',
    'hidden',
    'loop',
    'multiple',
    'muted',
    'noValidate',
    'open',
    'readOnly',
    'required',
    'reversed',
    'selected',
  };
  for (final attr in booleanAttributes) {
    output = output.replaceAllMapped(
      RegExp('(\\s)$attr(?=\\s|>|/)(?!\\s*=)', caseSensitive: false),
      (match) => '${match.group(1)}$attr={true}',
    );
  }

  const voidTags = {
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
  output = output.replaceAllMapped(RegExp(r'<([a-zA-Z][\w:-]*)([^<>]*?)>'), (
    match,
  ) {
    final tag = match.group(1)!;
    final attrs = match.group(2)!;
    if (!voidTags.contains(tag.toLowerCase()) ||
        attrs.trimRight().endsWith('/')) {
      return match.group(0)!;
    }
    return '<$tag${attrs.trimRight()} />';
  });

  return _wrapMultipleJsxRoots(output.trim());
}

String _cssStyleToJsxObject(String style) {
  final declarations = style
      .split(';')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  final entries = <String>[];
  for (final declaration in declarations) {
    final separator = declaration.indexOf(':');
    if (separator <= 0) continue;
    final property = declaration.substring(0, separator).trim();
    final value = declaration.substring(separator + 1).trim();
    if (property.isEmpty || value.isEmpty) continue;
    entries.add('${_cssPropertyToJsx(property)}: ${_jsxStyleValue(value)}');
  }
  return '{ ${entries.join(', ')} }';
}

String _cssPropertyToJsx(String property) {
  if (property.startsWith('--')) return "'$property'";
  final parts = property.toLowerCase().split('-');
  return [
    parts.first,
    for (final part in parts.skip(1))
      if (part.isNotEmpty) part[0].toUpperCase() + part.substring(1),
  ].join();
}

String _jsxStyleValue(String value) {
  final escaped = value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  return "'$escaped'";
}

String _wrapMultipleJsxRoots(String output) {
  if (!_hasMultipleJsxRoots(output)) return output;
  final indented = output
      .split('\n')
      .map((line) => line.trim().isEmpty ? line : '  $line')
      .join('\n');
  return '<div>\n$indented\n</div>';
}

bool _hasMultipleJsxRoots(String output) {
  var depth = 0;
  var rootCount = 0;
  var index = 0;

  while (index < output.length) {
    final char = output[index];
    if (char.trim().isEmpty) {
      index++;
      continue;
    }

    if (output.startsWith('{/*', index)) {
      if (depth == 0) rootCount++;
      if (rootCount > 1) return true;
      final end = output.indexOf('*/}', index + 3);
      index = end == -1 ? output.length : end + 3;
      continue;
    }

    if (char == '<') {
      if (output.startsWith('</', index)) {
        depth = max(0, depth - 1);
        final end = output.indexOf('>', index + 2);
        index = end == -1 ? output.length : end + 1;
        continue;
      }

      final end = output.indexOf('>', index + 1);
      if (end == -1) break;
      final tag = output.substring(index, end + 1);
      if (depth == 0) {
        rootCount++;
        if (rootCount > 1) return true;
      }
      if (!tag.trimRight().endsWith('/>')) {
        depth++;
      }
      index = end + 1;
      continue;
    }

    if (depth == 0) {
      rootCount++;
      if (rootCount > 1) return true;
    }
    while (index < output.length &&
        output[index] != '<' &&
        !output.startsWith('{/*', index)) {
      index++;
    }
  }

  return false;
}

Widget buildHtmlToJsx() {
  return const _HtmlToJsxView();
}
