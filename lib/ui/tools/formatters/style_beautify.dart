/// HTML/CSS/JS/RB beautify/minify tool views.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../services/file_dialog_service.dart';
import '../../../services/javascript_code_service.dart';
import '../../../services/ruby_format_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

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
      inputActions: [ToolButton(label: 'Go', onPressed: _run)],
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

  int _runId = 0;
  bool _processing = false;

  Future<void> _run() async {
    final runId = ++_runId;
    final text = _input.text;
    if (text.trim().isEmpty) {
      setState(() {
        _output.clear();
        _processing = false;
      });
      return;
    }
    setState(() => _processing = true);
    try {
      final output = await JavascriptCodeService.process(
        text,
        'CSS $_format',
        indentation: _indent,
      );
      if (!mounted || runId != _runId) return;
      setState(() {
        _output.text = output;
        _processing = false;
      });
    } catch (_) {
      if (!mounted || runId != _runId) return;
      setState(() {
        _output.text = 'Could not format CSS. Try again.';
        _processing = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final controls = _HtmlFormatControls(
      format: _format,
      processing: _processing,
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
      inputActions: [],
      outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
      inputOverlay: SourceFileControls(
        onPickFile: _pickFile,
        fileName: _sourceFileName,
        tooltip: 'Choose ${widget.language} file',
      ),
      outputOverlay: controls,
      showInputHeader: true,
      showOutputHeader: true,
      inputDropTargetId: _dropTargetId,
      onInputDropped: (paths) {
        if (paths.isNotEmpty) unawaited(_loadFile(paths.first));
      },
    );

    if (_error == null) {
      return ToolSampleAction(onPressed: _setSample, child: editors);
    }
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error!, style: errorToolTextStyle(context)),
          const SizedBox(height: 8),
          Expanded(child: editors),
        ],
      ),
    );
  }
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

  int _runId = 0;
  bool _processing = false;

  Future<void> _run() async {
    final runId = ++_runId;
    final text = _input.text;
    if (text.trim().isEmpty || _format == 'Preview') {
      setState(() {
        _output.clear();
        _processing = false;
      });
      return;
    }
    setState(() => _processing = true);
    try {
      final output = await JavascriptCodeService.process(
        text,
        'HTML $_format',
        indentation: _indent,
      );
      if (!mounted || runId != _runId) return;
      setState(() {
        _output.text = output;
        _processing = false;
      });
    } catch (_) {
      if (!mounted || runId != _runId) return;
      setState(() {
        _output.text = 'Could not format HTML. Try again.';
        _processing = false;
      });
    }
  }

  void _setSample() {
    const sample = '<div class="card">\n  <h1>Hello</h1>\n</div>';
    setState(() => _input.text = sample);
    _run();
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    final outputControls = _HtmlFormatControls(
      format: _format,
      processing: _processing,
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

    return ToolSampleAction(
      onPressed: _setSample,
      child: buildAdaptiveSplit(
        first: EditorPane(
          label: 'Input',
          actions: [],
          controller: _input,
          onChanged: (_) => _run(),
          placeholder: 'Paste HTML here...',
          showHeader: true,
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
                showHeader: true,
                overlay: outputControls,
              ),
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
    this.processing = false,
  });

  final bool processing;
  final String format;
  final String indent;
  final bool showIndent;
  final ValueChanged<String> onFormatChanged;
  final ValueChanged<String> onIndentChanged;
  final List<String> formats;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (processing) ...[
          Semantics(
            label: 'Formatting code',
            child: const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(width: 6),
        ],
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
    );
  }
}

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

  int _runId = 0;
  bool _processing = false;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final runId = ++_runId;
    final text = _input.text;
    final format = _format;
    if (text.trim().isEmpty) {
      setState(() {
        _processing = false;
        _output.clear();
      });
      return;
    }
    setState(() => _processing = true);
    try {
      final output = switch (format) {
        'Minify' ||
        'Verify' => await JavascriptCodeService.process(text, format),
        'Obfuscate' => _obfuscateJs(
          await JavascriptCodeService.process(text, 'Obfuscate'),
        ),
        _ => await JavascriptCodeService.process(
          text,
          'Beautify',
          indentation: _indent,
        ),
      };
      if (!mounted || runId != _runId) return;
      setState(() {
        _output.text = output;
        _processing = false;
      });
    } catch (error) {
      if (!mounted || runId != _runId) return;
      final message = error is PlatformException
          ? error.message
          : error is MissingPluginException
          ? 'The offline syntax parser requires the current macOS app build.'
          : error is FormatException
          ? error.message
          : 'Could not process this code. Try again.';
      setState(() {
        _output.text = message ?? 'Could not process this code. Try again.';
        _processing = false;
      });
    }
  }

  /// Reversible Base64 obfuscation; this is not encryption.
  String _obfuscateJs(String text) {
    final encoded = base64.encode(utf8.encode(text));
    return [
      '(function(){',
      '  const _d = typeof atob === "function"',
      '    ? (s) => new TextDecoder().decode(Uint8Array.from(atob(s), c => c.charCodeAt(0)))',
      '    : (s) => Buffer.from(s, "base64").toString("utf8");',
      '  eval(_d("$encoded"));',
      '})();',
    ].join('\n');
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

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: buildSplitEditors(
        inputActions: [ToolButton(label: 'Go', onPressed: _run)],
        outputActions: [
          if (_processing)
            Semantics(
              label: 'Processing code',
              child: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Operation',
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
      ),
    );
  }
}

// Re-indents Ruby source by keyword/`end` block structure. Each line is
// trimmed and re-indented from a running level, so it works on flat input.
String _beautifyRuby(String source, String indent) =>
    RubyFormatService.process(source, indent: indent);

String _minifyRuby(String source, bool keepComments) =>
    RubyFormatService.process(source, keepComments: keepComments);

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
      showComments: true,
    );
  }
  return _SimplePassThroughView(
    inputPlaceholder: 'Paste $language here...',
    showIndent: true,
  );
}
