/// Markdown preview tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../services/file_dialog_service.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _MarkdownPreviewView extends StatefulWidget {
  const _MarkdownPreviewView();

  @override
  State<_MarkdownPreviewView> createState() => _MarkdownPreviewViewState();
}

class _MarkdownPreviewViewState extends State<_MarkdownPreviewView> {
  final TextEditingController _input = TextEditingController();
  late final String _dropTargetScope = identityHashCode(this).toRadixString(16);
  String? _sourceFileName;
  String? _error;

  String get _dropTargetId => 'markdown-source-file-$_dropTargetScope';

  @override
  void dispose() {
    FileDropService.unregisterTarget(_dropTargetId);
    _input.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() {
      _sourceFileName = null;
      _error = null;
      _input.text = text;
    });
  }

  Future<void> _pickFile() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: const ['md', 'markdown', 'mdown', 'txt'],
    );
    if (path == null || !mounted) return;
    await _loadFile(path);
  }

  Future<void> _loadFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw const FileSystemException('Markdown file does not exist');
      }
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _sourceFileName = p.basename(path);
        _error = null;
        _input.text = text;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyFileReadError(error));
    }
  }

  void _setSample() {
    const sample = '''
# Heading 1

Paragraphs are separated by a blank line.

- Lists render as lists
- **Bold** and `inline code` render too''';
    setState(() {
      _sourceFileName = null;
      _error = null;
      _input.text = sample;
    });
  }

  void _clear() {
    setState(() {
      _sourceFileName = null;
      _error = null;
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final split = ResizableSplit(
      horizontal: false,
      initialRatio: 0.42,
      minFirstExtent: 110,
      minSecondExtent: 120,
      first: FileDropTargetRegion(
        targetId: _dropTargetId,
        onDropped: (paths) {
          if (paths.isNotEmpty) unawaited(_loadFile(paths.first));
        },
        child: EditorPane(
          label: 'Input',
          actions: [
            ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
            ToolButton(label: 'Sample', onPressed: _setSample),
            ToolButton(label: 'Clear', onPressed: _clear),
          ],
          controller: _input,
          onChanged: (_) {
            _sourceFileName = null;
            setState(() {});
          },
          placeholder: 'Drop a .md file here or type Markdown...',
          enableFileDrop: false,
          overlay: SourceFileControls(
            onPickFile: _pickFile,
            fileName: _sourceFileName,
            tooltip: 'Choose Markdown file',
          ),
        ),
      ),
      second: RenderedPreviewPane(
        label: 'Preview',
        html: markdownToHtmlForPreview(_input.text),
        badge: 'Rendered Markdown',
      ),
    );
    if (_error == null) return split;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_error!, style: errorToolTextStyle(context)),
        const SizedBox(height: 8),
        Expanded(child: split),
      ],
    );
  }
}

@visibleForTesting
String markdownToHtmlForPreview(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final buffer = StringBuffer();
  var inList = false;
  var inCode = false;
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    buffer.writeln('<p>${_markdownInline(paragraph.join(' '))}</p>');
    paragraph.clear();
  }

  void closeList() {
    if (!inList) return;
    buffer.writeln('</ul>');
    inList = false;
  }

  for (var index = 0; index < lines.length; index++) {
    final rawLine = lines[index];
    final line = rawLine.trimRight();
    final trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      flushParagraph();
      closeList();
      if (inCode) {
        buffer.writeln('</code></pre>');
      } else {
        buffer.writeln('<pre><code>');
      }
      inCode = !inCode;
      continue;
    }
    if (inCode) {
      buffer.writeln(htmlEscape.convert(rawLine));
      continue;
    }
    if (trimmed.isEmpty) {
      flushParagraph();
      closeList();
      continue;
    }
    final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
    if (heading != null) {
      flushParagraph();
      closeList();
      final level = heading.group(1)!.length;
      buffer.writeln(
        '<h$level>${_markdownInline(heading.group(2)!)}</h$level>',
      );
      continue;
    }
    if (_isMarkdownTableStart(lines, index)) {
      flushParagraph();
      closeList();
      final table = _parseMarkdownTable(lines, index);
      buffer.write(table.html);
      index = table.lastLineIndex;
      continue;
    }
    final bullet = RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
    if (bullet != null) {
      flushParagraph();
      if (!inList) {
        buffer.writeln('<ul>');
        inList = true;
      }
      buffer.writeln('<li>${_markdownInline(bullet.group(1)!)}</li>');
      continue;
    }
    paragraph.add(trimmed);
  }
  flushParagraph();
  closeList();
  if (inCode) buffer.writeln('</code></pre>');
  return buffer.toString();
}

