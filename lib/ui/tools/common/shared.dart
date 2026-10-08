/// Helpers shared across multiple tool implementations.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../services/file_dialog_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import 'editors.dart';

ValueChanged<String>? goActionChanged(List<Widget> actions) {
  for (final action in actions) {
    if (action is ToolButton && action.label == 'Go') {
      final onPressed = action.onPressed;
      if (onPressed != null) return (_) => onPressed();
    }
  }
  return null;
}

String indentFor(String value) {
  switch (value) {
    case '4 spaces':
      return '    ';
    case 'Tabs':
      return '\t';
    default:
      return '  ';
  }
}

String bytesToHex(List<int> bytes, {bool lower = false}) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    final hex = byte.toRadixString(16).padLeft(2, '0');
    buffer.write(lower ? hex : hex.toUpperCase());
  }
  return buffer.toString();
}

Future<String> readClipboardText() async {
  final data = await Clipboard.getData('text/plain');
  return data?.text ?? '';
}

BoxDecoration toolSurfaceDecoration(
  BuildContext context, {
  double radius = 8,
}) {
  final appColors = context.appColors;
  return BoxDecoration(
    color: appColors.panelElevated,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: appColors.border),
  );
}

TextStyle mutedToolTextStyle(BuildContext context, {double? fontSize}) {
  return TextStyle(fontSize: fontSize, color: context.appColors.mutedText);
}

TextStyle errorToolTextStyle(BuildContext context, {double? fontSize}) {
  return TextStyle(fontSize: fontSize, color: context.appColors.error);
}

class JsonToolStatus {
  const JsonToolStatus({this.summary, this.error});

  final String? summary;
  final String? error;

  static const empty = JsonToolStatus();

  bool get isValid => summary != null && error == null;
  bool get hasMessage => summary != null || error != null;
}

JsonCompareSummary compareJsonSessions(
  JsonToolSession left,
  JsonToolSession right,
  JsonCompareMode mode,
) {
  final leftText = mode == JsonCompareMode.normalized
      ? normalizedJson(left.inputText)
      : left.inputText;
  final rightText = mode == JsonCompareMode.normalized
      ? normalizedJson(right.inputText)
      : right.inputText;
  final changed = changedLineSets(leftText, rightText);
  return JsonCompareSummary(
    mode: mode,
    differenceCount: max(changed.$1.length, changed.$2.length),
    leftChangedLines: changed.$1,
    rightChangedLines: changed.$2,
  );
}

String normalizedJson(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
  } catch (_) {
    return value;
  }
}

(Set<int>, Set<int>) changedLineSets(String left, String right) {
  final leftLines = const LineSplitter().convert(left);
  final rightLines = const LineSplitter().convert(right);
  final count = max(leftLines.length, rightLines.length);
  final leftChanged = <int>{};
  final rightChanged = <int>{};
  for (var i = 0; i < count; i++) {
    final leftLine = i < leftLines.length ? leftLines[i] : null;
    final rightLine = i < rightLines.length ? rightLines[i] : null;
    if (leftLine != rightLine) {
      if (i < leftLines.length) leftChanged.add(i + 1);
      if (i < rightLines.length) rightChanged.add(i + 1);
    }
  }
  return (leftChanged, rightChanged);
}

class JsonSplitEditors extends StatelessWidget {
  const JsonSplitEditors({
    super.key,
    required this.inputController,
    required this.outputController,
    required this.inputScrollController,
    required this.outputScrollController,
    required this.inputMarkedLines,
    required this.inputRatio,
    required this.onInputRatioChanged,
    required this.onInputChanged,
    required this.inputActions,
    required this.outputActions,
    this.inputPlaceholder = 'Paste JSON...',
    this.outputPlaceholder = 'Formatted JSON...',
    this.showInputHeader = true,
    this.showOutputHeader = true,
    this.inputOverlay,
    this.outputOverlay,
    this.horizontal = false,
    this.outputSoftWrap = true,
    this.inputSoftWrap = true,
  });

