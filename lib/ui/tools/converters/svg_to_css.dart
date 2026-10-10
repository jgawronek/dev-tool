/// SVG to CSS converter tool view.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../services/file_dialog_service.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _SvgToCssView extends StatefulWidget {
  const _SvgToCssView();

  @override
  State<_SvgToCssView> createState() => _SvgToCssViewState();
}

class _SvgToCssViewState extends State<_SvgToCssView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  late final String _dropTargetScope = identityHashCode(this).toRadixString(16);
  String _format = 'URL Encoded';
  String? _sourceFileName;
  String? _error;

  String get _dropTargetId => 'svg-source-file-$_dropTargetScope';

  @override
  void dispose() {
    FileDropService.unregisterTarget(_dropTargetId);
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final svg = _input.text.trim();
    if (svg.isEmpty) {
      _output.clear();
      setState(() {});
      return;
    }
    if (!_looksLikeSvg(svg)) {
      _output.clear();
      _error = 'Input does not look like SVG (expected a root <svg> element).';
      setState(() {});
      return;
    }
    _error = null;
    final data = _format == 'URL Encoded' ? Uri.encodeComponent(svg) : svg;
    _output.text = "background-image: url('data:image/svg+xml,$data');";
    setState(() {});
  }

  /// Cheap structural check: an SVG document must have a root `<svg>`
  /// element. Namespaced or prefixed tags are accepted.
  bool _looksLikeSvg(String source) {
    return RegExp(
      r'<[\w.-]*:?\bsvg[\s>]',
      caseSensitive: false,
    ).hasMatch(source);
  }

  Future<void> _pickSvgFile() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: const ['svg'],
    );
    if (path == null || !mounted) return;
    await _loadSvgFile(path);
  }

  Future<void> _loadSvgFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw const FileSystemException('SVG file does not exist');
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
    setState(() {
      _sourceFileName = null;
      _error = null;
      _input.text =
          '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">\n'
          '  <circle cx="32" cy="32" r="28" fill="#5CC07F" />\n'
          '</svg>';
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(_error!, style: errorToolTextStyle(context)),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: buildAdaptiveSplit(
              initialRatio: 0.68,
              first: ResizableSplit(
                horizontal: false,
                initialRatio: 0.52,
                first: FileDropTargetRegion(
                  targetId: _dropTargetId,
                  onDropped: (paths) {
                    if (paths.isNotEmpty) unawaited(_loadSvgFile(paths.first));
                  },
                  child: EditorPane(
                    label: 'Source',
                    actions: [],
                    controller: _input,
                    onChanged: (_) {
                      _sourceFileName = null;
                      _run();
                    },
                    placeholder:
                        'Drop an .svg file here or paste SVG source...',
                    showHeader: true,
                    enableFileDrop: false,
                    overlay: SourceFileControls(
                      onPickFile: _pickSvgFile,
                      fileName: _sourceFileName,
                      tooltip: 'Choose SVG file',
                    ),
                  ),
                ),
                second: EditorPane(
                  label: 'CSS',
                  actions: const [],
                  controller: _output,
                  readOnly: true,
                  placeholder: 'Output...',
                  showHeader: true,
                  overlay: SmallDropdown(
                    items: const ['URL Encoded', 'Raw'],
                    initialValue: _format,
                    onChanged: (value) {
                      setState(() => _format = value);
                      _run();
                    },
                  ),
                ),
              ),
              second: _SvgPreviewPane(svg: _input.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _SvgPreviewPane extends StatelessWidget {
  const _SvgPreviewPane({required this.svg});

  final String svg;

  @override
  Widget build(BuildContext context) {
    final trimmed = svg.trim();
    return HtmlRenderedPreview(html: trimmed, overlay: const SizedBox.shrink());
  }
}

Widget buildSvgToCss() {
  return const _SvgToCssView();
}