bool _isMarkdownTableStart(List<String> lines, int index) {
  if (index + 1 >= lines.length) return false;
  final header = lines[index].trim();
  final delimiter = lines[index + 1].trim();
  return header.contains('|') && _isMarkdownTableDelimiter(delimiter);
}

bool _isMarkdownTableDelimiter(String line) {
  if (!line.contains('|')) return false;
  final cells = _splitMarkdownTableRow(line);
  if (cells.isEmpty) return false;
  return cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.trim()));
}

({String html, int lastLineIndex}) _parseMarkdownTable(
  List<String> lines,
  int startIndex,
) {
  final headers = _splitMarkdownTableRow(lines[startIndex]);
  final alignments = _splitMarkdownTableRow(
    lines[startIndex + 1],
  ).map(_markdownTableAlignment).toList();
  final rows = <List<String>>[];
  var index = startIndex + 2;

  while (index < lines.length) {
    final line = lines[index].trim();
    if (line.isEmpty || !line.contains('|')) break;
    rows.add(_splitMarkdownTableRow(lines[index]));
    index++;
  }

  String alignStyle(int cellIndex) {
    if (cellIndex >= alignments.length || alignments[cellIndex] == null) {
      return '';
    }
    return ' style="text-align: ${alignments[cellIndex]}"';
  }

  final buffer = StringBuffer()
    ..writeln('<div class="markdown-table-scroll">')
    ..writeln('<table>')
    ..writeln('<thead>')
    ..writeln('<tr>');
  for (var cellIndex = 0; cellIndex < headers.length; cellIndex++) {
    buffer.writeln(
      '<th${alignStyle(cellIndex)}>${_markdownInline(headers[cellIndex])}</th>',
    );
  }
  buffer
    ..writeln('</tr>')
    ..writeln('</thead>')
    ..writeln('<tbody>');

  for (final row in rows) {
    buffer.writeln('<tr>');
    for (var cellIndex = 0; cellIndex < headers.length; cellIndex++) {
      final value = cellIndex < row.length ? row[cellIndex] : '';
      buffer.writeln(
        '<td${alignStyle(cellIndex)}>${_markdownInline(value)}</td>',
      );
    }
    buffer.writeln('</tr>');
  }

  buffer
    ..writeln('</tbody>')
    ..writeln('</table>')
    ..writeln('</div>');
  return (html: buffer.toString(), lastLineIndex: index - 1);
}

List<String> _splitMarkdownTableRow(String line) {
  var trimmed = line.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
  return trimmed.split('|').map((cell) => cell.trim()).toList();
}

String? _markdownTableAlignment(String delimiter) {
  final trimmed = delimiter.trim();
  if (trimmed.startsWith(':') && trimmed.endsWith(':')) return 'center';
  if (trimmed.endsWith(':')) return 'right';
  if (trimmed.startsWith(':')) return 'left';
  return null;
}

String _markdownInline(String text) {
  var output = htmlEscape.convert(text);
  output = output.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (match) => '<code>${match.group(1)}</code>',
  );
  output = output.replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (match) => '<strong>${match.group(1)}</strong>',
  );
  output = output.replaceAllMapped(
    RegExp(r'\*([^*]+)\*'),
    (match) => '<em>${match.group(1)}</em>',
  );
  output = output.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
    (match) => '<a href="${match.group(2)}">${match.group(1)}</a>',
  );
  return output;
}

Widget buildMarkdownPreview() {
  return const _MarkdownPreviewView();
}