  final TextEditingController inputController;
  final TextEditingController outputController;
  final ScrollController inputScrollController;
  final ScrollController outputScrollController;
  final Set<int> inputMarkedLines;
  final double inputRatio;
  final ValueChanged<double> onInputRatioChanged;
  final ValueChanged<String> onInputChanged;
  final List<Widget> inputActions;
  final List<Widget> outputActions;
  final String inputPlaceholder;
  final String outputPlaceholder;
  final bool showInputHeader;
  final bool showOutputHeader;
  final Widget? inputOverlay;
  final Widget? outputOverlay;
  final bool horizontal;
  final bool outputSoftWrap;
  final bool inputSoftWrap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (horizontal) {
          const splitterWidth = 6.0;
          final available = max(0.0, constraints.maxWidth - splitterWidth);
          final minPane = min(220.0, available / 2);
          final maxInputWidth = max(minPane, available - minPane);
          final inputWidth = (available * inputRatio)
              .clamp(minPane, maxInputWidth)
              .toDouble();
          final outputWidth = max(0.0, available - inputWidth);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: inputWidth,
                child: EditorPane(
                  label: 'Input',
                  actions: inputActions,
                  placeholder: inputPlaceholder,
                  controller: inputController,
                  onChanged: onInputChanged,
                  scrollController: inputScrollController,
                  markedLines: inputMarkedLines,
                  showHeader: showInputHeader,
                  overlay: inputOverlay,
                  softWrap: inputSoftWrap,
                ),
              ),
              EditorSplitter(
                horizontal: true,
                onDrag: (delta) {
                  if (available <= 0) return;
                  onInputRatioChanged(
                    (inputRatio + delta.dx / available).clamp(0.2, 0.8),
                  );
                },
              ),
              SizedBox(
                width: outputWidth,
                child: EditorPane(
                  label: 'Output',
                  actions: outputActions,
                  placeholder: outputPlaceholder,
                  readOnly: true,
                  controller: outputController,
                  scrollController: outputScrollController,
                  showHeader: showOutputHeader,
                  overlay: outputOverlay,
                  softWrap: outputSoftWrap,
                ),
              ),
            ],
          );
        }

        const splitterHeight = 6.0;
        final available = max(0.0, constraints.maxHeight - splitterHeight);
        final minPane = min(160.0, available / 2);
        final maxInputHeight = max(minPane, available - minPane);
        final inputHeight = (available * inputRatio)
            .clamp(minPane, maxInputHeight)
            .toDouble();
        final outputHeight = max(0.0, available - inputHeight);

        return Column(
          children: [
            SizedBox(
              height: inputHeight,
              child: EditorPane(
                label: 'Input',
                actions: inputActions,
                placeholder: inputPlaceholder,
                controller: inputController,
                onChanged: onInputChanged,
                scrollController: inputScrollController,
                markedLines: inputMarkedLines,
                showHeader: showInputHeader,
                overlay: inputOverlay,
                softWrap: inputSoftWrap,
              ),
            ),
            JsonEditorSplitter(
              onDrag: (delta) {
                if (available <= 0) return;
                onInputRatioChanged(
                  (inputRatio + delta.dy / available).clamp(0.2, 0.8),
                );
              },
            ),
            SizedBox(
              height: outputHeight,
              child: EditorPane(
                label: 'Output',
                actions: outputActions,
                placeholder: outputPlaceholder,
                readOnly: true,
                controller: outputController,
                scrollController: outputScrollController,
                showHeader: showOutputHeader,
                overlay: outputOverlay,
                softWrap: outputSoftWrap,
              ),
            ),
          ],
        );
      },
    );
  }
}

class JsonEditorSplitter extends StatelessWidget {
  const JsonEditorSplitter({super.key, required this.onDrag});

  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return EditorSplitter(horizontal: false, onDrag: onDrag);
  }
}

class JsonValidationResult {
  const JsonValidationResult.valid(this.info) : error = null, isValid = true;
  const JsonValidationResult.invalid(this.error)
    : info = null,
      isValid = false;

  final bool isValid;
  final JsonValidationInfo? info;
  final JsonValidationError? error;
}

class JsonValidationError {
  const JsonValidationError({
    required this.message,
    required this.line,
    required this.column,
    this.context,
  });

  final String message;
  final int line;
  final int column;
  final String? context;

  String get description {
    var desc = 'Line $line, Column $column: $message';
    if (context != null && context!.isNotEmpty) {
      desc += '\n  -> $context';
    }
    return desc;
  }
}

// ignore: unused_element
JsonValidationResult validateJson(String json, {bool strict = false}) {
  final trimmed = json.trim();
  if (trimmed.isEmpty) {
    return const JsonValidationResult.invalid(
      JsonValidationError(message: 'Empty input', line: 1, column: 1),
    );
  }

  if (strict) {
    final strictError = checkStrictCompliance(trimmed);
    if (strictError != null) {
      return JsonValidationResult.invalid(strictError);
    }
  }

  try {
    final decoded = jsonDecode(trimmed);
    final info = analyzeJson(decoded, utf8.encode(trimmed).length);
    return JsonValidationResult.valid(info);
  } on FormatException catch (e) {
    final offset = e.offset ?? 0;
    final position = positionFromIndex(offset, trimmed);
    final context = extractContext(position.line, position.column, trimmed);
    final message = e.message;
    return JsonValidationResult.invalid(
      JsonValidationError(
        message: message,
        line: position.line,
        column: position.column,
        context: context,
      ),
    );
  } catch (e) {
    return const JsonValidationResult.invalid(
      JsonValidationError(message: 'Invalid JSON', line: 1, column: 1),
    );
  }
}

String? extractContext(int line, int column, String json) {
  final lines = json.split('\n');
  if (line <= 0 || line > lines.length) return null;
  final errorLine = lines[line - 1].trim();
  if (errorLine.length <= 60) return errorLine;
  final start = max(0, column - 30);
  final end = min(errorLine.length, column + 30);
  var snippet = errorLine.substring(start, end);
  if (start > 0) snippet = '...$snippet';
  if (end < errorLine.length) snippet = '$snippet...';
  return snippet;
}

JsonValidationError? checkStrictCompliance(String json) {
  final chars = json.split('');
  var inString = false;
  var lastNonWhitespace = ' ';
  var line = 1;
  var column = 1;
  var i = 0;
  while (i < chars.length) {
    final char = chars[i];
    if (char == '\n') {
      line += 1;
      column = 1;
    } else {
      column += 1;
    }

    if (char == '"' && (i == 0 || chars[i - 1] != '\\')) {
      inString = !inString;
      lastNonWhitespace = char;
      i += 1;
      continue;
    }

    if (inString) {
      i += 1;
      continue;
    }

    if (char == '/' &&
        i + 1 < chars.length &&
        (chars[i + 1] == '/' || chars[i + 1] == '*')) {
      return JsonValidationError(
        message: 'Comments are not allowed in JSON',
        line: line,
        column: column - 1,
      );
    }

    if ((char == '}' || char == ']') && lastNonWhitespace == ',') {
      return JsonValidationError(
        message: 'Trailing commas are not allowed in JSON',
        line: line,
        column: column - 1,
      );
    }

    if (char == "'") {
      return JsonValidationError(
        message: 'Single quotes are not allowed, use double quotes',
        line: line,
        column: column - 1,
      );
    }

    if (!RegExp(r'\s').hasMatch(char)) {
      lastNonWhitespace = char;
    }

    i += 1;
  }
  return null;
}

class CompactCheck extends StatelessWidget {
  const CompactCheck({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: (next) => onChanged(next ?? value),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class HtmlRenderedPreview extends StatefulWidget {
  const HtmlRenderedPreview({super.key, required this.html, required this.overlay});

  final String html;
  final Widget overlay;

  @override
  State<HtmlRenderedPreview> createState() => HtmlRenderedPreviewState();
}

class HtmlRenderedPreviewState extends State<HtmlRenderedPreview> {
  WebViewController? _controller;
  Object? _webViewError;
  Timer? _reloadTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void didUpdateWidget(covariant HtmlRenderedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _scheduleLoad();
    }
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    super.dispose();
  }

  void _initWebView() {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled);
      // macOS WKWebView has no `opaque`/background-color setter, so
      // setBackgroundColor throws UnimplementedError there. The preview
      // container already paints an opaque white surface, so skip it.
      if (!Platform.isMacOS) {
        controller.setBackgroundColor(Colors.transparent);
      }
      _controller = controller;
      _loadHtml();
    } catch (error) {
      _webViewError = error;
    }
  }

  void _scheduleLoad() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 180), _loadHtml);
  }

  Future<void> _loadHtml() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.loadHtmlString(previewDocument(widget.html));
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      key: const ValueKey('html-rendered-preview'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appColors.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: widget.html.trim().isEmpty
                ? Center(
                    child: Text(
                      'Preview rendered HTML here...',
                      style: TextStyle(color: appColors.mutedText),
                    ),
                  )
                : _controller == null
                ? HtmlPreviewFallback(html: widget.html, error: _webViewError)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: WebViewWidget(controller: _controller!),
                  ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: widget.overlay,
            ),
          ),
        ],
      ),
    );
  }
}

class HtmlPreviewFallback extends StatelessWidget {
  const HtmlPreviewFallback({super.key, required this.html, required this.error});

  final String html;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final text = plainTextFromHtml(html);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: SelectableText(
        text.isEmpty ? 'Preview unavailable: $error' : text,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 14,
          height: 1.45,
        ),
      ),
    );
  }
}

String previewDocument(String html) {
  final trimmed = html.trim();
  if (trimmed.isEmpty) return previewShell('');
  if (RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed;
  }
  return previewShell(trimmed);
}

String previewShell(String body) {
  return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
html, body {
  margin: 0;
  padding: 0;
  background: #ffffff;
  color: #111827;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 14px;
  line-height: 1.5;
}
body { padding: 20px; }
h1, h2, h3, h4, h5, h6 {
  margin: 1.1em 0 0.45em;
  line-height: 1.2;
  font-weight: 700;
}
h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
h1 { font-size: 2rem; padding-bottom: 0.35em; border-bottom: 1px solid #e5e7eb; }
h2 { font-size: 1.5rem; padding-bottom: 0.25em; border-bottom: 1px solid #edf0f3; }
h3 { font-size: 1.18rem; }
p { margin: 0 0 1em; }
ul, ol { margin: 0 0 1em 1.35em; padding: 0; }
li { margin: 0.25em 0; }
img, video, canvas, svg { max-width: 100%; height: auto; }
.markdown-table-scroll { overflow-x: auto; margin: 1em 0; }
table { border-collapse: collapse; width: 100%; min-width: 560px; }
td, th {
  border: 1px solid #d1d5db;
  padding: 8px 10px;
  text-align: left;
  vertical-align: top;
}
th { background: #f3f4f6; font-weight: 700; }
tbody tr:nth-child(even) td { background: #fafafa; }
pre, code, kbd, samp {
  font-family: Menlo, Consolas, monospace;
  background: #f3f4f6;
  border-radius: 4px;
}
code { padding: 2px 4px; }
pre { padding: 12px; overflow: auto; }
pre code { padding: 0; background: transparent; }
blockquote {
  margin-left: 0;
  padding-left: 14px;
  border-left: 3px solid #d1d5db;
  color: #4b5563;
}
a { color: #2563eb; }
</style>
</head>
<body>
$body
</body>
</html>
''';
}

String plainTextFromHtml(String html) {
  final withoutScripts = html
      .replaceAll(
        RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
        '',
      );
  final withBreaks = withoutScripts.replaceAll(
    RegExp(
      r'</?(p|div|section|article|h[1-6]|li|br|tr)\b[^>]*>',
      caseSensitive: false,
    ),
    '\n',
  );
  return decodeHtmlEntities(withBreaks.replaceAll(RegExp(r'<[^>]+>'), ' '))
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s+'), '\n')
      .trim();
}

String decodeHtmlEntities(String input) {
  return input.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (
    match,
  ) {
    final entity = match.group(1) ?? '';
    if (entity.startsWith('#x') || entity.startsWith('#X')) {
      final value = int.tryParse(entity.substring(2), radix: 16);
      return value == null ? match.group(0)! : String.fromCharCode(value);
    }
    if (entity.startsWith('#')) {
      final value = int.tryParse(entity.substring(1));
      return value == null ? match.group(0)! : String.fromCharCode(value);
    }
    return switch (entity) {
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      'nbsp' => ' ',
      _ => match.group(0)!,
    };
  });
}

class RenderedPreviewPane extends StatelessWidget {
  const RenderedPreviewPane({
    super.key,
    required this.label,
    required this.html,
    required this.badge,
  });

  final String label;
  final String html;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                PreviewBadge(label: badge),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: HtmlRenderedPreview(
            html: html,
            overlay: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class PreviewBadge extends StatelessWidget {
  const PreviewBadge({super.key, required this.label});

  final String label;

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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: appColors.editorText,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

extension FirstOrNullExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class FileDropTargetRegion extends StatefulWidget {
  const FileDropTargetRegion({
    super.key,
    required this.targetId,
    required this.onDropped,
    required this.child,
  });

  final String targetId;
  final FileDropHandler onDropped;
  final Widget child;

  @override
  State<FileDropTargetRegion> createState() => FileDropTargetRegionState();
}

class FileDropTargetRegionState extends State<FileDropTargetRegion> {
  final GlobalKey _dropKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _registerTarget();
  }

  @override
  void didUpdateWidget(covariant FileDropTargetRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetId != widget.targetId ||
        oldWidget.onDropped != widget.onDropped) {
      FileDropService.unregisterTarget(oldWidget.targetId);
      _registerTarget();
    }
  }

  @override
  void dispose() {
    FileDropService.unregisterTarget(widget.targetId);
    super.dispose();
  }

  void _registerTarget() {
    FileDropService.registerTarget(
      widget.targetId,
      key: _dropKey,
      handler: widget.onDropped,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => FileDropService.setActiveTarget(widget.targetId),
      onExit: (_) => FileDropService.setActiveTarget(null),
      child: KeyedSubtree(key: _dropKey, child: widget.child),
    );
  }
}

class SourceFileControls extends StatelessWidget {
  const SourceFileControls({
    super.key,
    required this.onPickFile,
    this.fileName,
    this.tooltip = 'Choose file',
  });

  final VoidCallback onPickFile;
  final String? fileName;
  final String tooltip;

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
            if (fileName != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  fileName!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: appColors.mutedText, fontSize: 11),
                ),
              ),
              const SizedBox(width: 6),
            ],
            ToolIconButton(
              icon: Icons.insert_drive_file,
              tooltip: tooltip,
              onPressed: onPickFile,
            ),
          ],
        ),
      ),
    );
  }
}

String friendlyFileReadError(Object error) {
  if (error is FileSystemException) {
    final message = error.message.isEmpty
        ? 'Could not read file.'
        : error.message;
    return error.path == null ? message : '$message: ${error.path}';
  }
  return 'Could not read file: $error';
}

class MarkupBeautifyMinifyView extends StatefulWidget {
  const MarkupBeautifyMinifyView({
    super.key,
    required this.language,
    required this.beautify,
    required this.minify,
    this.showComments = false,
  });

  final String language;
  final String Function(String source, String indent) beautify;
  final String Function(String source, bool keepComments) minify;
  final bool showComments;

  @override
  State<MarkupBeautifyMinifyView> createState() =>
      MarkupBeautifyMinifyViewState();
}

class MarkupBeautifyMinifyViewState extends State<MarkupBeautifyMinifyView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _format = 'Beautify';
  String _indent = '2 spaces';
  bool _keepComments = true;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    _output.text = _format == 'Minify'
        ? widget.minify(text, _keepComments)
        : widget.beautify(text, indentFor(_indent));
    setState(() {});
  }

  void _setSample() {
    setState(() {
      _input.text = widget.language == 'XML'
          ? '<?xml version="1.0"?><note><to>DevUtils</to><body>Hello<br/>World</body></note>'
          : 'class User\ndef initialize(name)\n@name = name\nend\ndef greet\nif @name\nputs "Hello #{@name}"\nelse\nputs "Hello"\nend\nend\nend';
    });
    _run();
  }

  void _clear() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SmallDropdown(
          items: const ['Beautify', 'Minify'],
          initialValue: _format,
          onChanged: (value) {
            setState(() => _format = value);
            _run();
          },
        ),
        if (_format == 'Beautify') ...[
          const SizedBox(width: 6),
          SmallDropdown(
            items: const ['2 spaces', '4 spaces', 'Tabs'],
            initialValue: _indent,
            onChanged: (value) {
              setState(() => _indent = value);
              _run();
            },
          ),
        ],
        if (_format == 'Minify' && widget.showComments) ...[
          const SizedBox(width: 6),
          SmallDropdown(
            items: const ['Keep comments', 'Strip comments'],
            initialValue: _keepComments ? 'Keep comments' : 'Strip comments',
            onChanged: (value) {
              setState(() => _keepComments = value == 'Keep comments');
              _run();
            },
          ),
        ],
      ],
    );

    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clear),
      ],
      outputActions: [
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
      onInputChanged: (_) => _run(),
      inputPlaceholder: 'Paste ${widget.language} here...',
      outputPlaceholder: 'Output...',
      showInputHeader: false,
      showOutputHeader: false,
      outputOverlay: controls,
    );
  }
}

class InlineTextField extends StatelessWidget {
  const InlineTextField({
    super.key,
    this.hintText,
    this.width,
    this.controller,
    this.onChanged,
  });

  final String? hintText;
  final double? width;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return SizedBox(
      width: width,
      child: Container(
        decoration: toolSurfaceDecoration(context, radius: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            border: InputBorder.none,
            isDense: true,
            hintStyle: TextStyle(color: appColors.mutedText),
          ),
          style: TextStyle(color: appColors.editorText),
        ),
      ),
    );
  }
}

class JsonCompareSummary {
  const JsonCompareSummary({
    required this.mode,
    required this.differenceCount,
    required this.leftChangedLines,
    required this.rightChangedLines,
  });

  final JsonCompareMode mode;
  final int differenceCount;
  final Set<int> leftChangedLines;
  final Set<int> rightChangedLines;

  String get label {
    if (differenceCount == 0) return 'No differences';
    return '$differenceCount ${differenceCount == 1 ? 'difference' : 'differences'}';
  }
}

class JsonToolSession {
  JsonToolSession();

  final TextEditingController input = TextEditingController();
  final TextEditingController output = TextEditingController();
  final ScrollController inputScroll = ScrollController();
  final ScrollController outputScroll = ScrollController();
  final ValueNotifier<JsonToolStatus> status = ValueNotifier<JsonToolStatus>(
    JsonToolStatus.empty,
  );

  String indent = '2 spaces';
  int _formatToken = 0;

  String get inputText => input.text;
  String get outputText => output.text;

  Future<void> format() async {
    final text = input.text.trim();
    if (text.isEmpty) {
      output.text = '';
      status.value = JsonToolStatus.empty;
      return;
    }
    final token = ++_formatToken;
    final indentString = indentFor(indent);
    JsonFormatOutcome outcome;
    try {
      // Large documents are decoded + re-encoded off the UI thread so the
      // app stays responsive (a 26MB file would otherwise block for seconds).
      if (text.length > 200000) {
        outcome = await compute(formatJsonWorker, (text, indentString));
      } else {
        outcome = formatJsonSync(text, indentString);
      }
    } catch (e) {
      outcome = JsonFormatOutcome(error: e.toString());
    }
    if (token != _formatToken) return; // a newer format() superseded this one
    if (outcome.error != null) {
      output.text = '';
      status.value = JsonToolStatus(error: outcome.error);
    } else {
      output.text = outcome.output ?? '';
      status.value = JsonToolStatus(summary: outcome.summary);
    }
  }

  Future<void> pasteClipboard() async {
    input.text = await readClipboardText();
  }

  void setSample() {
    input.text = '{"name":"DevUtils","items":[1,2,3],"enabled":true}';
  }

  void clear() {
    input.clear();
    output.clear();
    status.value = JsonToolStatus.empty;
  }

  Future<void> copyOutput() async {
    await Clipboard.setData(ClipboardData(text: output.text));
  }

  void dispose() {
    input.dispose();
    output.dispose();
    inputScroll.dispose();
    outputScroll.dispose();
    status.dispose();
  }
}

enum JsonCompareMode { raw, normalized }

class JsonValidationInfo {
  const JsonValidationInfo({
    required this.rootType,
    required this.keyCount,
    required this.elementCount,
    required this.depth,
    required this.size,
  });

  final String rootType;
  final int? keyCount;
  final int? elementCount;
  final int depth;
  final int size;

  String get summary {
    final count = elementCount != null
        ? '${thousandsSep(elementCount!)} ${elementCount == 1 ? 'item' : 'items'}'
        : keyCount != null
        ? '${thousandsSep(keyCount!)} ${keyCount == 1 ? 'key' : 'keys'}'
        : null;
    final parts = <String>[
      rootType,
      if (count != null) count,
      humanJsonSize(size),
      'depth $depth',
    ];
    return parts.join('  ·  ');
  }
}

JsonValidationInfo analyzeJson(dynamic value, int size) {
  final rootType = jsonType(value);
  final depth = jsonDepth(value);
  int? keyCount;
  int? elementCount;
  if (value is Map) {
    keyCount = value.length;
  } else if (value is List) {
    elementCount = value.length;
  }
  return JsonValidationInfo(
    rootType: rootType,
    keyCount: keyCount,
    elementCount: elementCount,
    depth: depth,
    size: size,
  );
}

({int line, int column}) positionFromIndex(int index, String input) {
  var line = 1;
  var column = 1;
  var current = 0;
  for (final rune in input.runes) {
    if (current >= index) break;
    final char = String.fromCharCode(rune);
    if (char == '\n') {
      line += 1;
      column = 1;
    } else {
      column += 1;
    }
    current += 1;
  }
  return (line: line, column: column);
}

enum AntiBotCategory { antiBot, captcha, fingerprinting, waf }

enum AntiBotPatternType { cookie, header, script, html, js, url, meta }

enum AntiBotRiskLevel { none, low, medium, high, extreme }

class JsonFormatOutcome {
  const JsonFormatOutcome({this.output, this.summary, this.error});
  final String? output;
  final String? summary;
  final String? error;
}

// Top-level so it can run inside an isolate via `compute`.
JsonFormatOutcome formatJsonWorker((String, String) args) {
  return formatJsonSync(args.$1, args.$2);
}

JsonFormatOutcome formatJsonSync(String text, String indentString) {
  // jsonDecode is the source of truth for validity: it rejects real comments
  // and trailing commas with a precise offset, and (unlike a naive `//` scan)
  // correctly accepts `//` inside string values such as https:// URLs.
  try {
    final decoded = jsonDecode(text);
    final output = JsonEncoder.withIndent(indentString).convert(decoded);
    final info = analyzeJson(decoded, text.length);
    return JsonFormatOutcome(output: output, summary: info.summary);
  } on FormatException catch (e) {
    final position = positionFromIndex(e.offset ?? 0, text);
    return JsonFormatOutcome(
      error: 'Line ${position.line}, column ${position.column}: ${e.message}',
    );
  } catch (_) {
    return const JsonFormatOutcome(error: 'Invalid JSON');
  }
}

String thousandsSep(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String humanJsonSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String jsonType(dynamic value) {
  if (value is Map) return 'object';
  if (value is List) return 'array';
  if (value is String) return 'string';
  if (value is num) return 'number';
  if (value is bool) return 'boolean';
  if (value == null) return 'null';
  return 'string';
}

int jsonDepth(dynamic value, [int current = 1]) {
  if (value is Map) {
    if (value.isEmpty) return current;
    final depths = value.values.map((entry) => jsonDepth(entry, current + 1));
    return depths.reduce(max);
  }
  if (value is List) {
    if (value.isEmpty) return current;
    final depths = value.map((entry) => jsonDepth(entry, current + 1));
    return depths.reduce(max);
  }
  return current;
}
