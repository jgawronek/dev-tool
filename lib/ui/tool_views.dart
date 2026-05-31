import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/digests/md2.dart';
import 'package:pointycastle/digests/md4.dart';
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha224.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha384.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/digests/ripemd128.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/ripemd320.dart';
import 'package:pointycastle/digests/tiger.dart';
import 'package:pointycastle/digests/whirlpool.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/block/modes/cfb.dart';
import 'package:pointycastle/block/modes/ofb.dart';
import 'package:pointycastle/stream/ctr.dart';
import 'package:pointycastle/stream/salsa20.dart';
import 'package:pointycastle/stream/chacha20.dart';
import 'package:pointycastle/stream/rc4_engine.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/block/rc2_engine.dart';
import 'package:pointycastle/api.dart' as pc;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yaml/yaml.dart';

import '../data/mime_types.dart';
import '../services/file_dialog_service.dart';
import '../services/firewall_fingerprint_service.dart';
import '../services/hash_lookup_service.dart';
import '../services/app_appearance_service.dart';
import '../services/local_llm_service.dart';
import '../services/local_server_service.dart';
import '../services/network_scanner_service.dart';
import '../services/payload_embedding_service.dart';
import '../services/php_to_js_service.dart';
import '../services/port_scanner_service.dart';
import '../services/subdomain_lookup_service.dart';
import '../services/subdomain_takeover_service.dart';
import '../state/tool_state_scope.dart';
import 'app_colors.dart';
import 'widgets.dart';

Widget buildSplitEditors({
  String inputLabel = 'Input',
  String outputLabel = 'Output',
  List<Widget> inputActions = const [],
  List<Widget> outputActions = const [],
  bool outputReadOnly = true,
  String inputPlaceholder = 'Enter text...',
  String outputPlaceholder = 'Output...',
  TextEditingController? inputController,
  TextEditingController? outputController,
  ValueChanged<String>? onInputChanged,
  bool horizontal = false,
  VoidCallback? onInputSubmit,
  ScrollController? inputScrollController,
  ScrollController? outputScrollController,
  Set<int> inputMarkedLines = const <int>{},
  Set<int> outputMarkedLines = const <int>{},
  bool showInputHeader = false,
  bool showOutputHeader = false,
  Widget? inputOverlay,
  Widget? outputOverlay,
  String? inputDropTargetId,
  FileDropHandler? onInputDropped,
}) {
  final liveInputChanged = onInputChanged ?? _goActionChanged(inputActions);
  final wrapsOwnDropTarget =
      inputDropTargetId != null && onInputDropped != null;
  Widget input = EditorPane(
    label: inputLabel,
    actions: inputActions,
    placeholder: inputPlaceholder,
    controller: inputController,
    onChanged: liveInputChanged,
    onSubmit: onInputSubmit,
    scrollController: inputScrollController,
    markedLines: inputMarkedLines,
    showHeader: showInputHeader,
    overlay: inputOverlay,
    // The built-in EditorPane drop would double-register with the explicit
    // wrapper below, so disable it when this helper owns the drop target.
    enableFileDrop: !wrapsOwnDropTarget,
  );
  if (inputDropTargetId != null && onInputDropped != null) {
    input = _FileDropTargetRegion(
      targetId: inputDropTargetId,
      onDropped: onInputDropped,
      child: input,
    );
  }
  final output = EditorPane(
    label: outputLabel,
    actions: outputActions,
    placeholder: outputPlaceholder,
    readOnly: outputReadOnly,
    controller: outputController,
    scrollController: outputScrollController,
    markedLines: outputMarkedLines,
    showHeader: showOutputHeader,
    overlay: outputOverlay,
  );
  return _ResizableSplit(horizontal: horizontal, first: input, second: output);
}

Widget buildVerticalEditors({
  String inputLabel = 'Input',
  String outputLabel = 'Output',
  List<Widget> inputActions = const [],
  List<Widget> outputActions = const [],
  bool outputReadOnly = true,
  String inputPlaceholder = 'Enter text...',
  String outputPlaceholder = 'Output...',
  TextEditingController? inputController,
  TextEditingController? outputController,
  ValueChanged<String>? onInputChanged,
  ScrollController? inputScrollController,
  ScrollController? outputScrollController,
  Set<int> inputMarkedLines = const <int>{},
  Set<int> outputMarkedLines = const <int>{},
  bool showInputHeader = false,
  bool showOutputHeader = false,
  Widget? inputOverlay,
  Widget? outputOverlay,
}) {
  return buildSplitEditors(
    inputLabel: inputLabel,
    outputLabel: outputLabel,
    inputActions: inputActions,
    outputActions: outputActions,
    outputReadOnly: outputReadOnly,
    inputPlaceholder: inputPlaceholder,
    outputPlaceholder: outputPlaceholder,
    inputController: inputController,
    outputController: outputController,
    onInputChanged: onInputChanged,
    inputScrollController: inputScrollController,
    outputScrollController: outputScrollController,
    inputMarkedLines: inputMarkedLines,
    outputMarkedLines: outputMarkedLines,
    showInputHeader: showInputHeader,
    showOutputHeader: showOutputHeader,
    inputOverlay: inputOverlay,
    outputOverlay: outputOverlay,
    horizontal: false,
  );
}

ValueChanged<String>? _goActionChanged(List<Widget> actions) {
  for (final action in actions) {
    if (action is ToolButton && action.label == 'Go') {
      final onPressed = action.onPressed;
      if (onPressed != null) return (_) => onPressed();
    }
  }
  return null;
}

class _ResizableSplit extends StatefulWidget {
  const _ResizableSplit({
    required this.horizontal,
    required this.first,
    required this.second,
    this.initialRatio = 0.5,
    this.minFirstExtent = 120,
    this.minSecondExtent = 120,
  });

  final bool horizontal;
  final Widget first;
  final Widget second;
  final double initialRatio;
  final double minFirstExtent;
  final double minSecondExtent;

  @override
  State<_ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<_ResizableSplit> {
  late double _firstRatio = widget.initialRatio.clamp(0.2, 0.8).toDouble();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const splitterExtent = 6.0;
        final maxExtent = widget.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final available = max(0.0, maxExtent - splitterExtent);
        final requestedFirst = min(widget.minFirstExtent, available);
        final requestedSecond = min(widget.minSecondExtent, available);
        final minTotal = requestedFirst + requestedSecond;
        final minScale = minTotal > available && minTotal > 0
            ? available / minTotal
            : 1.0;
        final minFirstExtent = requestedFirst * minScale;
        final minSecondExtent = requestedSecond * minScale;
        final lowerRatio = available <= 0 ? 0.5 : minFirstExtent / available;
        final upperRatio = available <= 0
            ? 0.5
            : max(lowerRatio, 1 - minSecondExtent / available);
        final effectiveRatio = _firstRatio
            .clamp(lowerRatio, upperRatio)
            .toDouble();
        final firstExtent = available * effectiveRatio;
        final secondExtent = max(0.0, available - firstExtent);

        void handleDrag(Offset delta) {
          if (available <= 0) return;
          final movement = widget.horizontal ? delta.dx : delta.dy;
          setState(() {
            _firstRatio = (_firstRatio + movement / available)
                .clamp(lowerRatio, upperRatio)
                .toDouble();
          });
        }

        if (widget.horizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: firstExtent, child: widget.first),
              _EditorSplitter(horizontal: true, onDrag: handleDrag),
              SizedBox(width: secondExtent, child: widget.second),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(height: firstExtent, child: widget.first),
            _EditorSplitter(horizontal: false, onDrag: handleDrag),
            SizedBox(height: secondExtent, child: widget.second),
          ],
        );
      },
    );
  }
}

class _EditorSplitter extends StatelessWidget {
  const _EditorSplitter({required this.horizontal, required this.onDrag});

  final bool horizontal;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        key: ValueKey(
          horizontal
              ? 'split-editor-horizontal-resize-handle'
              : 'split-editor-vertical-resize-handle',
        ),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDrag(details.delta),
        child: SizedBox(
          width: horizontal ? 6 : double.infinity,
          height: horizontal ? double.infinity : 6,
          child: Center(
            child: Container(
              width: horizontal ? 2 : 52,
              height: horizontal ? 52 : 2,
              decoration: BoxDecoration(
                color: appColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _indentFor(String value) {
  switch (value) {
    case '4 spaces':
      return '    ';
    case 'Tabs':
      return '\t';
    default:
      return '  ';
  }
}

String _bytesToHex(List<int> bytes, {bool lower = false}) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    final hex = byte.toRadixString(16).padLeft(2, '0');
    buffer.write(lower ? hex : hex.toUpperCase());
  }
  return buffer.toString();
}

int _colorComponent(double value) {
  return (value * 255.0).round().clamp(0, 255).toInt();
}

Future<String> _readClipboardText() async {
  final data = await Clipboard.getData('text/plain');
  return data?.text ?? '';
}

String _base64UrlNoPad(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

Uint8List _base64UrlDecode(String input) {
  final normalized = base64Url.normalize(input);
  return Uint8List.fromList(base64Url.decode(normalized));
}

BoxDecoration _toolSurfaceDecoration(
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

TextStyle _mutedToolTextStyle(BuildContext context, {double? fontSize}) {
  return TextStyle(fontSize: fontSize, color: context.appColors.mutedText);
}

TextStyle _errorToolTextStyle(BuildContext context, {double? fontSize}) {
  return TextStyle(fontSize: fontSize, color: context.appColors.error);
}

enum JsonCompareMode { raw, normalized }

class JsonToolStatus {
  const JsonToolStatus({this.summary, this.error});

  final String? summary;
  final String? error;

  static const empty = JsonToolStatus();

  bool get isValid => summary != null && error == null;
  bool get hasMessage => summary != null || error != null;
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
    final indentString = _indentFor(indent);
    JsonFormatOutcome outcome;
    try {
      // Large documents are decoded + re-encoded off the UI thread so the
      // app stays responsive (a 26MB file would otherwise block for seconds).
      if (text.length > 200000) {
        outcome = await compute(_formatJsonWorker, (text, indentString));
      } else {
        outcome = _formatJsonSync(text, indentString);
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
    input.text = await _readClipboardText();
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

class JsonFormatOutcome {
  const JsonFormatOutcome({this.output, this.summary, this.error});
  final String? output;
  final String? summary;
  final String? error;
}

// Top-level so it can run inside an isolate via `compute`.
JsonFormatOutcome _formatJsonWorker((String, String) args) {
  return _formatJsonSync(args.$1, args.$2);
}

JsonFormatOutcome _formatJsonSync(String text, String indentString) {
  // jsonDecode is the source of truth for validity: it rejects real comments
  // and trailing commas with a precise offset, and (unlike a naive `//` scan)
  // correctly accepts `//` inside string values such as https:// URLs.
  try {
    final decoded = jsonDecode(text);
    final output = JsonEncoder.withIndent(indentString).convert(decoded);
    final info = _analyzeJson(decoded, text.length);
    return JsonFormatOutcome(output: output, summary: info.summary);
  } on FormatException catch (e) {
    final position = _positionFromIndex(e.offset ?? 0, text);
    return JsonFormatOutcome(
      error: 'Line ${position.line}, column ${position.column}: ${e.message}',
    );
  } catch (_) {
    return const JsonFormatOutcome(error: 'Invalid JSON');
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

class JsonPanelCompareDetails {
  const JsonPanelCompareDetails({
    required this.summary,
    required this.changedLines,
    required this.linkedScroll,
  });

  final JsonCompareSummary summary;
  final Set<int> changedLines;
  final bool linkedScroll;
}

JsonCompareSummary compareJsonSessions(
  JsonToolSession left,
  JsonToolSession right,
  JsonCompareMode mode,
) {
  final leftText = mode == JsonCompareMode.normalized
      ? _normalizedJson(left.inputText)
      : left.inputText;
  final rightText = mode == JsonCompareMode.normalized
      ? _normalizedJson(right.inputText)
      : right.inputText;
  final changed = _changedLineSets(leftText, rightText);
  return JsonCompareSummary(
    mode: mode,
    differenceCount: max(changed.$1.length, changed.$2.length),
    leftChangedLines: changed.$1,
    rightChangedLines: changed.$2,
  );
}

String _normalizedJson(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
  } catch (_) {
    return value;
  }
}

(Set<int>, Set<int>) _changedLineSets(String left, String right) {
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

class _JsonFormatValidateView extends StatefulWidget {
  const _JsonFormatValidateView({this.session, this.compare});

  final JsonToolSession? session;
  final JsonPanelCompareDetails? compare;

  @override
  State<_JsonFormatValidateView> createState() =>
      _JsonFormatValidateViewState();
}

class _JsonFormatValidateViewState extends State<_JsonFormatValidateView> {
  late JsonToolSession _session;
  late bool _ownsSession;
  double _inputRatio = 0.5;
  bool _wrap = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.session == null;
    _session = widget.session ?? JsonToolSession();
  }

  @override
  void didUpdateWidget(covariant _JsonFormatValidateView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session && widget.session != null) {
      if (_ownsSession) _session.dispose();
      _ownsSession = false;
      _session = widget.session!;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_ownsSession) _session.dispose();
    super.dispose();
  }

  void _setIndent(String value) {
    setState(() {
      _session.indent = value;
      _session.format();
    });
  }

  void _formatLive(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _session.format);
  }

  void _setExample() {
    setState(() {
      _session.setSample();
      _session.format();
    });
  }

  void _clearSource() {
    setState(() => _session.clear());
  }

  @override
  Widget build(BuildContext context) {
    final compare = widget.compare;
    return Column(
      children: [
        if (compare != null) ...[
          _JsonCompareStrip(compare: compare),
          const SizedBox(height: 8),
        ],
        _JsonStatsHeader(statusListenable: _session.status),
        const SizedBox(height: 8),
        Expanded(
          child: _JsonSplitEditors(
            inputController: _session.input,
            outputController: _session.output,
            inputScrollController: _session.inputScroll,
            outputScrollController: _session.outputScroll,
            inputMarkedLines: compare?.changedLines ?? const <int>{},
            inputRatio: _inputRatio,
            onInputRatioChanged: (value) => setState(() => _inputRatio = value),
            onInputChanged: _formatLive,
            horizontal: true,
            inputSoftWrap: _wrap,
            outputSoftWrap: _wrap,
            inputActions: [
              ToolButton(label: 'Sample', onPressed: _setExample),
              ToolButton(label: 'Clear', onPressed: _clearSource),
            ],
            outputActions: const [],
            showInputHeader: false,
            showOutputHeader: false,
            outputOverlay: _JsonFormatOutputOverlay(
              indent: _session.indent,
              wrap: _wrap,
              onIndentChanged: _setIndent,
              onWrapChanged: (value) => setState(() => _wrap = value),
            ),
          ),
        ),
      ],
    );
  }
}

class _JsonFormatOutputOverlay extends StatelessWidget {
  const _JsonFormatOutputOverlay({
    required this.indent,
    required this.wrap,
    required this.onIndentChanged,
    required this.onWrapChanged,
  });

  final String indent;
  final bool wrap;
  final ValueChanged<String> onIndentChanged;
  final ValueChanged<bool> onWrapChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SmallDropdown(
          items: const ['No wrap', 'Wrap'],
          initialValue: wrap ? 'Wrap' : 'No wrap',
          onChanged: (value) => onWrapChanged(value == 'Wrap'),
        ),
        const SizedBox(width: 8),
        SmallDropdown(
          items: const ['2 spaces', '4 spaces', 'Tabs'],
          initialValue: indent,
          onChanged: onIndentChanged,
        ),
      ],
    );
  }
}

/// Compact stats header shown at the top of the JSON Format/Validate tool:
/// root type, item/key count, size, and depth — or the validation error.
class _JsonStatsHeader extends StatelessWidget {
  const _JsonStatsHeader({required this.statusListenable});

  final ValueListenable<JsonToolStatus> statusListenable;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return ValueListenableBuilder<JsonToolStatus>(
      valueListenable: statusListenable,
      builder: (context, status, _) {
        final IconData icon;
        final Color color;
        final String text;
        if (status.error != null) {
          icon = Icons.error_outline;
          color = appColors.error;
          text = status.error!;
        } else if (status.summary != null) {
          icon = Icons.check_circle_outline;
          color = appColors.success;
          text = status.summary!;
        } else {
          icon = Icons.data_object;
          color = appColors.mutedText;
          text = 'Paste or drop JSON to validate and format.';
        }
        return Container(
          width: double.infinity,
          decoration: _toolSurfaceDecoration(context),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: status.error != null
                        ? appColors.error
                        : appColors.editorText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _JsonSplitEditors extends StatelessWidget {
  const _JsonSplitEditors({
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
              _EditorSplitter(
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
            _JsonEditorSplitter(
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

class _JsonEditorSplitter extends StatelessWidget {
  const _JsonEditorSplitter({required this.onDrag});

  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return _EditorSplitter(horizontal: false, onDrag: onDrag);
  }
}

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

class _JsonCompareStrip extends StatelessWidget {
  const _JsonCompareStrip({required this.compare});

  final JsonPanelCompareDetails compare;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final modeLabel = compare.summary.mode == JsonCompareMode.normalized
        ? 'Normalized Diff'
        : 'Raw Diff';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: appColors.accentSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, size: 16, color: appColors.accent),
          const SizedBox(width: 8),
          Text(modeLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text(compare.summary.label),
          const SizedBox(width: 10),
          if (compare.linkedScroll)
            Text('Linked Scroll', style: TextStyle(color: appColors.mutedText)),
        ],
      ),
    );
  }
}

class _JsonValidationResult {
  const _JsonValidationResult.valid(this.info) : error = null, isValid = true;
  const _JsonValidationResult.invalid(this.error)
    : info = null,
      isValid = false;

  final bool isValid;
  final _JsonValidationInfo? info;
  final _JsonValidationError? error;
}

class _JsonValidationInfo {
  const _JsonValidationInfo({
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
        ? '${_thousandsSep(elementCount!)} ${elementCount == 1 ? 'item' : 'items'}'
        : keyCount != null
        ? '${_thousandsSep(keyCount!)} ${keyCount == 1 ? 'key' : 'keys'}'
        : null;
    final parts = <String>[
      rootType,
      if (count != null) count,
      _humanJsonSize(size),
      'depth $depth',
    ];
    return parts.join('  ·  ');
  }
}

String _humanJsonSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _thousandsSep(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _JsonValidationError {
  const _JsonValidationError({
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
_JsonValidationResult _validateJson(String json, {bool strict = false}) {
  final trimmed = json.trim();
  if (trimmed.isEmpty) {
    return const _JsonValidationResult.invalid(
      _JsonValidationError(message: 'Empty input', line: 1, column: 1),
    );
  }

  if (strict) {
    final strictError = _checkStrictCompliance(trimmed);
    if (strictError != null) {
      return _JsonValidationResult.invalid(strictError);
    }
  }

  try {
    final decoded = jsonDecode(trimmed);
    final info = _analyzeJson(decoded, utf8.encode(trimmed).length);
    return _JsonValidationResult.valid(info);
  } on FormatException catch (e) {
    final offset = e.offset ?? 0;
    final position = _positionFromIndex(offset, trimmed);
    final context = _extractContext(position.line, position.column, trimmed);
    final message = e.message;
    return _JsonValidationResult.invalid(
      _JsonValidationError(
        message: message,
        line: position.line,
        column: position.column,
        context: context,
      ),
    );
  } catch (e) {
    return const _JsonValidationResult.invalid(
      _JsonValidationError(message: 'Invalid JSON', line: 1, column: 1),
    );
  }
}

_JsonValidationInfo _analyzeJson(dynamic value, int size) {
  final rootType = _jsonType(value);
  final depth = _jsonDepth(value);
  int? keyCount;
  int? elementCount;
  if (value is Map) {
    keyCount = value.length;
  } else if (value is List) {
    elementCount = value.length;
  }
  return _JsonValidationInfo(
    rootType: rootType,
    keyCount: keyCount,
    elementCount: elementCount,
    depth: depth,
    size: size,
  );
}

String _jsonType(dynamic value) {
  if (value is Map) return 'object';
  if (value is List) return 'array';
  if (value is String) return 'string';
  if (value is num) return 'number';
  if (value is bool) return 'boolean';
  if (value == null) return 'null';
  return 'string';
}

int _jsonDepth(dynamic value, [int current = 1]) {
  if (value is Map) {
    if (value.isEmpty) return current;
    final depths = value.values.map((entry) => _jsonDepth(entry, current + 1));
    return depths.reduce(max);
  }
  if (value is List) {
    if (value.isEmpty) return current;
    final depths = value.map((entry) => _jsonDepth(entry, current + 1));
    return depths.reduce(max);
  }
  return current;
}

({int line, int column}) _positionFromIndex(int index, String input) {
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

String? _extractContext(int line, int column, String json) {
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

_JsonValidationError? _checkStrictCompliance(String json) {
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
      return _JsonValidationError(
        message: 'Comments are not allowed in JSON',
        line: line,
        column: column - 1,
      );
    }

    if ((char == '}' || char == ']') && lastNonWhitespace == ',') {
      return _JsonValidationError(
        message: 'Trailing commas are not allowed in JSON',
        line: line,
        column: column - 1,
      );
    }

    if (char == "'") {
      return _JsonValidationError(
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
      final encoder = JsonEncoder.withIndent(_indentFor(_indent));
      _output.text = encoder.convert(data);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
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
            child: Text(_error!, style: _errorToolTextStyle(context)),
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

class _HexToAsciiView extends StatefulWidget {
  const _HexToAsciiView();

  @override
  State<_HexToAsciiView> createState() => _HexToAsciiViewState();
}

class _HexToAsciiViewState extends State<_HexToAsciiView> {
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
      final bytes = <int>[];
      final parts = text.split(RegExp(r'\s+'));
      for (final part in parts) {
        if (part.trim().isEmpty) continue;
        var token = part.trim();
        if (token.startsWith('0x') || token.startsWith('0X')) {
          token = token.substring(2);
        }
        if (token.length.isOdd) {
          token = '0$token';
        }
        for (var i = 0; i < token.length; i += 2) {
          final hexPair = token.substring(i, i + 2);
          bytes.add(int.parse(hexPair, radix: 16));
        }
      }
      _output.text = String.fromCharCodes(bytes);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() {
      _input.text = text;
    });
  }

  void _setSample() {
    setState(() {
      _input.text = '48 65 6C 6C 6F 20 66 72 6F 6D 20 44 65 76 55 74 69 6C 73';
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
            ],
            outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
            inputPlaceholder: '48 65 6C 6C 6F',
            outputPlaceholder: 'Hello',
            inputController: _input,
            outputController: _output,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!, style: _errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

class _AsciiToHexView extends StatefulWidget {
  const _AsciiToHexView();

  @override
  State<_AsciiToHexView> createState() => _AsciiToHexViewState();
}

class _AsciiToHexViewState extends State<_AsciiToHexView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    if (text.isEmpty) {
      setState(() => _output.text = '');
      return;
    }
    final bytes = text.codeUnits;
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i > 0) buffer.write(' ');
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    setState(() => _output.text = buffer.toString());
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() {
      _input.text = text;
    });
  }

  void _setSample() {
    setState(() => _input.text = 'Hello from DevUtils');
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
      outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
      inputPlaceholder: 'Hello from DevUtils',
      outputPlaceholder: '48 65 6C 6C 6F',
      inputController: _input,
      outputController: _output,
    );
  }
}

class _Base64StringView extends StatefulWidget {
  const _Base64StringView();

  @override
  State<_Base64StringView> createState() => _Base64StringViewState();
}

class _Base64StringViewState extends State<_Base64StringView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  var _encode = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      if (_encode) {
        final bytes = utf8.encode(text);
        _output.text = base64Encode(bytes);
      } else {
        final bytes = base64Decode(text);
        _output.text = utf8.decode(bytes, allowMalformed: true);
      }
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(
      () => _input.text = _encode
          ? 'Hello from DevUtils'
          : 'SGVsbG8gZnJvbSBEZXZVdGlscw==',
    );
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

  void _useAsInput() {
    setState(() => _input.text = _output.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildVerticalEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
              SegmentedToggle(
                options: const ['Encode', 'Decode'],
                initialIndex: _encode ? 0 : 1,
                onChanged: (index) {
                  setState(() => _encode = index == 0);
                  _run();
                },
              ),
            ],
            outputActions: [
              ToolButton(label: 'Copy', onPressed: _copyOutput),
              ToolButton(label: 'Use as input', onPressed: _useAsInput),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: _encode ? 'Hello from DevUtils' : 'SGVsbG8=',
            outputPlaceholder: _encode ? 'SGVsbG8=' : 'Hello',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!, style: _errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

class _UrlEncodeDecodeView extends StatefulWidget {
  const _UrlEncodeDecodeView();

  @override
  State<_UrlEncodeDecodeView> createState() => _UrlEncodeDecodeViewState();
}

class _UrlEncodeDecodeViewState extends State<_UrlEncodeDecodeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  var _encode = true;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _error = null;
      });
      return;
    }
    try {
      _output.text = _encode
          ? Uri.encodeComponent(text)
          : Uri.decodeComponent(text);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(
      () => _input.text = _encode
          ? r'abc 0123 !@#$'
          : 'abc%200123%20%21%40%23%24',
    );
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

  void _useAsInput() {
    setState(() => _input.text = _output.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildVerticalEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearInput),
              const ToolIconButton(icon: Icons.settings),
              SegmentedToggle(
                options: const ['Encode', 'Decode'],
                initialIndex: _encode ? 0 : 1,
                onChanged: (index) {
                  setState(() => _encode = index == 0);
                  _run();
                },
              ),
            ],
            outputActions: [
              ToolButton(label: 'Copy', onPressed: _copyOutput),
              ToolButton(label: 'Use as input', onPressed: _useAsInput),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: _encode ? r'abc 0123 !@#$' : 'abc%200123',
            outputPlaceholder: _encode ? 'abc%200123' : 'abc 0123',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!, style: _errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

class _BackslashEscapeView extends StatefulWidget {
  const _BackslashEscapeView();

  @override
  State<_BackslashEscapeView> createState() => _BackslashEscapeViewState();
}

class _BackslashEscapeViewState extends State<_BackslashEscapeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  var _escape = false;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    setState(() {
      _output.text = _escape
          ? _escapeBackslashes(text)
          : _unescapeBackslashes(text);
    });
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(
      () => _input.text = _escape ? 'Line 1\nLine 2' : 'Line 1\\nLine 2',
    );
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

  void _useAsInput() {
    setState(() => _input.text = _output.text);
  }

  @override
  Widget build(BuildContext context) {
    return buildVerticalEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
        SegmentedToggle(
          options: const ['Escape', 'Unescape'],
          initialIndex: _escape ? 0 : 1,
          onChanged: (index) {
            setState(() => _escape = index == 0);
            _run();
          },
        ),
      ],
      outputActions: [
        ToolButton(label: 'Copy', onPressed: _copyOutput),
        ToolButton(label: 'Use as input', onPressed: _useAsInput),
      ],
      inputController: _input,
      outputController: _output,
      inputPlaceholder: 'Line 1\\nLine 2',
      outputPlaceholder: 'Line 1\nLine 2',
    );
  }
}

String _escapeBackslashes(String input) {
  return input
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t')
      .replaceAll('"', r'\"');
}

String _unescapeBackslashes(String input) {
  return input
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', '\\');
}

class _LineSortDedupeView extends StatefulWidget {
  const _LineSortDedupeView();

  @override
  State<_LineSortDedupeView> createState() => _LineSortDedupeViewState();
}

class _LineSortDedupeViewState extends State<_LineSortDedupeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _sort = 'A -> Z (Text)';
  String _dupes = 'With Duplicates';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final lines = _input.text.split(RegExp(r'\r?\n'));
    final cleaned = _dupes == 'With Duplicates'
        ? lines
        : lines.toSet().toList();
    cleaned.sort((a, b) => a.compareTo(b));
    if (_sort.startsWith('Z')) {
      cleaned.setAll(0, cleaned.reversed);
    }
    _output.text = cleaned.join('\n');
    setState(() {});
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(() => _input.text = '1\n11\n2\n22\n22\n33\n5.0\n2.5');
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
        SmallDropdown(
          items: const ['A -> Z (Text)', 'Z -> A (Text)'],
          initialValue: _sort,
          onChanged: (value) {
            setState(() => _sort = value);
            _run();
          },
        ),
        SmallDropdown(
          items: const ['With Duplicates', 'Without Duplicates'],
          initialValue: _dupes,
          onChanged: (value) {
            setState(() => _dupes = value);
            _run();
          },
        ),
        ToolButton(label: 'Copy', onPressed: _copyOutput),
      ],
      inputController: _input,
      outputController: _output,
      inputPlaceholder: 'Line 1\nLine 2\nLine 2',
      outputPlaceholder: 'Line 1\nLine 2',
    );
  }
}

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
    final text = await _readClipboardText();
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
        : _beautifyStyleSheet(text, _indentFor(_indent));
    setState(() {});
  }

  Future<void> _pickFile() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: _acceptedExtensions,
    );
    if (path == null || !mounted) return;
    await _loadFile(path);
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
      setState(() => _error = _friendlyFileReadError(error));
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
      inputPlaceholder: 'Drop a .${widget.language.toLowerCase()} file here '
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
      outputActions: const [],
      inputOverlay: _SourceFileControls(
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
        Text(_error!, style: _errorToolTextStyle(context)),
        const SizedBox(height: 8),
        Expanded(child: editors),
      ],
    );
  }
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
    lines.add('${indent()}$text${suffixSemicolon ? ';' : ''}');
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
        _output.text = _beautifyHtml(text, _indentFor(_indent));
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

    return _ResizableSplit(
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
          ? _HtmlRenderedPreview(html: _input.text, overlay: outputControls)
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
          Text(_error!, style: _errorToolTextStyle(context)),
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
      setState(() => _error = _friendlyFileReadError(error));
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
          Text(_error!, style: _errorToolTextStyle(context)),
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
                _SourceFileControls(
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
        Text(summary, style: _mutedToolTextStyle(context, fontSize: 12)),
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
            color: selected ? appColors.accent.withAlpha(48) : Colors.transparent,
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
              _CompactCheck(
                label: 'class fields',
                value: addClassFields,
                onChanged: (value) => onChanged(addClassFields: value),
              ),
              _CompactCheck(
                label: 'JSDoc',
                value: useJsDoc,
                onChanged: (value) => onChanged(useJsDoc: value),
              ),
              _CompactCheck(
                label: 'CommonJS',
                value: rewriteCommonJs,
                onChanged: (value) => onChanged(rewriteCommonJs: value),
              ),
              _CompactCheck(
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

class _CompactCheck extends StatelessWidget {
  const _CompactCheck({
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
    RegExp(r'\b(function\s+[A-Za-z_$][\w$]*|class\s+[A-Za-z_$][\w$]*)\s*<[^>]*>'),
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
    RegExp(r'([(,]\s*(?:\.\.\.)?[A-Za-z_$][\w$]*)\s*\?\s*:\s*[^,)=]+?(?=\s*[,)=])'),
    (m) => m.group(1)!,
  );
  output = output.replaceAllMapped(
    RegExp(r'([(,]\s*(?:\.\.\.)?[A-Za-z_$][\w$]*)\s*:\s*[^,)=]+?(?=\s*[,)=])'),
    (m) => m.group(1)!,
  );

  // Class field declarations: `name?: T;` / `name: T = …`.
  output = output.replaceAllMapped(
    RegExp(r'^([ \t]*)([A-Za-z_$][\w$]*)\s*\??\s*:\s*[^=;\n]+?(\s*[=;])', multiLine: true),
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
    final keepExport = src.substring(match.start, braceStart).contains('export');
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

class _HtmlRenderedPreview extends StatefulWidget {
  const _HtmlRenderedPreview({required this.html, required this.overlay});

  final String html;
  final Widget overlay;

  @override
  State<_HtmlRenderedPreview> createState() => _HtmlRenderedPreviewState();
}

class _HtmlRenderedPreviewState extends State<_HtmlRenderedPreview> {
  WebViewController? _controller;
  Object? _webViewError;
  Timer? _reloadTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void didUpdateWidget(covariant _HtmlRenderedPreview oldWidget) {
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
    await controller.loadHtmlString(_previewDocument(widget.html));
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
                ? _HtmlPreviewFallback(html: widget.html, error: _webViewError)
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

class _HtmlPreviewFallback extends StatelessWidget {
  const _HtmlPreviewFallback({required this.html, required this.error});

  final String html;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final text = _plainTextFromHtml(html);
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

String _previewDocument(String html) {
  final trimmed = html.trim();
  if (trimmed.isEmpty) return _previewShell('');
  if (RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed;
  }
  return _previewShell(trimmed);
}

String _previewShell(String body) {
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

String _plainTextFromHtml(String html) {
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
  return _decodeHtmlEntities(withBreaks.replaceAll(RegExp(r'<[^>]+>'), ' '))
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s+'), '\n')
      .trim();
}

String? _htmlTagName(String tag) {
  final match = RegExp(r'^</?\s*([a-zA-Z0-9:-]+)').firstMatch(tag);
  return match?.group(1)?.toLowerCase();
}

String _decodeHtmlEntities(String input) {
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
        _output.text = _beautifyJs(text, _indentFor(_indent));
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
    final text = await _readClipboardText();
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

class _Base64ImageView extends StatefulWidget {
  const _Base64ImageView();

  @override
  State<_Base64ImageView> createState() => _Base64ImageViewState();
}

class _Base64ImageViewState extends State<_Base64ImageView> {
  final TextEditingController _input = TextEditingController();
  String _previewLabel = 'Image preview (base64 only)';
  Uint8List? _previewBytes;
  String? _previewError;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    _input.text = text;
    _updatePreview();
  }

  void _setSample() {
    _input.text =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l5F7cwAAAABJRU5ErkJggg==';
    _updatePreview();
  }

  void _clear() {
    setState(() {
      _input.clear();
      _previewLabel = 'Image preview (base64 only)';
      _previewBytes = null;
      _previewError = null;
    });
  }

  Future<void> _copyString() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
  }

  Future<void> _copyImage() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
  }

  void _updatePreview() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _previewLabel = 'Image preview (base64 only)';
        _previewBytes = null;
        _previewError = null;
      });
      return;
    }
    try {
      final bytes = _decodeBase64Image(text);
      setState(() {
        _previewBytes = bytes;
        _previewLabel = '${bytes.length} bytes';
        _previewError = null;
      });
    } catch (error) {
      setState(() {
        _previewBytes = null;
        _previewLabel = 'Image preview (base64 only)';
        _previewError = 'Invalid image data';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ResizableSplit(
      horizontal: true,
      first: EditorPane(
        label: 'String',
        actions: [
          ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
          ToolButton(label: 'Sample', onPressed: _setSample),
          ToolButton(label: 'Clear', onPressed: _clear),
          ToolButton(label: 'Copy', onPressed: _copyString),
        ],
        controller: _input,
        onChanged: (_) => _updatePreview(),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Image',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: _toolSurfaceDecoration(context),
              child: Stack(
                children: [
                  Center(
                    child: _previewBytes == null
                        ? Text(
                            _previewError ?? _previewLabel,
                            style: _previewError == null
                                ? _mutedToolTextStyle(context)
                                : _errorToolTextStyle(context),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(18),
                            child: Image.memory(
                              _previewBytes!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (context, error, stackTrace) =>
                                  Text(
                                    'Could not render image',
                                    style: _errorToolTextStyle(context),
                                  ),
                            ),
                          ),
                  ),
                  if (_previewBytes != null)
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: Text(
                        _previewLabel,
                        style: _mutedToolTextStyle(context, fontSize: 11),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Load File...',
                          child: IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.upload_file, size: 18),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            splashRadius: 16,
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: _copyImage,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 24),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          child: const Text('Copy'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Uint8List _decodeBase64Image(String input) {
  var value = input.trim();
  final comma = value.indexOf(',');
  if (value.toLowerCase().startsWith('data:image/') && comma >= 0) {
    value = value.substring(comma + 1);
  }
  value = value.replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) throw const FormatException('No image data.');
  return Uint8List.fromList(base64Decode(value));
}

class _UrlParserView extends StatefulWidget {
  const _UrlParserView();

  @override
  State<_UrlParserView> createState() => _UrlParserViewState();
}

class _UrlParserViewState extends State<_UrlParserView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _queryJson = TextEditingController();
  String _protocol = '';
  String _host = '';
  String _path = '';
  String _file = '';
  String _query = '';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _queryJson.dispose();
    super.dispose();
  }

  void _parse() {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _protocol = '';
        _host = '';
        _path = '';
        _file = '';
        _query = '';
        _queryJson.clear();
        _error = null;
      });
      return;
    }
    try {
      final uri = Uri.parse(raw);
      _protocol = uri.scheme;
      _host = uri.host;
      _path = uri.path;
      _file = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      _query = uri.query;
      final queryMap = uri.queryParameters;
      _queryJson.text = const JsonEncoder.withIndent('  ').convert(queryMap);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _parse();
  }

  void _setSample() {
    const sample =
        'https://www.google.com/search?q=sample+long+query&src=devutils';
    setState(() => _input.text = sample);
    _parse();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _queryJson.clear();
      _error = null;
    });
  }

  Future<void> _copyQuery() async {
    await Clipboard.setData(ClipboardData(text: _queryJson.text));
  }

  @override
  Widget build(BuildContext context) {
    return _ResizableSplit(
      horizontal: false,
      initialRatio: 0.36,
      minFirstExtent: 180,
      minSecondExtent: 320,
      first: EditorPane(
        label: 'Input',
        actions: [
          ToolButton(label: 'Go', onPressed: _parse),
          ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
          ToolButton(label: 'Sample', onPressed: _setSample),
          ToolButton(label: 'Clear', onPressed: _clearInput),
          const ToolIconButton(icon: Icons.settings),
        ],
        controller: _input,
        onChanged: (_) => _parse(),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Field'),
          Container(
            decoration: _toolSurfaceDecoration(context),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Protocol: $_protocol'),
                Text('Host: $_host'),
                Text('Path: $_path'),
                Text('File name: $_file'),
                Text('Query: $_query'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: EditorPane(
              label: 'Query string',
              actions: [ToolButton(label: 'Copy', onPressed: _copyQuery)],
              controller: _queryJson,
              readOnly: true,
              placeholder: '{ }',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: _errorToolTextStyle(context)),
          ],
        ],
      ),
    );
  }
}

class _SubdomainFinderView extends StatefulWidget {
  const _SubdomainFinderView();

  @override
  State<_SubdomainFinderView> createState() => _SubdomainFinderViewState();
}

class _SubdomainFinderViewState extends State<_SubdomainFinderView> {
  final TextEditingController _domain = TextEditingController();
  final TextEditingController _results = TextEditingController();
  late final SubdomainLookupService _service = SubdomainLookupService();
  var _mode = SubdomainLookupMode.domain;
  var _loading = false;
  var _status = 'Enter a root domain to find public subdomains.';
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _requestId++;
    _service.close();
    _domain.dispose();
    _results.dispose();
    super.dispose();
  }

  bool get _isDomainMode => _mode == SubdomainLookupMode.domain;

  String get _inputHint => _isDomainMode ? 'example.com' : 'Example Inc';

  String get _emptyStatus => _isDomainMode
      ? 'Enter a root domain to find public subdomains.'
      : 'Enter an organization name to find public certificate names.';

  String get _loadingStatus => _isDomainMode
      ? 'Searching certificate transparency and DNS records...'
      : 'Searching organization certificates...';

  String get _outputPlaceholder => _isDomainMode
      ? 'Public subdomains will appear here...'
      : 'Public certificate names will appear here...';

  Future<void> _findSubdomains() async {
    final requestId = ++_requestId;
    final mode = _mode;
    setState(() {
      _loading = true;
      _error = null;
      _status = _loadingStatus;
      _results.clear();
    });

    try {
      final result = switch (mode) {
        SubdomainLookupMode.domain => await _service.lookup(_domain.text),
        SubdomainLookupMode.organization => await _service.lookupOrganization(
          _domain.text,
        ),
      };
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results.text = result.subdomains.join('\n');
        final noun = result.mode == SubdomainLookupMode.domain
            ? 'public subdomains'
            : 'public certificate names';
        final target = result.mode == SubdomainLookupMode.domain
            ? result.domain
            : '"${result.domain}"';
        if (result.subdomains.isEmpty) {
          final fallbackHint =
              result.mode == SubdomainLookupMode.domain && !result.usedSubfinder
              ? ' Install subfinder for deeper local discovery.'
              : '';
          final warningText = result.usedSubfinder && result.hasWarnings
              ? ' ${result.warnings.join(' ')}'
              : '';
          _status = 'No $noun found for $target.$fallbackHint$warningText';
        } else {
          _status = '${result.subdomains.length} $noun found for $target.';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
        _status = 'Lookup failed.';
        _loading = false;
      });
    }
  }

  void _setSample() {
    _domain.text = _isDomainMode ? 'github.com' : 'GitHub';
  }

  void _clear() {
    setState(() {
      _domain.clear();
      _results.clear();
      _error = null;
      _status = _emptyStatus;
    });
  }

  void _changeMode(int index) {
    final mode = index == 0
        ? SubdomainLookupMode.domain
        : SubdomainLookupMode.organization;
    setState(() {
      _requestId++;
      _mode = mode;
      _domain.clear();
      _results.clear();
      _error = null;
      _loading = false;
      _status = _emptyStatus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: _toolSurfaceDecoration(context),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedToggle(
                      options: const ['Domain', 'Organization'],
                      initialIndex: _isDomainMode ? 0 : 1,
                      onChanged: _changeMode,
                    ),
                    Text(
                      'Target',
                      style: TextStyle(
                        color: appColors.editorText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ToolButton(
                      label: 'Find known',
                      onPressed: _loading ? null : _findSubdomains,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: _toolSurfaceDecoration(context, radius: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextField(
                    controller: _domain,
                    enabled: !_loading,
                    onSubmitted: (_) => _findSubdomains(),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: _inputHint,
                      hintStyle: TextStyle(color: appColors.mutedText),
                    ),
                    style: TextStyle(
                      color: appColors.editorText,
                      fontFamily: 'Menlo',
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_loading) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _error ?? _status,
                  style: _error == null
                      ? _mutedToolTextStyle(context)
                      : _errorToolTextStyle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: EditorPane(
              label: 'Public subdomains',
              actions: [
                ToolButton(label: 'Sample', onPressed: _setSample),
                ToolButton(label: 'Clear', onPressed: _clear),
              ],
              controller: _results,
              readOnly: true,
              placeholder: _outputPlaceholder,
              showHeader: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubdomainTakeoverView extends StatefulWidget {
  const _SubdomainTakeoverView();

  @override
  State<_SubdomainTakeoverView> createState() => _SubdomainTakeoverViewState();
}

class _SubdomainTakeoverViewState extends State<_SubdomainTakeoverView> {
  final TextEditingController _targets = TextEditingController();
  final TextEditingController _timeout = TextEditingController(text: '8');
  final TextEditingController _concurrency = TextEditingController(text: '8');
  final TextEditingController _details = TextEditingController();
  late final SubdomainTakeoverService _service = SubdomainTakeoverService();

  var _scanning = false;
  var _status = 'Enter subdomains to check for dangling provider mappings.';
  var _reportMode = 'Details';
  String? _error;
  TakeoverScanProgress? _progress;
  TakeoverScanSummary? _summary;
  TakeoverScanResult? _selected;
  int _requestId = 0;

  @override
  void dispose() {
    _requestId++;
    _service.close();
    _targets.dispose();
    _timeout.dispose();
    _concurrency.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;

    final requestId = ++_requestId;
    setState(() {
      _scanning = true;
      _error = null;
      _summary = null;
      _selected = null;
      _progress = null;
      _details.clear();
      _status = 'Checking DNS and provider fingerprints...';
    });

    try {
      final timeoutSeconds = double.tryParse(_timeout.text.trim()) ?? 8;
      final concurrency = int.tryParse(_concurrency.text.trim()) ?? 8;
      final summary = await _service.scanText(
        _targets.text,
        timeout: Duration(milliseconds: (timeoutSeconds * 1000).round()),
        concurrency: concurrency,
        onProgress: (progress) {
          if (!mounted || requestId != _requestId) return;
          setState(() {
            _progress = progress;
            _status =
                'Checked ${progress.scanned}/${progress.total}, ${progress.potentialCount} potential.';
          });
        },
      );

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _summary = summary;
        _selected = summary.results.isEmpty ? null : summary.results.first;
        _scanning = false;
        _progress = TakeoverScanProgress(
          scanned: summary.results.length,
          total: summary.results.length,
          potentialCount: summary.potentialCount,
        );
        _status = summary.potentialCount == 0
            ? 'No takeover fingerprints matched across ${summary.results.length} hosts.'
            : '${summary.potentialCount} potential takeover match(es) across ${summary.results.length} hosts.';
        _refreshDetails();
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error is FormatException ? error.message : error.toString();
        _status = 'Scan failed.';
        _scanning = false;
      });
    }
  }

  void _refreshDetails() {
    final summary = _summary;
    if (_reportMode == 'JSON') {
      _details.text = summary?.toJsonReport() ?? '';
      return;
    }
    if (_reportMode == 'CSV') {
      _details.text = summary?.toCsvReport() ?? '';
      return;
    }
    final selected = _selected;
    _details.text = selected == null ? '' : _formatTakeoverDetails(selected);
  }

  void _selectResult(TakeoverScanResult result) {
    setState(() {
      _selected = result;
      _reportMode = 'Details';
      _refreshDetails();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTakeoverControls(context),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_scanning) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _error ?? _status,
                  style: _error == null
                      ? _mutedToolTextStyle(context)
                      : _errorToolTextStyle(context),
                ),
              ),
              if (progress != null && progress.total > 0) ...[
                SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(value: progress.ratio),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(progress.ratio * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: appColors.mutedText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _ResizableSplit(
              horizontal: true,
              initialRatio: 0.5,
              minFirstExtent: 360,
              minSecondExtent: 360,
              first: _buildTakeoverResults(context),
              second: _buildTakeoverDetails(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTakeoverControls(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Targets',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              _takeoverOptionField(
                context,
                'Timeout',
                controller: _timeout,
                width: 72,
                suffix: 's',
              ),
              const SizedBox(width: 10),
              _takeoverOptionField(
                context,
                'Concurrency',
                controller: _concurrency,
                width: 72,
              ),
              const Spacer(),
              ToolButton(label: 'Scan', onPressed: _scanning ? null : _scan),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: _toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: TextField(
              key: const ValueKey('subdomain-takeover-targets'),
              controller: _targets,
              enabled: !_scanning,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'docs.example.com\nhelp.example.com',
                hintStyle: TextStyle(color: appColors.mutedText),
              ),
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: 'Menlo',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTakeoverResults(BuildContext context) {
    final results = _summary?.results ?? const <TakeoverScanResult>[];
    return Container(
      decoration: _toolSurfaceDecoration(context),
      child: results.isEmpty
          ? Center(
              child: Text(
                _scanning
                    ? 'Scanning targets...'
                    : 'Potential takeover matches will appear here',
                style: _mutedToolTextStyle(context),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final result = results[index];
                return _takeoverResultTile(context, result);
              },
            ),
    );
  }

  Widget _takeoverResultTile(BuildContext context, TakeoverScanResult result) {
    final appColors = context.appColors;
    final selected = identical(_selected, result);
    return InkWell(
      onTap: () => _selectResult(result),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? appColors.accent.withAlpha(24) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? appColors.accent : appColors.border,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.host,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: appColors.editorText,
                      fontFamily: 'Menlo',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _takeoverConfidenceChip(context, result.confidence),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              result.service,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appColors.editorText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.evidence,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _mutedToolTextStyle(context, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTakeoverDetails(BuildContext context) {
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SegmentedToggle(
                key: ValueKey('takeover-report-$_reportMode'),
                options: const ['Details', 'JSON', 'CSV'],
                initialIndex: switch (_reportMode) {
                  'JSON' => 1,
                  'CSV' => 2,
                  _ => 0,
                },
                onChanged: (index) {
                  setState(() {
                    _reportMode = switch (index) {
                      1 => 'JSON',
                      2 => 'CSV',
                      _ => 'Details',
                    };
                    _refreshDetails();
                  });
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selected?.host ?? 'Result details',
                  overflow: TextOverflow.ellipsis,
                  style: _mutedToolTextStyle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: EditorPane(
              label: 'Takeover details',
              actions: const [],
              controller: _details,
              readOnly: true,
              placeholder: 'Select a scan result to inspect evidence...',
              showHeader: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _takeoverOptionField(
    BuildContext context,
    String label, {
    required TextEditingController controller,
    required double width,
    String? suffix,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _mutedToolTextStyle(context)),
        const SizedBox(width: 6),
        SizedBox(
          width: width,
          child: Container(
            decoration: _toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              controller: controller,
              enabled: !_scanning,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
              style: TextStyle(
                color: context.appColors.editorText,
                fontFamily: 'Menlo',
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text(suffix, style: _mutedToolTextStyle(context)),
        ],
      ],
    );
  }

  Widget _takeoverConfidenceChip(
    BuildContext context,
    TakeoverConfidence confidence,
  ) {
    final appColors = context.appColors;
    final color = switch (confidence) {
      TakeoverConfidence.high => appColors.error,
      TakeoverConfidence.medium => appColors.warning,
      TakeoverConfidence.low => appColors.accent,
      TakeoverConfidence.safe => appColors.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(160)),
      ),
      child: Text(
        confidence.label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _formatTakeoverDetails(TakeoverScanResult result) {
  final buffer = StringBuffer()
    ..writeln('Host: ${result.host}')
    ..writeln('Service: ${result.service}')
    ..writeln('Confidence: ${result.confidence.label}')
    ..writeln('Evidence: ${result.evidence}');

  if (result.matchedCnameIndicator != null) {
    buffer.writeln('Matched CNAME indicator: ${result.matchedCnameIndicator}');
  }
  if (result.matchedBodyIndicator != null) {
    buffer.writeln('Matched page indicator: ${result.matchedBodyIndicator}');
  }
  if (result.cnameChain.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('CNAME chain:')
      ..writeln(result.cnameChain.map((cname) => '  $cname').join('\n'));
  }
  if (result.probes.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('HTTP probes:');
    for (final probe in result.probes) {
      final status = probe.statusCode?.toString() ?? 'no response';
      final error = probe.error == null ? '' : ' (${probe.error})';
      buffer.writeln('  ${probe.url} - $status$error');
    }
  }

  buffer
    ..writeln()
    ..writeln(
      'Note: Treat this as a triage signal. Verify provider ownership before taking action.',
    );
  return buffer.toString();
}

class _PortScannerView extends StatefulWidget {
  const _PortScannerView();

  @override
  State<_PortScannerView> createState() => _PortScannerViewState();
}

class _PortScannerViewState extends State<_PortScannerView> {
  final TextEditingController _target = TextEditingController(
    text: '127.0.0.1',
  );
  final TextEditingController _ports = TextEditingController();
  final TextEditingController _timeout = TextEditingController();
  final TextEditingController _concurrency = TextEditingController();
  final TextEditingController _report = TextEditingController();
  late final PortScannerService _service = PortScannerService();
  late final StreamSubscription<ScanProgress> _progressSubscription;

  var _profileName = 'Quick Scan';
  var _reportMode = 'JSON';
  var _detailsIndex = 0;
  var _grabBanners = true;
  var _tlsDetails = true;
  var _httpProbe = true;
  var _scanning = false;
  var _reconLoading = false;
  var _status = 'Ready.';
  String? _error;
  ScanProgress? _progress;
  PortScanSummary? _summary;
  HostReconResult? _recon;
  final List<PortScanSummary> _history = [];
  int _requestId = 0;

  static const _customProfileName = 'Custom Ports';

  bool get _isCustomProfile => _profileName == _customProfileName;

  List<String> get _profileNames => [
    ...PortScannerService.profiles.map((profile) => profile.name),
    _customProfileName,
  ];

  @override
  void initState() {
    super.initState();
    _syncProfileFields();
    _progressSubscription = _service.progress.listen((progress) {
      if (!mounted) return;
      setState(() {
        _progress = progress;
        if (progress.active) {
          _status =
              'Scanning ${progress.scanned}/${progress.total} ports, ${progress.openCount} open.';
        }
      });
    });
  }

  @override
  void dispose() {
    _requestId++;
    _progressSubscription.cancel();
    _service.close();
    _target.dispose();
    _ports.dispose();
    _timeout.dispose();
    _concurrency.dispose();
    _report.dispose();
    super.dispose();
  }

  void _syncProfileFields() {
    if (_isCustomProfile) {
      if (_ports.text.trim().isEmpty) {
        _ports.text = '22,80,443,8080,8443';
      }
      _timeout.text = '1.0';
      _concurrency.text = '50';
      return;
    }

    final profile = PortScannerService.profileByName(_profileName);
    _ports.text = _describePorts(profile);
    _timeout.text = _secondsLabel(profile.timeout);
    _concurrency.text = profile.concurrency.toString();
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    final requestId = ++_requestId;
    late final PortScanProfile profile;
    late final List<int>? customPorts;
    late final Duration timeout;
    late final int concurrency;

    try {
      timeout = _parseTimeout();
      concurrency = _parseConcurrency();
      if (_isCustomProfile) {
        customPorts = PortScannerService.parsePorts(_ports.text);
        profile = PortScanProfile(
          name: _customProfileName,
          description: 'Custom port list',
          timeout: timeout,
          concurrency: concurrency,
          ports: customPorts,
        );
      } else {
        customPorts = null;
        profile = PortScannerService.profileByName(_profileName);
      }
      PortScannerService.normalizeTarget(_target.text);
    } catch (e) {
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
      });
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
      _progress = const ScanProgress(
        scanned: 0,
        total: 0,
        active: true,
        openCount: 0,
      );
      _status = 'Resolving target...';
      _summary = null;
      _report.clear();
    });

    try {
      final summary = await _service.scan(
        target: _target.text,
        profile: profile,
        ports: customPorts,
        timeout: timeout,
        concurrency: concurrency,
        grabBanners: _grabBanners,
        tlsDetails: _tlsDetails,
        httpProbe: _httpProbe,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _summary = summary;
        _history.insert(0, summary);
        if (_history.length > 20) _history.removeLast();
        _status =
            '${summary.results.length} open of ${summary.totalPorts} ports. Grade ${summary.securityScore.grade}.';
        _scanning = false;
      });
      _refreshReport();
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
        _status = 'Scan failed.';
        _scanning = false;
      });
    }
  }

  Future<void> _runRecon() async {
    if (_reconLoading) return;
    final requestId = ++_requestId;
    try {
      PortScannerService.normalizeTarget(_target.text);
    } catch (e) {
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
      });
      return;
    }

    setState(() {
      _reconLoading = true;
      _error = null;
      _status = 'Collecting host details...';
      _detailsIndex = 1;
    });

    try {
      final recon = await _service.reconnaissance(_target.text);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _recon = recon;
        _status = 'Recon complete for ${recon.target}.';
        _reconLoading = false;
      });
      _refreshReport();
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _status = 'Recon failed.';
        _reconLoading = false;
      });
    }
  }

  void _stopScan() {
    _service.cancel();
    setState(() {
      _requestId++;
      _scanning = false;
      _status = 'Stopping scan...';
    });
  }

  void _setSample() {
    setState(() {
      _target.text = 'scanme.nmap.org';
      _profileName = 'Web Ports';
      _syncProfileFields();
    });
  }

  Duration _parseTimeout() {
    final seconds = double.tryParse(_timeout.text.trim());
    if (seconds == null || seconds <= 0 || seconds > 30) {
      throw const FormatException(
        'Timeout must be between 0.1 and 30 seconds.',
      );
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  int _parseConcurrency() {
    final value = int.tryParse(_concurrency.text.trim());
    if (value == null || value < 1 || value > 100) {
      throw const FormatException('Concurrency must be between 1 and 100.');
    }
    return value;
  }

  void _refreshReport() {
    final summary = _summary;
    final recon = _recon;
    if (_reportMode == 'CSV') {
      _report.text = summary?.toCsvReport() ?? '';
      return;
    }
    final payload = <String, Object?>{
      if (summary != null) 'scan': summary.toJson(),
      if (recon != null) 'recon': recon.toJson(),
    };
    _report.text = payload.isEmpty
        ? ''
        : const JsonEncoder.withIndent('  ').convert(payload);
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildControls(context),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_scanning || _reconLoading) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _error ?? _status,
                  style: _error == null
                      ? _mutedToolTextStyle(context)
                      : _errorToolTextStyle(context),
                ),
              ),
              if (progress != null && progress.total > 0) ...[
                SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(value: progress.ratio),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(progress.ratio * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: appColors.mutedText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _ResizableSplit(
              horizontal: true,
              initialRatio: 0.56,
              minFirstExtent: 360,
              minSecondExtent: 320,
              first: _buildPortsPanel(context),
              second: _buildDetailsPanel(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Target',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(
                width: 280,
                child: _compactTextField(
                  key: const ValueKey('port-scanner-target'),
                  controller: _target,
                  hint: 'example.com or 192.0.2.10',
                  enabled: !_scanning,
                  onSubmitted: (_) => _startScan(),
                ),
              ),
              SmallDropdown(
                key: ValueKey('port-profile-$_profileName'),
                items: _profileNames,
                initialValue: _profileName,
                width: 180,
                onChanged: (value) {
                  setState(() {
                    _profileName = value;
                    _syncProfileFields();
                  });
                },
              ),
              SizedBox(
                width: 250,
                child: _compactTextField(
                  controller: _ports,
                  hint: '22,80,443 or 8000-8010',
                  enabled: _isCustomProfile && !_scanning,
                ),
              ),
              ToolButton(
                label: 'Sample',
                onPressed: _scanning ? null : _setSample,
              ),
              ToolButton(
                label: 'Scan',
                onPressed: _scanning ? null : _startScan,
              ),
              ToolButton(
                label: 'Recon',
                onPressed: _reconLoading ? null : _runRecon,
              ),
              ToolButton(
                label: 'Stop',
                onPressed: _scanning ? _stopScan : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _miniLabeledField(
                context,
                'Timeout',
                width: 84,
                controller: _timeout,
                suffix: 's',
                enabled: !_scanning,
              ),
              _miniLabeledField(
                context,
                'Concurrency',
                width: 76,
                controller: _concurrency,
                enabled: !_scanning,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _grabBanners,
                    onChanged: _scanning
                        ? null
                        : (value) {
                            setState(() => _grabBanners = value ?? true);
                          },
                  ),
                  Text(
                    'Banners',
                    style: TextStyle(color: appColors.editorText),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _tlsDetails,
                    onChanged: _scanning
                        ? null
                        : (value) {
                            setState(() => _tlsDetails = value ?? true);
                          },
                  ),
                  Text(
                    'TLS details',
                    style: TextStyle(color: appColors.editorText),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _httpProbe,
                    onChanged: _scanning
                        ? null
                        : (value) {
                            setState(() => _httpProbe = value ?? true);
                          },
                  ),
                  Text(
                    'HTTP HEAD',
                    style: TextStyle(color: appColors.editorText),
                  ),
                ],
              ),
              Text(
                _isCustomProfile
                    ? 'Custom list'
                    : PortScannerService.profileByName(
                        _profileName,
                      ).description,
                style: _mutedToolTextStyle(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortsPanel(BuildContext context) {
    final summary = _summary;
    final results = summary?.results ?? const <PortScanResult>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final showStats = constraints.maxHeight >= 120;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showStats) ...[
              _buildScanStats(context, summary),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: Container(
                decoration: _toolSurfaceDecoration(context),
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          _scanning
                              ? 'Scanning...'
                              : 'Open ports will appear here',
                          style: _mutedToolTextStyle(context),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _portResultRow(context, results[index]);
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScanStats(BuildContext context, PortScanSummary? summary) {
    final open = summary?.results.length ?? 0;
    final total = summary?.totalPorts ?? _progress?.total ?? 0;
    final highRisk = summary?.highRiskPorts ?? 0;
    final score = summary?.securityScore.score ?? 100;
    final grade = summary?.securityScore.grade ?? 'A';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _statPill(context, 'Open', '$open'),
        _statPill(context, 'Scanned', '$total'),
        _statPill(context, 'High risk', '$highRisk'),
        _statPill(context, 'Score', '$score / $grade'),
      ],
    );
  }

  Widget _statPill(BuildContext context, String label, String value) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: _mutedToolTextStyle(context, fontSize: 12)),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: appColors.editorText,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _portResultRow(BuildContext context, PortScanResult result) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  result.port.toString(),
                  style: TextStyle(
                    color: appColors.editorText,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '${result.service} · ${result.protocol} · ${result.confidence}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: appColors.editorText),
                ),
              ),
              _riskChip(context, result.riskLevel),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.riskReason,
            style: _mutedToolTextStyle(context, fontSize: 12),
          ),
          if (result.httpStatus != null ||
              (result.tls?.connected ?? false)) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (result.httpStatus != null) result.httpStatus,
                if (result.tls?.connected ?? false)
                  'TLS ${result.tls?.daysUntilExpiry == null ? 'ok' : '${result.tls!.daysUntilExpiry}d left'}',
              ].join(' · '),
              style: TextStyle(
                color: appColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (result.banner.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              result.banner,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appColors.mutedText,
                fontFamily: 'Menlo',
                fontSize: 11,
              ),
            ),
          ],
          if (result.vulnerabilities.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${result.vulnerabilities.length} known CVE/reference checks',
              style: TextStyle(
                color: appColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _riskChip(BuildContext context, String riskLevel) {
    final appColors = context.appColors;
    final color = switch (riskLevel) {
      'CRITICAL' => appColors.error,
      'HIGH' => appColors.warning,
      'MEDIUM' => appColors.accent,
      _ => appColors.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(160)),
      ),
      child: Text(
        riskLevel,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildDetailsPanel(BuildContext context) {
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SegmentedToggle(
                  options: const ['Details', 'Recon', 'Report', 'History'],
                  initialIndex: _detailsIndex,
                  onChanged: (index) => setState(() => _detailsIndex = index),
                ),
                if (_detailsIndex == 2) ...[
                  const SizedBox(width: 10),
                  SmallDropdown(
                    key: ValueKey('port-report-$_reportMode'),
                    items: const ['JSON', 'CSV'],
                    initialValue: _reportMode,
                    width: 90,
                    onChanged: (value) {
                      setState(() => _reportMode = value);
                      _refreshReport();
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: switch (_detailsIndex) {
              0 => _buildScoreDetails(context),
              1 => _buildReconDetails(context),
              2 => _buildReportPanel(context),
              _ => _buildHistoryPanel(context),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScoreDetails(BuildContext context) {
    final summary = _summary;
    if (summary == null) {
      return Center(
        child: Text(
          'Scan details will appear here',
          style: _mutedToolTextStyle(context),
        ),
      );
    }
    final score = summary.securityScore;
    return ListView(
      children: [
        _detailRow(
          context,
          'Target',
          '${summary.target} (${summary.resolvedIp})',
        ),
        _detailRow(context, 'Profile', summary.profile),
        _detailRow(
          context,
          'Duration',
          '${summary.duration.inMilliseconds} ms',
        ),
        _detailRow(
          context,
          'Security grade',
          '${score.grade} (${score.score}/100)',
        ),
        const SizedBox(height: 10),
        Text(
          'Penalty breakdown',
          style: TextStyle(
            color: context.appColors.editorText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        for (final entry in score.breakdown.entries)
          _detailRow(
            context,
            _sentenceLabel(entry.key),
            entry.value.toString(),
          ),
        const SizedBox(height: 10),
        Text(
          'Recommendations',
          style: TextStyle(
            color: context.appColors.editorText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        if (score.recommendations.isEmpty)
          Text(
            'No high-priority recommendations.',
            style: _mutedToolTextStyle(context),
          )
        else
          for (final recommendation in score.recommendations)
            _recommendationTile(context, recommendation),
        if (summary.results.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Service evidence',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final result in summary.results)
            _portEvidenceTile(context, result),
        ],
      ],
    );
  }

  Widget _portEvidenceTile(BuildContext context, PortScanResult result) {
    final appColors = context.appColors;
    final tls = result.tls;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${result.port} · ${result.service} · ${result.confidence}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: appColors.editorText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _riskChip(context, result.riskLevel),
            ],
          ),
          if (result.httpStatus != null)
            _detailRow(context, 'HTTP status', result.httpStatus!),
          if (tls != null) ...[
            _detailRow(context, 'TLS', tls.connected ? 'Connected' : 'Failed'),
            if (tls.protocol != null)
              _detailRow(context, 'Protocol', tls.protocol!),
            if (tls.subject != null)
              _detailRow(context, 'Subject', tls.subject!),
            if (tls.issuer != null) _detailRow(context, 'Issuer', tls.issuer!),
            if (tls.daysUntilExpiry != null)
              _detailRow(context, 'Days left', '${tls.daysUntilExpiry}'),
            if (tls.error != null) _detailRow(context, 'TLS error', tls.error!),
          ],
          if (result.banner.isNotEmpty)
            _detailRow(context, 'Banner', result.banner),
          for (final observation in result.observations)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '- $observation',
                style: _mutedToolTextStyle(context, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReconDetails(BuildContext context) {
    final recon = _recon;
    if (_reconLoading) {
      return Center(
        child: Text('Collecting recon...', style: _mutedToolTextStyle(context)),
      );
    }
    if (recon == null) {
      return Center(
        child: Text(
          'Run recon to collect host details',
          style: _mutedToolTextStyle(context),
        ),
      );
    }

    return ListView(
      children: [
        _detailRow(context, 'Target', recon.target),
        if (recon.resolvedIp != null)
          _detailRow(context, 'Resolved IP', recon.resolvedIp!),
        if (recon.hostname != null)
          _detailRow(context, 'Hostname', recon.hostname!),
        _sectionBlock(context, 'Geolocation', recon.geolocation),
        _sectionBlock(context, 'Whois', recon.whois),
        _dnsBlock(context, recon.dnsRecords),
        _sectionBlock(context, 'SSL/TLS', recon.sslAnalysis),
        _sectionBlock(context, 'Security headers', recon.securityHeaders),
        _technologiesBlock(context, recon.technologies),
        _sectionBlock(context, 'Shodan', recon.shodan),
      ],
    );
  }

  Widget _buildReportPanel(BuildContext context) {
    return EditorPane(
      label: 'Report',
      actions: const [],
      controller: _report,
      readOnly: true,
      placeholder: 'Run a scan or recon to generate a report...',
      showHeader: false,
    );
  }

  Widget _buildHistoryPanel(BuildContext context) {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          'Recent scans will appear here',
          style: _mutedToolTextStyle(context),
        ),
      );
    }
    return ListView.separated(
      itemCount: _history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _history[index];
        return Container(
          decoration: _toolSurfaceDecoration(context, radius: 6),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.target,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appColors.editorText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${item.results.length}/${item.totalPorts} open',
                style: _mutedToolTextStyle(context),
              ),
              const SizedBox(width: 10),
              _riskChip(
                context,
                item.securityScore.grade == 'F' ? 'HIGH' : 'LOW',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionBlock(
    BuildContext context,
    String title,
    Map<String, Object?> values,
  ) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: _toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in values.entries)
                  _detailRow(
                    context,
                    _sentenceLabel(entry.key),
                    '${entry.value}',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dnsBlock(BuildContext context, Map<String, List<String>> records) {
    if (records.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DNS records',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: _toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in records.entries)
                  _detailRow(context, entry.key, entry.value.join('\n')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _technologiesBlock(
    BuildContext context,
    List<Map<String, Object?>> technologies,
  ) {
    if (technologies.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Technologies',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: _toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tech in technologies)
                  _detailRow(
                    context,
                    '${tech['name'] ?? 'Technology'}',
                    [
                      if (tech['value'] != null) tech['value'],
                      if (tech['category'] != null) tech['category'],
                    ].join(' · '),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationTile(
    BuildContext context,
    SecurityRecommendation recommendation,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _riskChip(context, recommendation.priority),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  recommendation.title,
                  style: TextStyle(
                    color: context.appColors.editorText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            recommendation.description,
            style: _mutedToolTextStyle(context, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: TextStyle(
                color: appColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: value.length > 24 ? 'Menlo' : null,
                fontSize: value.length > 24 ? 11.5 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniLabeledField(
    BuildContext context,
    String label, {
    required double width,
    required TextEditingController controller,
    String? suffix,
    required bool enabled,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _mutedToolTextStyle(context)),
        const SizedBox(width: 6),
        SizedBox(
          width: width,
          child: _compactTextField(
            controller: controller,
            hint: '',
            enabled: enabled,
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text(suffix, style: _mutedToolTextStyle(context)),
        ],
      ],
    );
  }

  Widget _compactTextField({
    Key? key,
    required TextEditingController controller,
    required String hint,
    bool enabled = true,
    ValueChanged<String>? onSubmitted,
  }) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: TextField(
        key: key,
        controller: controller,
        enabled: enabled,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: appColors.mutedText),
        ),
        style: TextStyle(
          color: appColors.editorText,
          fontFamily: 'Menlo',
          fontSize: 13,
        ),
      ),
    );
  }

  String _describePorts(PortScanProfile profile) {
    final ports = profile.ports;
    if (ports != null) return ports.join(',');
    return '${profile.startPort}-${profile.endPort}';
  }

  String _secondsLabel(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return seconds == seconds.roundToDouble()
        ? seconds.toStringAsFixed(0)
        : seconds.toStringAsFixed(1);
  }

  String _sentenceLabel(String key) {
    final normalized = key.replaceAll('_', ' ');
    return normalized.isEmpty
        ? normalized
        : normalized[0].toUpperCase() + normalized.substring(1);
  }
}

class _NetworkScannerView extends StatefulWidget {
  const _NetworkScannerView();

  @override
  State<_NetworkScannerView> createState() => _NetworkScannerViewState();
}

class _NetworkScannerViewState extends State<_NetworkScannerView> {
  final TextEditingController _targets = TextEditingController(
    text: '192.168.1.0/24',
  );
  final TextEditingController _ports = TextEditingController();
  final TextEditingController _timeout = TextEditingController();
  final TextEditingController _concurrency = TextEditingController();
  final TextEditingController _report = TextEditingController();
  late final NetworkScannerService _service = NetworkScannerService();
  late final StreamSubscription<NetworkScanProgress> _progressSubscription;

  var _profileName = 'Quick LAN';
  var _reportMode = 'JSON';
  var _detailsIndex = 0;
  var _ping = true;
  var _tcpProbe = true;
  var _scanning = false;
  var _status = 'Ready. Enter a CIDR range or detect the current LAN.';
  String? _error;
  NetworkScanProgress? _progress;
  NetworkScanSummary? _summary;
  NetworkDeviceResult? _selected;
  List<LocalNetworkCandidate> _localNetworks = const [];
  int _requestId = 0;

  static const _customProfileName = 'Custom Ports';

  bool get _isCustomProfile => _profileName == _customProfileName;

  List<String> get _profileNames => [
    ...NetworkScannerService.profiles.map((profile) => profile.name),
    _customProfileName,
  ];

  @override
  void initState() {
    super.initState();
    _syncProfileFields();
    _loadLocalNetworks();
    _progressSubscription = _service.progress.listen((progress) {
      if (!mounted) return;
      setState(() {
        _progress = progress;
        if (progress.active) {
          _status =
              'Scanned ${progress.scanned}/${progress.total} hosts, ${progress.deviceCount} device(s) found.';
        }
      });
    });
  }

  @override
  void dispose() {
    _requestId++;
    _progressSubscription.cancel();
    _service.close();
    _targets.dispose();
    _ports.dispose();
    _timeout.dispose();
    _concurrency.dispose();
    _report.dispose();
    super.dispose();
  }

  void _syncProfileFields() {
    if (_isCustomProfile) {
      if (_ports.text.trim().isEmpty) {
        _ports.text = '22,80,443,8080,8443';
      }
      _timeout.text = '1.0';
      _concurrency.text = '48';
      return;
    }

    final profile = NetworkScannerService.profileByName(_profileName);
    _ports.text = profile.ports.join(',');
    _timeout.text = _secondsLabel(profile.timeout);
    _concurrency.text = profile.concurrency.toString();
  }

  Future<void> _loadLocalNetworks() async {
    final networks = await NetworkScannerService.localNetworks();
    if (!mounted) return;
    setState(() {
      _localNetworks = networks;
      if (networks.isNotEmpty && _targets.text == '192.168.1.0/24') {
        _targets.text = networks.first.cidr;
      }
    });
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    final requestId = ++_requestId;
    late final NetworkScanProfile profile;
    late final List<int>? customPorts;
    late final Duration timeout;
    late final int concurrency;

    try {
      timeout = _parseTimeout();
      concurrency = _parseConcurrency();
      NetworkScannerService.parseNetwork(_targets.text);
      if (_isCustomProfile) {
        customPorts = NetworkScannerService.parsePorts(_ports.text);
        profile = NetworkScanProfile(
          name: _customProfileName,
          description: 'Custom LAN discovery ports',
          ports: customPorts,
          timeout: timeout,
          concurrency: concurrency,
          maxHosts: 512,
        );
      } else {
        customPorts = null;
        profile = NetworkScannerService.profileByName(_profileName);
      }
    } catch (error) {
      setState(() {
        _error = error is FormatException ? error.message : error.toString();
      });
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
      _status = 'Scanning network...';
      _progress = const NetworkScanProgress(
        scanned: 0,
        total: 0,
        active: true,
        deviceCount: 0,
      );
      _summary = null;
      _selected = null;
      _report.clear();
    });

    try {
      final summary = await _service.scan(
        networkText: _targets.text,
        profile: profile,
        ports: customPorts,
        timeout: timeout,
        concurrency: concurrency,
        ping: _ping,
        tcpProbe: _tcpProbe,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _summary = summary;
        _selected = summary.results.isEmpty ? null : summary.results.first;
        _status =
            '${summary.results.length} device(s) found across ${summary.totalHosts} host(s).';
        if (summary.warnings.isNotEmpty) {
          _status = 'Completed with ${summary.warnings.length} warning(s).';
        }
        _scanning = false;
      });
      _refreshReport();
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error is FormatException ? error.message : error.toString();
        _status = 'Scan failed.';
        _scanning = false;
      });
    }
  }

  void _stopScan() {
    _service.cancel();
    setState(() {
      _requestId++;
      _scanning = false;
      _status = 'Stopping scan...';
    });
  }

  Duration _parseTimeout() {
    final seconds = double.tryParse(_timeout.text.trim());
    if (seconds == null || seconds <= 0 || seconds > 30) {
      throw const FormatException(
        'Timeout must be between 0.1 and 30 seconds.',
      );
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  int _parseConcurrency() {
    final value = int.tryParse(_concurrency.text.trim());
    if (value == null || value < 1 || value > 96) {
      throw const FormatException('Concurrency must be between 1 and 96.');
    }
    return value;
  }

  void _selectResult(NetworkDeviceResult result) {
    setState(() {
      _selected = result;
      _detailsIndex = 0;
    });
  }

  void _refreshReport() {
    final summary = _summary;
    if (summary == null) {
      _report.clear();
      return;
    }
    _report.text = _reportMode == 'CSV'
        ? summary.toCsvReport()
        : summary.toJsonReport();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildControls(context),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_scanning) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _error ?? _status,
                  style: _error == null
                      ? _mutedToolTextStyle(context)
                      : _errorToolTextStyle(context),
                ),
              ),
              if (progress != null && progress.total > 0) ...[
                SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(value: progress.ratio),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(progress.ratio * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: appColors.mutedText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _ResizableSplit(
              horizontal: true,
              initialRatio: 0.54,
              minFirstExtent: 360,
              minSecondExtent: 320,
              first: _buildResultsPanel(context),
              second: _buildDetailsPanel(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Network',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(
                width: 320,
                child: _networkTextField(
                  key: const ValueKey('network-scanner-targets'),
                  controller: _targets,
                  hint: '192.168.1.0/24',
                  enabled: !_scanning,
                  onSubmitted: (_) => _startScan(),
                ),
              ),
              ToolButton(
                label: 'Detect LAN',
                onPressed: _scanning || _localNetworks.isEmpty
                    ? null
                    : () {
                        setState(
                          () => _targets.text = _localNetworks.first.cidr,
                        );
                      },
              ),
              SmallDropdown(
                key: ValueKey('network-profile-$_profileName'),
                items: _profileNames,
                initialValue: _profileName,
                width: 180,
                onChanged: (value) {
                  setState(() {
                    _profileName = value;
                    _syncProfileFields();
                  });
                },
              ),
              SizedBox(
                width: 260,
                child: _networkTextField(
                  controller: _ports,
                  hint: '22,80,443 or 8000-8010',
                  enabled: _isCustomProfile && !_scanning && _tcpProbe,
                ),
              ),
              ToolButton(
                label: 'Scan',
                onPressed: _scanning ? null : _startScan,
              ),
              ToolButton(
                label: 'Stop',
                onPressed: _scanning ? _stopScan : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _networkMiniField(
                context,
                'Timeout',
                controller: _timeout,
                width: 74,
                suffix: 's',
                enabled: !_scanning,
              ),
              _networkMiniField(
                context,
                'Concurrency',
                controller: _concurrency,
                width: 70,
                enabled: !_scanning,
              ),
              _networkCheckbox(
                context,
                label: 'Ping',
                value: _ping,
                onChanged: _scanning
                    ? null
                    : (value) => setState(() => _ping = value ?? true),
              ),
              _networkCheckbox(
                context,
                label: 'TCP ports',
                value: _tcpProbe,
                onChanged: _scanning
                    ? null
                    : (value) => setState(() => _tcpProbe = value ?? true),
              ),
              Text(
                _isCustomProfile
                    ? 'Custom device discovery'
                    : NetworkScannerService.profileByName(
                        _profileName,
                      ).description,
                style: _mutedToolTextStyle(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel(BuildContext context) {
    final summary = _summary;
    final results = summary?.results ?? const <NetworkDeviceResult>[];
    return Container(
      decoration: _toolSurfaceDecoration(context),
      child: results.isEmpty && (summary?.warnings.isEmpty ?? true)
          ? Center(
              child: Text(
                _scanning
                    ? 'Scanning network...'
                    : 'Responsive devices will appear here',
                style: _mutedToolTextStyle(context),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(10),
              children: [
                _buildNetworkStats(context, summary),
                if (summary != null && summary.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final warning in summary.warnings)
                    _networkWarningTile(context, warning),
                ],
                const SizedBox(height: 8),
                for (final result in results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _networkResultTile(context, result),
                  ),
              ],
            ),
    );
  }

  Widget _buildNetworkStats(BuildContext context, NetworkScanSummary? summary) {
    final total = summary?.totalHosts ?? _progress?.total ?? 0;
    final open = summary?.results.length ?? 0;
    final ping = summary?.pingCount ?? 0;
    final ports = summary?.openPortCount ?? 0;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _networkPill(context, 'Devices', '$open'),
        _networkPill(context, 'Hosts', '$total'),
        _networkPill(context, 'Ping', '$ping'),
        _networkPill(context, 'Ports', '$ports'),
      ],
    );
  }

  Widget _networkResultTile(BuildContext context, NetworkDeviceResult result) {
    final appColors = context.appColors;
    final selected = identical(_selected, result);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _selectResult(result),
      child: Container(
        decoration: BoxDecoration(
          color: appColors.panelElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? appColors.accent : appColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: appColors.editorText,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  result.evidenceLabel,
                  style: _mutedToolTextStyle(context, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              result.openPorts.isEmpty
                  ? 'No probed TCP ports open'
                  : result.openPorts
                        .map((port) => '${port.port}/${port.service}')
                        .join('  '),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appColors.editorText),
            ),
            if (result.latencyMs != null) ...[
              const SizedBox(height: 6),
              Text(
                '${result.latencyMs} ms ping response',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: appColors.mutedText,
                  fontFamily: 'Menlo',
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _networkWarningTile(BuildContext context, String warning) {
    final appColors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: appColors.warning.withAlpha(24),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.warning.withAlpha(120)),
      ),
      padding: const EdgeInsets.all(10),
      child: Text(
        warning,
        style: TextStyle(color: appColors.editorText, fontSize: 12),
      ),
    );
  }

  Widget _buildDetailsPanel(BuildContext context) {
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SegmentedToggle(
                  options: const ['Evidence', 'Report'],
                  initialIndex: _detailsIndex,
                  onChanged: (index) => setState(() => _detailsIndex = index),
                ),
                if (_detailsIndex == 1) ...[
                  const SizedBox(width: 10),
                  SmallDropdown(
                    key: ValueKey('network-report-$_reportMode'),
                    items: const ['JSON', 'CSV'],
                    initialValue: _reportMode,
                    width: 90,
                    onChanged: (value) {
                      setState(() => _reportMode = value);
                      _refreshReport();
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _detailsIndex == 0
                ? _buildEvidencePanel(context)
                : EditorPane(
                    label: 'Report',
                    actions: const [],
                    controller: _report,
                    readOnly: true,
                    placeholder: 'Run a network scan to generate a report...',
                    showHeader: false,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidencePanel(BuildContext context) {
    final selected = _selected;
    if (selected == null) {
      return Center(
        child: Text(
          'Select a device to inspect discovery evidence',
          style: _mutedToolTextStyle(context),
        ),
      );
    }

    return ListView(
      children: [
        _networkDetailRow(context, 'IP address', selected.ip),
        if (selected.hostname != null)
          _networkDetailRow(context, 'Hostname', selected.hostname!),
        _networkDetailRow(
          context,
          'Ping',
          selected.pingResponded ? 'Responded' : 'No response',
        ),
        if (selected.latencyMs != null)
          _networkDetailRow(context, 'Latency', '${selected.latencyMs} ms'),
        _networkDetailRow(
          context,
          'Open ports',
          selected.openPorts.isEmpty
              ? 'None found in the selected probe set'
              : selected.openPorts.map((port) => port.port).join(', '),
        ),
        const SizedBox(height: 12),
        Text(
          'Services',
          style: TextStyle(
            color: context.appColors.editorText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        if (selected.openPorts.isEmpty)
          Text(
            'The device responded to ping but did not expose any probed TCP ports.',
            style: _mutedToolTextStyle(context),
          )
        else
          for (final port in selected.openPorts)
            _networkServiceRow(context, port),
        if (_summary?.warnings.isNotEmpty ?? false) ...[
          const SizedBox(height: 12),
          Text(
            'Warnings',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final warning in _summary!.warnings)
            _networkBullet(context, warning),
        ],
      ],
    );
  }

  Widget _networkServiceRow(BuildContext context, NetworkDevicePort port) {
    final appColors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              port.port.toString(),
              style: TextStyle(
                color: appColors.editorText,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${port.service} · ${port.protocol} · ${port.category}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appColors.editorText),
            ),
          ),
          if (port.encrypted)
            Text(
              'encrypted',
              style: TextStyle(
                color: appColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _networkPill(BuildContext context, String label, String value) {
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: _mutedToolTextStyle(context, fontSize: 12)),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkDetailRow(BuildContext context, String label, String value) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                color: appColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: value.length > 22 ? 'Menlo' : null,
                fontSize: value.length > 22 ? 11.5 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkBullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('- ', style: TextStyle(color: context.appColors.mutedText)),
          Expanded(
            child: Text(
              text,
              style: _mutedToolTextStyle(context, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkCheckbox(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool?>? onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: onChanged),
        Text(label, style: TextStyle(color: context.appColors.editorText)),
      ],
    );
  }

  Widget _networkMiniField(
    BuildContext context,
    String label, {
    required TextEditingController controller,
    required double width,
    String? suffix,
    required bool enabled,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _mutedToolTextStyle(context)),
        const SizedBox(width: 6),
        SizedBox(
          width: width,
          child: _networkTextField(
            controller: controller,
            hint: '',
            enabled: enabled,
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text(suffix, style: _mutedToolTextStyle(context)),
        ],
      ],
    );
  }

  Widget _networkTextField({
    Key? key,
    required TextEditingController controller,
    required String hint,
    bool enabled = true,
    ValueChanged<String>? onSubmitted,
  }) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: TextField(
        key: key,
        controller: controller,
        enabled: enabled,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: appColors.mutedText),
        ),
        style: TextStyle(
          color: appColors.editorText,
          fontFamily: 'Menlo',
          fontSize: 13,
        ),
      ),
    );
  }

  String _secondsLabel(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return seconds == seconds.roundToDouble()
        ? seconds.toStringAsFixed(0)
        : seconds.toStringAsFixed(1);
  }
}

class _FirewallFingerprintView extends StatefulWidget {
  const _FirewallFingerprintView();

  @override
  State<_FirewallFingerprintView> createState() =>
      _FirewallFingerprintViewState();
}

class _FirewallFingerprintViewState extends State<_FirewallFingerprintView> {
  final TextEditingController _target = TextEditingController();
  final TextEditingController _timeout = TextEditingController(text: '7');
  final TextEditingController _report = TextEditingController();
  late final FirewallFingerprintService _service = FirewallFingerprintService();

  var _findAll = true;
  var _followRedirects = true;
  var _loading = false;
  var _detailsIndex = 0;
  var _reportMode = 'JSON';
  var _status = 'Ready.';
  String? _error;
  FirewallFingerprintResult? _result;
  int _requestId = 0;

  @override
  void dispose() {
    _requestId++;
    _service.close();
    _target.dispose();
    _timeout.dispose();
    _report.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_loading) return;
    final requestId = ++_requestId;
    late final Duration timeout;
    try {
      FirewallFingerprintService.normalizeUrl(_target.text);
      final seconds = int.tryParse(_timeout.text.trim());
      if (seconds == null || seconds < 1 || seconds > 30) {
        throw const FormatException(
          'Timeout must be between 1 and 30 seconds.',
        );
      }
      timeout = Duration(seconds: seconds);
    } catch (e) {
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = 'Fingerprinting target...';
      _result = null;
      _report.clear();
    });

    try {
      final result = await _service.scan(
        target: _target.text,
        findAll: _findAll,
        followRedirects: _followRedirects,
        timeout: timeout,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _result = result;
        _status = result.detected
            ? '${result.detections.length} signature match${result.detections.length == 1 ? '' : 'es'} found.'
            : 'No firewall signature detected.';
        _loading = false;
      });
      _refreshFirewallReport();
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _status = 'Fingerprint failed.';
        _loading = false;
      });
    }
  }

  void _setSample() {
    _target.text = 'https://www.cloudflare.com/';
  }

  void _refreshFirewallReport() {
    final result = _result;
    if (result == null) {
      _report.clear();
      return;
    }
    _report.text = _reportMode == 'JSON'
        ? result.toJsonReport()
        : result.toTextReport();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFirewallControls(context),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_loading) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _error ?? _status,
                  style: _error == null
                      ? _mutedToolTextStyle(context)
                      : _errorToolTextStyle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _ResizableSplit(
              horizontal: true,
              initialRatio: 0.52,
              minFirstExtent: 340,
              minSecondExtent: 320,
              first: _buildFirewallResults(context),
              second: _buildFirewallDetails(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirewallControls(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Target',
            style: TextStyle(
              color: appColors.editorText,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(
            width: 330,
            child: _firewallTextField(
              key: const ValueKey('firewall-fingerprint-target'),
              controller: _target,
              hint: 'https://example.com/',
              onSubmitted: (_) => _scan(),
            ),
          ),
          _firewallMiniField(
            context,
            'Timeout',
            _timeout,
            width: 64,
            suffix: 's',
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _findAll,
                onChanged: _loading
                    ? null
                    : (value) => setState(() => _findAll = value ?? true),
              ),
              Text('Find all', style: TextStyle(color: appColors.editorText)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _followRedirects,
                onChanged: _loading
                    ? null
                    : (value) {
                        setState(() => _followRedirects = value ?? true);
                      },
              ),
              Text('Redirects', style: TextStyle(color: appColors.editorText)),
            ],
          ),
          ToolButton(label: 'Sample', onPressed: _loading ? null : _setSample),
          ToolButton(label: 'Fingerprint', onPressed: _loading ? null : _scan),
        ],
      ),
    );
  }

  Widget _buildFirewallResults(BuildContext context) {
    final result = _result;
    final detections = result?.detections ?? const <FirewallDetection>[];
    return Container(
      decoration: _toolSurfaceDecoration(context),
      child: result == null
          ? Center(
              child: Text(
                _loading
                    ? 'Running probes...'
                    : 'Firewall matches will appear here',
                style: _mutedToolTextStyle(context),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(10),
              children: [
                _firewallSummary(context, result),
                const SizedBox(height: 10),
                if (detections.isEmpty && result.genericDetected)
                  _genericFirewallTile(context, result.genericReason)
                else if (detections.isEmpty)
                  Text(
                    'No WAF detected by signature or generic probes.',
                    style: _mutedToolTextStyle(context),
                  )
                else
                  for (final detection in detections)
                    _firewallDetectionTile(context, detection),
              ],
            ),
    );
  }

  Widget _firewallSummary(
    BuildContext context,
    FirewallFingerprintResult result,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _firewallPill(context, 'Detected', result.detected ? 'Yes' : 'No'),
        _firewallPill(context, 'Matches', '${result.detections.length}'),
        _firewallPill(context, 'Requests', '${result.requestCount}'),
        _firewallPill(
          context,
          'Generic',
          result.genericDetected ? 'Yes' : 'No',
        ),
      ],
    );
  }

  Widget _firewallDetectionTile(
    BuildContext context,
    FirewallDetection detection,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detection.firewall,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appColors.editorText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _firewallConfidence(context, detection.confidence),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detection.manufacturer,
            style: _mutedToolTextStyle(context, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final evidence in detection.evidence.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                evidence,
                style: TextStyle(
                  color: context.appColors.mutedText,
                  fontFamily: 'Menlo',
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _genericFirewallTile(BuildContext context, String reason) {
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Generic firewall behavior',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(reason, style: _mutedToolTextStyle(context)),
        ],
      ),
    );
  }

  Widget _buildFirewallDetails(BuildContext context) {
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SegmentedToggle(
                  options: const ['Probes', 'Report'],
                  initialIndex: _detailsIndex,
                  onChanged: (index) => setState(() => _detailsIndex = index),
                ),
                if (_detailsIndex == 1) ...[
                  const SizedBox(width: 10),
                  SmallDropdown(
                    key: ValueKey('firewall-report-$_reportMode'),
                    items: const ['JSON', 'Text'],
                    initialValue: _reportMode,
                    width: 90,
                    onChanged: (value) {
                      setState(() => _reportMode = value);
                      _refreshFirewallReport();
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _detailsIndex == 0
                ? _buildProbeList(context)
                : EditorPane(
                    label: 'Report',
                    actions: const [],
                    controller: _report,
                    readOnly: true,
                    placeholder:
                        'Run a fingerprint scan to generate a report...',
                    showHeader: false,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProbeList(BuildContext context) {
    final probes = _result?.probes ?? const <FirewallProbeResponse>[];
    if (probes.isEmpty) {
      return Center(
        child: Text(
          'Probe results will appear here',
          style: _mutedToolTextStyle(context),
        ),
      );
    }
    return ListView.separated(
      itemCount: probes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final probe = probes[index];
        return Container(
          decoration: _toolSurfaceDecoration(context, radius: 6),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      probe.name,
                      style: TextStyle(
                        color: context.appColors.editorText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'HTTP ${probe.statusCode}',
                    style: TextStyle(
                      color: context.appColors.editorText,
                      fontFamily: 'Menlo',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                probe.url.toString(),
                overflow: TextOverflow.ellipsis,
                style: _mutedToolTextStyle(context, fontSize: 11),
              ),
              if (probe.bodySnippet.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  probe.bodySnippet.replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appColors.mutedText,
                    fontFamily: 'Menlo',
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _firewallPill(BuildContext context, String label, String value) {
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: _mutedToolTextStyle(context, fontSize: 12)),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _firewallConfidence(BuildContext context, int confidence) {
    final appColors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: appColors.accent.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appColors.accent.withAlpha(150)),
      ),
      child: Text(
        '$confidence%',
        style: TextStyle(
          color: appColors.accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _firewallMiniField(
    BuildContext context,
    String label,
    TextEditingController controller, {
    required double width,
    String? suffix,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _mutedToolTextStyle(context)),
        const SizedBox(width: 6),
        SizedBox(
          width: width,
          child: _firewallTextField(controller: controller, hint: ''),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text(suffix, style: _mutedToolTextStyle(context)),
        ],
      ],
    );
  }

  Widget _firewallTextField({
    Key? key,
    required TextEditingController controller,
    required String hint,
    ValueChanged<String>? onSubmitted,
  }) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: TextField(
        key: key,
        controller: controller,
        enabled: !_loading,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: appColors.mutedText),
        ),
        style: TextStyle(
          color: appColors.editorText,
          fontFamily: 'Menlo',
          fontSize: 13,
        ),
      ),
    );
  }
}

class _UuidUlidView extends StatefulWidget {
  const _UuidUlidView();

  @override
  State<_UuidUlidView> createState() => _UuidUlidViewState();
}

class _UuidUlidViewState extends State<_UuidUlidView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _standard = TextEditingController();
  final TextEditingController _raw = TextEditingController();
  final TextEditingController _version = TextEditingController();
  final TextEditingController _variant = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final TextEditingController _clock = TextEditingController();
  final TextEditingController _node = TextEditingController();
  final TextEditingController _count = TextEditingController(text: '1');
  final TextEditingController _generated = TextEditingController();
  String _type = 'UUID v4';
  bool _lowercase = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _standard.dispose();
    _raw.dispose();
    _version.dispose();
    _variant.dispose();
    _time.dispose();
    _clock.dispose();
    _node.dispose();
    _count.dispose();
    _generated.dispose();
    super.dispose();
  }

  void _decode() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _clearDecodedFields();
      setState(() => _error = null);
      return;
    }

    final uuid = _normalizeUuid(text);
    if (uuid != null) {
      _applyUuid(uuid);
      setState(() => _error = null);
      return;
    }

    final ulid = _normalizeUlid(text);
    if (ulid != null) {
      _applyUlid(ulid);
      setState(() => _error = null);
      return;
    }

    _clearDecodedFields();
    setState(() => _error = 'Not a valid UUID or ULID.');
  }

  void _clearDecodedFields() {
    _standard.clear();
    _raw.clear();
    _version.clear();
    _variant.clear();
    _time.clear();
    _clock.clear();
    _node.clear();
  }

  String? _normalizeUuid(String text) {
    final compact = text.replaceAll('-', '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(compact)) return null;
    return '${compact.substring(0, 8)}-${compact.substring(8, 12)}-'
        '${compact.substring(12, 16)}-${compact.substring(16, 20)}-'
        '${compact.substring(20)}';
  }

  String? _normalizeUlid(String text) {
    final normalized = text.trim().toUpperCase();
    if (RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$').hasMatch(normalized)) {
      return normalized;
    }
    return null;
  }

  void _applyUuid(String uuid) {
    final raw = uuid.replaceAll('-', '');
    final version = raw[12];
    final variantNibble = int.parse(raw[16], radix: 16);
    _standard.text = uuid;
    _raw.text = raw;
    _version.text = 'UUID v$version';
    _variant.text = variantNibble >= 8 && variantNibble <= 11
        ? 'RFC 4122'
        : 'Reserved';

    if (version == '1') {
      final timeLow = int.parse(raw.substring(0, 8), radix: 16);
      final timeMid = int.parse(raw.substring(8, 12), radix: 16);
      final timeHigh = int.parse(raw.substring(12, 16), radix: 16) & 0x0fff;
      final timestamp = (timeHigh << 48) | (timeMid << 32) | timeLow;
      const uuidEpochOffset = 0x01B21DD213814000;
      final microsSinceUnix = (timestamp - uuidEpochOffset) ~/ 10;
      _time.text = DateTime.fromMicrosecondsSinceEpoch(
        microsSinceUnix,
        isUtc: true,
      ).toIso8601String();
      final clockSequence =
          int.parse(raw.substring(16, 20), radix: 16) & 0x3fff;
      _clock.text = clockSequence.toRadixString(16).padLeft(4, '0');
      _node.text = raw
          .substring(20)
          .replaceAllMapped(RegExp(r'.{2}'), (match) => '${match.group(0)}:')
          .replaceFirst(RegExp(r':$'), '');
    } else {
      _time.text = version == '7' ? 'Embedded timestamp' : 'Not time based';
      _clock.clear();
      _node.clear();
    }
  }

  void _applyUlid(String ulid) {
    _standard.text = ulid;
    _raw.text = ulid;
    _version.text = 'ULID';
    _variant.text = 'Crockford Base32';
    final timestamp = _decodeUlidTimestamp(ulid);
    _time.text = timestamp == null
        ? ''
        : DateTime.fromMillisecondsSinceEpoch(
            timestamp,
            isUtc: true,
          ).toIso8601String();
    _clock.clear();
    _node.clear();
  }

  int? _decodeUlidTimestamp(String ulid) {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    var value = 0;
    for (final codeUnit in ulid.substring(0, 10).codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(codeUnit));
      if (index < 0) return null;
      value = value * 32 + index;
    }
    return value;
  }

  String _uuidV4() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = _bytesToHex(bytes, lower: true);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _uuidV1() {
    final rand = Random.secure();
    final now = DateTime.now().toUtc();
    const uuidEpochOffset = 0x01B21DD213814000;
    final timestamp = now.microsecondsSinceEpoch * 10 + uuidEpochOffset;
    final timeLow = timestamp & 0xffffffff;
    final timeMid = (timestamp >> 32) & 0xffff;
    final timeHigh = ((timestamp >> 48) & 0x0fff) | 0x1000;
    final clockSeq = rand.nextInt(0x4000);
    final clockHi = ((clockSeq >> 8) & 0x3f) | 0x80;
    final clockLow = clockSeq & 0xff;
    final node = List<int>.generate(6, (_) => rand.nextInt(256));
    node[0] = node[0] | 0x01;
    final nodeHex = _bytesToHex(node, lower: true);
    return '${timeLow.toRadixString(16).padLeft(8, '0')}-'
        '${timeMid.toRadixString(16).padLeft(4, '0')}-'
        '${timeHigh.toRadixString(16).padLeft(4, '0')}-'
        '${clockHi.toRadixString(16).padLeft(2, '0')}'
        '${clockLow.toRadixString(16).padLeft(2, '0')}-$nodeHex';
  }

  String _ulid() {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final rand = Random.secure();
    var timestamp = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    final timeChars = List<String>.filled(10, '0');
    for (var i = 9; i >= 0; i--) {
      timeChars[i] = alphabet[timestamp & 0x1f];
      timestamp >>= 5;
    }
    buffer.writeAll(timeChars);
    for (var i = 0; i < 16; i++) {
      buffer.write(alphabet[rand.nextInt(32)]);
    }
    return buffer.toString();
  }

  void _generate() {
    final count = (int.tryParse(_count.text) ?? 1).clamp(1, 100).toInt();
    final values = <String>[];
    for (var i = 0; i < count; i++) {
      switch (_type) {
        case 'UUID v1':
          values.add(_uuidV1());
          break;
        case 'ULID':
          values.add(_ulid());
          break;
        default:
          values.add(_uuidV4());
      }
    }
    var output = values.join('\n');
    if (!_lowercase && !_type.startsWith('ULID')) {
      output = output.toUpperCase();
    } else if (_lowercase) {
      output = output.toLowerCase();
    }
    setState(() => _generated.text = output);
  }

  Future<void> _copyGenerated() async {
    await Clipboard.setData(ClipboardData(text: _generated.text));
  }

  void _clearGenerated() {
    setState(() => _generated.clear());
  }

  @override
  Widget build(BuildContext context) {
    return _ResizableSplit(
      horizontal: true,
      initialRatio: 0.5,
      minFirstExtent: 360,
      minSecondExtent: 380,
      first: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditorPane(
                label: 'Input',
                actions: [
                  ToolButton(
                    label: 'Clipboard',
                    onPressed: () async {
                      final text = await _readClipboardText();
                      setState(() => _input.text = text);
                      _decode();
                    },
                  ),
                  ToolButton(
                    label: 'Sample',
                    onPressed: () {
                      setState(() => _input.text = _uuidV4());
                      _decode();
                    },
                  ),
                  ToolButton(
                    label: 'Clear',
                    onPressed: () {
                      setState(() => _input.clear());
                      _decode();
                    },
                  ),
                ],
                controller: _input,
                onChanged: (_) => _decode(),
                placeholder: '00000000-0000-0000-0000-000000000000',
                expand: false,
                fixedHeight: 104,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: _errorToolTextStyle(context)),
              ],
              const SizedBox(height: 12),
              _IdDetailsPanel(
                rows: [
                  _IdDetailRowData('Standard', _standard.text),
                  _IdDetailRowData('Raw', _raw.text),
                  _IdDetailRowData('Type', _version.text),
                  _IdDetailRowData('Variant', _variant.text),
                  _IdDetailRowData('Time', _time.text),
                  _IdDetailRowData('Clock ID', _clock.text),
                  _IdDetailRowData('Node', _node.text),
                ],
              ),
            ],
          ),
        ),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: _toolSurfaceDecoration(context, radius: 8),
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Generate',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SmallDropdown(
                  items: const ['UUID v4', 'UUID v1', 'ULID'],
                  initialValue: _type,
                  width: 128,
                  onChanged: (value) => setState(() => _type = value),
                ),
                _InlineTextField(width: 56, hintText: '1', controller: _count),
                ToolButton(label: 'Generate', onPressed: _generate),
                Checkbox(
                  value: _lowercase,
                  onChanged: (value) =>
                      setState(() => _lowercase = value ?? false),
                ),
                const Text('lowercase'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Generated IDs',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              ToolButton(label: 'Reset output', onPressed: _clearGenerated),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EditorPane(
              label: '',
              actions: const [],
              controller: _generated,
              readOnly: true,
              placeholder: 'Generated IDs...',
              copyAction: _copyGenerated,
              showHeader: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdDetailRowData {
  const _IdDetailRowData(this.label, this.value);

  final String label;
  final String value;
}

class _IdDetailsPanel extends StatelessWidget {
  const _IdDetailsPanel({required this.rows});

  final List<_IdDetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final hasData = rows.any((row) => row.value.isNotEmpty);
    return Container(
      width: double.infinity,
      decoration: _toolSurfaceDecoration(context, radius: 8),
      padding: const EdgeInsets.all(12),
      child: hasData
          ? Column(
              children: [
                for (final row in rows)
                  _IdDetailRow(label: row.label, value: row.value),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Paste a UUID or ULID to decode it.',
                  style: TextStyle(color: appColors.mutedText),
                ),
              ),
            ),
    );
  }
}

class _IdDetailRow extends StatelessWidget {
  const _IdDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                color: appColors.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: 'Menlo',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HtmlPreviewView extends StatefulWidget {
  const _HtmlPreviewView();

  @override
  State<_HtmlPreviewView> createState() => _HtmlPreviewViewState();
}

class _HtmlPreviewViewState extends State<_HtmlPreviewView> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    const sample = '''
<!doctype html>
<html>
<body>
  <h1>Hello from DevUtils</h1>
  <p>This is a rendered HTML preview.</p>
</body>
</html>''';
    setState(() => _input.text = sample);
  }

  void _clear() {
    setState(() => _input.clear());
  }

  @override
  Widget build(BuildContext context) {
    return _ResizableSplit(
      horizontal: false,
      initialRatio: 0.42,
      minFirstExtent: 110,
      minSecondExtent: 120,
      first: EditorPane(
        label: 'Input',
        actions: [
          ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
          ToolButton(label: 'Sample', onPressed: _setSample),
          ToolButton(label: 'Clear', onPressed: _clear),
        ],
        controller: _input,
        onChanged: (_) => setState(() {}),
        placeholder: '<html>...</html>',
      ),
      second: _RenderedPreviewPane(
        label: 'Preview',
        html: _input.text,
        badge: 'Rendered HTML',
      ),
    );
  }
}

class _TextDiffView extends StatefulWidget {
  const _TextDiffView();

  @override
  State<_TextDiffView> createState() => _TextDiffViewState();
}

class _TextDiffViewState extends State<_TextDiffView> {
  final TextEditingController _left = TextEditingController();
  final TextEditingController _right = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _mode = 'Characters';

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final left = _left.text;
    final right = _right.text;
    List<String> leftParts;
    List<String> rightParts;
    if (_mode == 'Words') {
      leftParts = left.split(RegExp(r'\s+'));
      rightParts = right.split(RegExp(r'\s+'));
    } else if (_mode == 'Lines') {
      leftParts = left.split('\n');
      rightParts = right.split('\n');
    } else {
      leftParts = left.split('');
      rightParts = right.split('');
    }
    final removed = leftParts
        .where((item) => !rightParts.contains(item))
        .toList();
    final added = rightParts
        .where((item) => !leftParts.contains(item))
        .toList();
    final buffer = StringBuffer();
    for (final item in removed) {
      buffer.writeln('- $item');
    }
    for (final item in added) {
      buffer.writeln('+ $item');
    }
    setState(() => _output.text = buffer.toString().trimRight());
  }

  void _swap() {
    final temp = _left.text;
    _left.text = _right.text;
    _right.text = temp;
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final inputComparison = _ResizableSplit(
      horizontal: true,
      first: EditorPane(
        label: 'Input 1',
        actions: [
          ToolButton(
            label: 'Clipboard',
            onPressed: () async {
              final text = await _readClipboardText();
              setState(() => _left.text = text);
              _run();
            },
          ),
          ToolButton(
            label: 'Sample',
            onPressed: () {
              setState(() => _left.text = 'Line one\nLine two');
              _run();
            },
          ),
          ToolButton(
            label: 'Clear',
            onPressed: () {
              setState(() => _left.clear());
              _run();
            },
          ),
        ],
        controller: _left,
        onChanged: (_) => _run(),
      ),
      second: EditorPane(
        label: 'Input 2',
        actions: [
          ToolButton(
            label: 'Clipboard',
            onPressed: () async {
              final text = await _readClipboardText();
              setState(() => _right.text = text);
              _run();
            },
          ),
          ToolButton(
            label: 'Clear',
            onPressed: () {
              setState(() => _right.clear());
              _run();
            },
          ),
          ToolButton(label: 'Swap Inputs', onPressed: _swap),
        ],
        controller: _right,
        onChanged: (_) => _run(),
      ),
    );

    final outputPane = Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Diff mode:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SegmentedToggle(
              options: const ['Characters', 'Words', 'Lines'],
              initialIndex: 0,
              onChanged: (index) {
                setState(
                  () => _mode = const ['Characters', 'Words', 'Lines'][index],
                );
                _run();
              },
            ),
            const SizedBox(width: 8),
            const Text(
              'Output:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SmallDropdown(
              items: ['Formatted Text', 'Plain Text'],
              initialValue: 'Formatted Text',
            ),
            const Icon(Icons.chevron_left, size: 16),
            Text(
              '${_output.text.split('\n').where((line) => line.isNotEmpty).length}',
            ),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: EditorPane(
            label: '',
            actions: [
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            controller: _output,
            readOnly: true,
            placeholder: 'Diff output...',
          ),
        ),
      ],
    );

    return _ResizableSplit(
      horizontal: false,
      initialRatio: 0.66,
      first: inputComparison,
      second: outputPane,
    );
  }
}

class _NumberBaseConverterView extends StatefulWidget {
  const _NumberBaseConverterView();

  @override
  State<_NumberBaseConverterView> createState() =>
      _NumberBaseConverterViewState();
}

class _NumberBaseConverterViewState extends State<_NumberBaseConverterView> {
  final TextEditingController _input = TextEditingController(
    text: '0xDEADBEEF',
  );
  String _customBase = '36';
  String _inputBase = 'Auto';
  String _width = '32';
  String _interpretation = 'Unsigned';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  _ParsedNumber? _parseCurrent() {
    try {
      return _parseBigIntInput(
        _input.text,
        selectedBase: _inputBase,
        customBase: int.tryParse(_customBase) ?? 10,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parseCurrent();
    final customBase = int.tryParse(_customBase) ?? 36;
    final outputs = parsed == null
        ? const <_BaseConversionOutput>[]
        : _buildBaseOutputs(parsed.value, customBase);
    final widthBits = int.tryParse(_width);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNumberInput(context),
          const SizedBox(height: 10),
          if (parsed == null)
            Text(
              'Enter a valid value for the selected base.',
              style: _errorToolTextStyle(context),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _numberPill(context, 'Detected', 'Base ${parsed.detectedBase}'),
                _numberPill(
                  context,
                  'Digits',
                  _digitCount(parsed.value).toString(),
                ),
                _numberPill(
                  context,
                  'Bits',
                  _bitLength(parsed.value).toString(),
                ),
                _numberPill(
                  context,
                  'Bytes',
                  _byteLength(parsed.value).toString(),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _ResizableSplit(
              horizontal: true,
              initialRatio: 0.62,
              minFirstExtent: 420,
              minSecondExtent: 300,
              first: Container(
                decoration: _toolSurfaceDecoration(context),
                child: parsed == null
                    ? Center(
                        child: Text(
                          'Converted bases will appear here',
                          style: _mutedToolTextStyle(context),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: outputs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _BaseOutputRow(output: outputs[index]);
                        },
                      ),
              ),
              second: Container(
                decoration: _toolSurfaceDecoration(context),
                padding: const EdgeInsets.all(12),
                child: parsed == null
                    ? Center(
                        child: Text(
                          'Inspector details will appear here',
                          style: _mutedToolTextStyle(context),
                        ),
                      )
                    : _NumberInspector(
                        value: parsed.value,
                        widthBits: widthBits,
                        interpretation: _interpretation,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberInput(BuildContext context) {
    final appColors = context.appColors;
    final baseOptions = const [
      'Auto',
      'Binary',
      'Octal',
      'Decimal',
      'Hex',
      'Custom',
    ];
    final customBaseOptions = List<String>.generate(
      35,
      (index) => (index + 2).toString(),
    );
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Input',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SmallDropdown(
                key: ValueKey('number-input-base-$_inputBase'),
                items: baseOptions,
                initialValue: _inputBase,
                width: 120,
                onChanged: (value) => setState(() => _inputBase = value),
              ),
              if (_inputBase == 'Custom')
                SmallDropdown(
                  key: ValueKey('number-custom-base-$_customBase'),
                  items: customBaseOptions,
                  initialValue: _customBase,
                  width: 82,
                  onChanged: (value) => setState(() => _customBase = value),
                ),
              SmallDropdown(
                key: ValueKey('number-width-$_width'),
                items: const ['Auto', '8', '16', '32', '64', '128', '256'],
                initialValue: _width,
                width: 104,
                onChanged: (value) => setState(() => _width = value),
              ),
              SmallDropdown(
                key: ValueKey('number-interpretation-$_interpretation'),
                items: const ['Unsigned', 'Signed'],
                initialValue: _interpretation,
                width: 118,
                onChanged: (value) => setState(() => _interpretation = value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: _toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              key: const ValueKey('number-base-input'),
              controller: _input,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: '0b1010, 0o755, 123456, 0xDEADBEEF',
                hintStyle: TextStyle(color: appColors.mutedText),
              ),
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: 'Menlo',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberPill(BuildContext context, String label, String value) {
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: _mutedToolTextStyle(context, fontSize: 12)),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _BaseConversionOutput {
  const _BaseConversionOutput({
    required this.label,
    required this.base,
    required this.prefix,
    required this.value,
    required this.groupedValue,
  });

  final String label;
  final int base;
  final String prefix;
  final String value;
  final String groupedValue;
}

class _ParsedNumber {
  const _ParsedNumber({required this.value, required this.detectedBase});

  final BigInt value;
  final int detectedBase;
}

class _BaseOutputRow extends StatelessWidget {
  const _BaseOutputRow({required this.output});

  final _BaseConversionOutput output;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final prefixed = '${output.prefix}${output.value}';
    return Listener(
      onPointerDown: (event) {
        if ((event.buttons & kSecondaryMouseButton) != 0) {
          _showBaseValueMenu(context, event.position, output);
        }
      },
      child: Container(
        decoration: _toolSurfaceDecoration(context, radius: 6),
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    output.label,
                    style: TextStyle(
                      color: appColors.editorText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'base ${output.base}',
                    style: _mutedToolTextStyle(context, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      prefixed,
                      style: TextStyle(
                        color: appColors.editorText,
                        fontFamily: 'Menlo',
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  if (output.groupedValue != output.value) ...[
                    const SizedBox(height: 5),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        output.groupedValue,
                        style: TextStyle(
                          color: appColors.mutedText,
                          fontFamily: 'Menlo',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBaseValueMenu(
    BuildContext context,
    Offset position,
    _BaseConversionOutput output,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      color: context.appColors.panelElevated,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'value', child: Text('Copy value')),
        PopupMenuItem(value: 'prefix', child: Text('Copy with prefix')),
        PopupMenuItem(value: 'grouped', child: Text('Copy grouped')),
      ],
    );
    switch (selected) {
      case 'value':
        await Clipboard.setData(ClipboardData(text: output.value));
        break;
      case 'prefix':
        await Clipboard.setData(
          ClipboardData(text: '${output.prefix}${output.value}'),
        );
        break;
      case 'grouped':
        await Clipboard.setData(ClipboardData(text: output.groupedValue));
        break;
    }
  }
}

class _NumberInspector extends StatelessWidget {
  const _NumberInspector({
    required this.value,
    required this.widthBits,
    required this.interpretation,
  });

  final BigInt value;
  final int? widthBits;
  final String interpretation;

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = widthBits ?? _minimumByteAlignedBits(value);
    final unsigned = _unsignedWithinWidth(value, effectiveWidth);
    final signed = _signedWithinWidth(unsigned, effectiveWidth);
    final hex = unsigned.toRadixString(16).padLeft(effectiveWidth ~/ 4, '0');
    final bytes = _hexToBytePairs(hex);
    final ascii = _asciiPreview(unsigned, effectiveWidth);

    return ListView(
      children: [
        _inspectorRow(context, 'Mode', interpretation),
        _inspectorRow(context, 'Width', '$effectiveWidth bits'),
        _inspectorRow(context, 'Bit length', _bitLength(value).toString()),
        _inspectorRow(context, 'Byte length', _byteLength(value).toString()),
        _inspectorRow(context, 'Unsigned', unsigned.toString()),
        _inspectorRow(context, 'Signed', signed.toString()),
        _inspectorRow(context, 'Two\'s complement', '0x$hex'),
        _inspectorRow(context, 'Big endian bytes', bytes.join(' ')),
        _inspectorRow(context, 'Little endian bytes', bytes.reversed.join(' ')),
        _inspectorRow(
          context,
          'ASCII',
          ascii.isEmpty ? 'Not printable' : ascii,
        ),
      ],
    );
  }

  Widget _inspectorRow(BuildContext context, String label, String value) {
    final appColors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: appColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: value.length > 18 ? 'Menlo' : null,
                fontSize: value.length > 18 ? 11.5 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

_ParsedNumber _parseBigIntInput(
  String raw, {
  required String selectedBase,
  required int customBase,
}) {
  var text = raw.trim();
  if (text.isEmpty) throw const FormatException('Enter a number.');
  var negative = false;
  if (text.startsWith('-')) {
    negative = true;
    text = text.substring(1).trimLeft();
  } else if (text.startsWith('+')) {
    text = text.substring(1).trimLeft();
  }

  var base = switch (selectedBase) {
    'Binary' => 2,
    'Octal' => 8,
    'Decimal' => 10,
    'Hex' => 16,
    'Custom' => customBase,
    _ => 0,
  };

  final lower = text.toLowerCase();
  if (lower.startsWith('0b')) {
    base = base == 0 ? 2 : base;
    text = text.substring(2);
  } else if (lower.startsWith('0o')) {
    base = base == 0 ? 8 : base;
    text = text.substring(2);
  } else if (lower.startsWith('0x')) {
    base = base == 0 ? 16 : base;
    text = text.substring(2);
  } else if (base == 0) {
    base = RegExp(r'[a-z]', caseSensitive: false).hasMatch(text) ? 16 : 10;
  }

  if (base < 2 || base > 36) {
    throw const FormatException('Base must be between 2 and 36.');
  }

  final normalized = text.replaceAll(RegExp(r'[\s_]+'), '');
  if (normalized.isEmpty) throw const FormatException('Enter a number.');
  final validChars = '0123456789abcdefghijklmnopqrstuvwxyz'.substring(0, base);
  for (final codeUnit in normalized.toLowerCase().codeUnits) {
    if (!validChars.contains(String.fromCharCode(codeUnit))) {
      throw FormatException('Invalid digit for base $base.');
    }
  }

  var value = BigInt.parse(normalized, radix: base);
  if (negative) value = -value;
  return _ParsedNumber(value: value, detectedBase: base);
}

List<_BaseConversionOutput> _buildBaseOutputs(BigInt value, int customBase) {
  final rows = <_BaseConversionOutput>[
    _baseOutput('Binary', 2, '0b', value),
    _baseOutput('Octal', 8, '0o', value),
    _baseOutput('Decimal', 10, '', value),
    _baseOutput('Hex', 16, '0x', value),
    _baseOutput('Base 32', 32, '', value),
    _baseOutput('Base 36', 36, '', value),
  ];
  if (!const {2, 8, 10, 16, 32, 36}.contains(customBase)) {
    rows.add(_baseOutput('Custom', customBase, '', value));
  }
  return rows;
}

_BaseConversionOutput _baseOutput(
  String label,
  int base,
  String prefix,
  BigInt value,
) {
  final raw = value.toRadixString(base).toUpperCase();
  return _BaseConversionOutput(
    label: label,
    base: base,
    prefix: value.isNegative && prefix.isNotEmpty ? '-$prefix' : prefix,
    value: value.isNegative && prefix.isNotEmpty ? raw.substring(1) : raw,
    groupedValue: _groupBaseValue(raw, base),
  );
}

String _groupBaseValue(String value, int base) {
  final negative = value.startsWith('-');
  final body = negative ? value.substring(1) : value;
  final size = switch (base) {
    2 => 4,
    8 => 3,
    10 => 3,
    16 => 2,
    _ => 4,
  };
  final groups = <String>[];
  for (var index = body.length; index > 0; index -= size) {
    final start = max(0, index - size);
    groups.insert(0, body.substring(start, index));
  }
  final grouped = groups.join(' ');
  return negative ? '-$grouped' : grouped;
}

int _bitLength(BigInt value) {
  if (value == BigInt.zero) return 0;
  return value.abs().bitLength;
}

int _byteLength(BigInt value) {
  final bits = _bitLength(value);
  return bits == 0 ? 0 : ((bits + 7) ~/ 8);
}

int _digitCount(BigInt value) {
  final text = value.abs().toString();
  return text == '0' ? 1 : text.length;
}

int _minimumByteAlignedBits(BigInt value) {
  final bits = max(1, _bitLength(value));
  return ((bits + 7) ~/ 8) * 8;
}

BigInt _unsignedWithinWidth(BigInt value, int widthBits) {
  final modulus = BigInt.one << widthBits;
  final remainder = value % modulus;
  return remainder.isNegative ? remainder + modulus : remainder;
}

BigInt _signedWithinWidth(BigInt unsigned, int widthBits) {
  final signBit = BigInt.one << (widthBits - 1);
  final modulus = BigInt.one << widthBits;
  return unsigned >= signBit ? unsigned - modulus : unsigned;
}

List<String> _hexToBytePairs(String hex) {
  final padded = hex.length.isOdd ? '0$hex' : hex;
  final bytes = <String>[];
  for (var index = 0; index < padded.length; index += 2) {
    bytes.add(padded.substring(index, index + 2).toUpperCase());
  }
  return bytes;
}

String _asciiPreview(BigInt value, int widthBits) {
  final unsigned = _unsignedWithinWidth(value, widthBits);
  final hex = unsigned.toRadixString(16).padLeft(widthBits ~/ 4, '0');
  final buffer = StringBuffer();
  for (final pair in _hexToBytePairs(hex)) {
    final byte = int.parse(pair, radix: 16);
    if (byte < 32 || byte > 126) return '';
    buffer.writeCharCode(byte);
  }
  return buffer.toString();
}

class _LoremIpsumView extends StatefulWidget {
  const _LoremIpsumView();

  @override
  State<_LoremIpsumView> createState() => _LoremIpsumViewState();
}

class _LoremIpsumViewState extends State<_LoremIpsumView> {
  final TextEditingController _output = TextEditingController();
  String _count = 'x1';
  String _mode = 'Replace';

  @override
  void dispose() {
    _output.dispose();
    super.dispose();
  }

  void _addText(String text) {
    final count = int.tryParse(_count.replaceAll('x', '')) ?? 1;
    final repeated = List<String>.filled(count, text).join('\n\n');
    if (_mode == 'Append' && _output.text.isNotEmpty) {
      _output.text = '${_output.text}\n$repeated';
    } else {
      _output.text = repeated;
    }
    setState(() {});
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return _ResizableSplit(
      horizontal: true,
      initialRatio: 0.34,
      minFirstExtent: 300,
      minSecondExtent: 420,
      first: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LoremControlRow(
                label: 'Count',
                child: SmallDropdown(
                  items: const ['x1', 'x5', 'x10'],
                  initialValue: _count,
                  width: 104,
                  onChanged: (value) => setState(() => _count = value),
                ),
              ),
              const SizedBox(height: 8),
              _LoremControlRow(
                label: 'Mode',
                child: SmallDropdown(
                  items: const ['Replace', 'Append'],
                  initialValue: _mode,
                  width: 124,
                  onChanged: (value) => setState(() => _mode = value),
                ),
              ),
              const SizedBox(height: 18),
              _LoremSection(
                title: 'Text',
                children: [
                  _LoremActionButton(
                    label: 'Paragraph',
                    onPressed: () => _addText(_paragraph()),
                  ),
                  _LoremActionButton(
                    label: 'Sentence',
                    onPressed: () => _addText('Lorem ipsum dolor sit amet.'),
                  ),
                  _LoremActionButton(
                    label: 'Word',
                    onPressed: () => _addText('Lorem'),
                  ),
                  _LoremActionButton(
                    label: 'Title',
                    onPressed: () => _addText('Lorem Ipsum Title'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _LoremSection(
                title: 'Identity',
                children: [
                  _LoremActionButton(
                    label: 'First name',
                    onPressed: () => _addText('Alex'),
                  ),
                  _LoremActionButton(
                    label: 'Last name',
                    onPressed: () => _addText('Johnson'),
                  ),
                  _LoremActionButton(
                    label: 'Full name',
                    onPressed: () => _addText('Alex Johnson'),
                  ),
                  _LoremActionButton(
                    label: 'Email',
                    onPressed: () => _addText('hello@example.com'),
                  ),
                  _LoremActionButton(
                    label: 'URL',
                    onPressed: () => _addText('https://example.com'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _LoremSection(
                title: 'Social',
                children: [
                  _LoremActionButton(
                    label: 'Short tweet',
                    onPressed: () => _addText('Building tools offline.'),
                  ),
                  _LoremActionButton(
                    label: 'Long tweet',
                    onPressed: () => _addText(
                      'DevUtils helps you with daily tasks, offline and fast.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Output',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              ToolButton(
                label: 'Reset output',
                onPressed: () => setState(() => _output.clear()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EditorPane(
              label: '',
              actions: const [],
              controller: _output,
              placeholder: 'Generated text...',
              copyAction: _copyOutput,
              showHeader: false,
            ),
          ),
        ],
      ),
    );
  }

  String _paragraph() {
    return 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.';
  }
}

class _LoremControlRow extends StatelessWidget {
  const _LoremControlRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: context.appColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _LoremSection extends StatelessWidget {
  const _LoremSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.appColors.editorText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }
}

class _LoremActionButton extends StatelessWidget {
  const _LoremActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return SizedBox(
      width: 132,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          minimumSize: const Size(0, 34),
          side: BorderSide(color: appColors.border),
          backgroundColor: appColors.panelElevated,
          foregroundColor: appColors.editorText,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 12.5),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _QrCodeView extends StatefulWidget {
  const _QrCodeView();

  @override
  State<_QrCodeView> createState() => _QrCodeViewState();
}

class _QrCodeViewState extends State<_QrCodeView> {
  final TextEditingController _content = TextEditingController();
  String _template = 'Plain text';
  String _errorCorrection = 'High (30%)';
  bool _roundedModules = false;
  bool _circleEyes = false;
  String? _logoPath;
  ui.Image? _logoImage;

  static const _ecLevels = <String, int>{
    'Low (7%)': QrErrorCorrectLevel.L,
    'Medium (15%)': QrErrorCorrectLevel.M,
    'Quartile (25%)': QrErrorCorrectLevel.Q,
    'High (30%)': QrErrorCorrectLevel.H,
  };

  int get _ecLevel => _ecLevels[_errorCorrection] ?? QrErrorCorrectLevel.H;

  QrEyeStyle get _eyeStyle => QrEyeStyle(
    eyeShape: _circleEyes ? QrEyeShape.circle : QrEyeShape.square,
    color: Colors.black,
  );

  QrDataModuleStyle get _dataModuleStyle => QrDataModuleStyle(
    dataModuleShape:
        _roundedModules ? QrDataModuleShape.circle : QrDataModuleShape.square,
    color: Colors.black,
  );

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  void _updatePreview() {
    setState(() {});
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  Future<void> _pickLogo() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    );
    if (path == null || !mounted) return;
    try {
      final bytes = await File(path).readAsBytes();
      final image = await _decodeUiImage(bytes);
      if (!mounted) return;
      setState(() {
        _logoPath = path;
        _logoImage = image;
        // A center logo covers data modules, so force the highest error
        // correction to keep the code scannable.
        _errorCorrection = 'High (30%)';
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load logo: $error')),
      );
    }
  }

  void _removeLogo() {
    setState(() {
      _logoPath = null;
      _logoImage = null;
    });
  }

  Future<void> _savePng() async {
    final data = _content.text;
    if (data.isEmpty) return;
    try {
      const exportSize = 1024.0;
      const margin = exportSize * 0.08; // quiet zone
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: _ecLevel,
        gapless: true,
        eyeStyle: _eyeStyle,
        dataModuleStyle: _dataModuleStyle,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        const Rect.fromLTWH(0, 0, exportSize, exportSize),
      );
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, exportSize, exportSize),
        Paint()..color = Colors.white,
      );
      canvas.save();
      canvas.translate(margin, margin);
      painter.paint(canvas, const Size(exportSize - 2 * margin, exportSize - 2 * margin));
      canvas.restore();

      final logo = _logoImage;
      if (logo != null) {
        const center = Offset(exportSize / 2, exportSize / 2);
        final plate = exportSize * 0.22;
        final plateRect = Rect.fromCenter(
          center: center,
          width: plate,
          height: plate,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(plateRect, const Radius.circular(24)),
          Paint()..color = Colors.white,
        );
        final inner = plate * 0.82;
        final scale = min(inner / logo.width, inner / logo.height);
        final drawn = Rect.fromCenter(
          center: center,
          width: logo.width * scale,
          height: logo.height * scale,
        );
        canvas.drawImageRect(
          logo,
          Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
          drawn,
          Paint()..filterQuality = FilterQuality.high,
        );
      }

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(
        exportSize.toInt(),
        exportSize.toInt(),
      );
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null || !mounted) return;
      final path = await FileDialogService.saveFile(
        suggestedName: 'qr-code.png',
        allowedExtensions: const ['png'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes.buffer.asUint8List());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save QR code: $error')),
      );
    }
  }

  void _applyTemplate(String value) {
    final content = switch (value) {
      'vCard' =>
        'BEGIN:VCARD\nVERSION:3.0\nFN:Alex Johnson\nORG:DevUtils\nEMAIL:alex@example.com\nTEL:+15551234567\nEND:VCARD',
      'Wi-Fi' => 'WIFI:T:WPA;S:Example-Network;P:correct-horse-battery;;',
      'URL' => 'https://example.com',
      'Email' => 'mailto:alex@example.com?subject=Hello&body=Message',
      'SMS' => 'SMSTO:+15551234567:Hello from DevUtils',
      _ => 'Hello from DevUtils',
    };
    setState(() {
      _template = value;
      _content.text = content;
    });
    _updatePreview();
  }

  @override
  Widget build(BuildContext context) {
    return _ResizableSplit(
      horizontal: false,
      first: EditorPane(
        label: 'Content',
        actions: [
          ToolButton(
            label: 'Clipboard',
            onPressed: () async {
              final text = await _readClipboardText();
              setState(() => _content.text = text);
              _updatePreview();
            },
          ),
          ToolButton(
            label: 'Sample',
            onPressed: () {
              setState(
                () => _content.text = 'BEGIN:VCARD\nFN:DevUtils\nEND:VCARD',
              );
              _updatePreview();
            },
          ),
          ToolButton(
            label: 'Clear',
            onPressed: () {
              setState(() => _content.clear());
              _updatePreview();
            },
          ),
          SmallDropdown(
            items: const [
              'Plain text',
              'URL',
              'vCard',
              'Wi-Fi',
              'Email',
              'SMS',
            ],
            initialValue: _template,
            onChanged: _applyTemplate,
          ),
        ],
        controller: _content,
        onChanged: (_) => _updatePreview(),
        placeholder: 'BEGIN:VCARD...',
      ),
      second: Column(
        children: [
          Expanded(
            child: Container(
              decoration: _toolSurfaceDecoration(context),
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _content.text.isEmpty
                    ? Text(
                        'Enter content to generate a QR code',
                        style: _mutedToolTextStyle(context),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 320,
                          maxHeight: 320,
                        ),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(color: Colors.white),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  QrImageView(
                                    data: _content.text,
                                    version: QrVersions.auto,
                                    errorCorrectionLevel: _ecLevel,
                                    backgroundColor: Colors.white,
                                    eyeStyle: _eyeStyle,
                                    dataModuleStyle: _dataModuleStyle,
                                    errorStateBuilder: (context, error) =>
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(
                                            'Content too long for a QR code at this error-correction level.',
                                            textAlign: TextAlign.center,
                                            style: _errorToolTextStyle(context),
                                          ),
                                        ),
                                  ),
                                  if (_logoPath != null)
                                    FractionallySizedBox(
                                      widthFactor: 0.24,
                                      heightFactor: 0.24,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Image.file(
                                          File(_logoPath!),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SmallDropdown(
                items: const ['Square modules', 'Rounded modules'],
                initialValue:
                    _roundedModules ? 'Rounded modules' : 'Square modules',
                onChanged: (value) =>
                    setState(() => _roundedModules = value == 'Rounded modules'),
              ),
              SmallDropdown(
                items: const ['Square eyes', 'Circle eyes'],
                initialValue: _circleEyes ? 'Circle eyes' : 'Square eyes',
                onChanged: (value) =>
                    setState(() => _circleEyes = value == 'Circle eyes'),
              ),
              if (_logoPath == null)
                ToolButton(label: 'Add Logo', onPressed: _pickLogo)
              else ...[
                ToolButton(label: 'Change Logo', onPressed: _pickLogo),
                ToolButton(label: 'Remove Logo', onPressed: _removeLogo),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SmallDropdown(
                items: _ecLevels.keys.toList(),
                initialValue: _errorCorrection,
                onChanged: (value) =>
                    setState(() => _errorCorrection = value),
              ),
              ToolButton(label: 'Save PNG', onPressed: _savePng),
            ],
          ),
        ],
      ),
    );
  }
}

class _StringInspectorView extends StatefulWidget {
  const _StringInspectorView();

  @override
  State<_StringInspectorView> createState() => _StringInspectorViewState();
}

class _StringInspectorViewState extends State<_StringInspectorView> {
  final TextEditingController _input = TextEditingController();
  bool _caseSensitive = true;

  @override
  void initState() {
    super.initState();
    _input.addListener(_handleInputChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_handleInputChanged);
    _input.dispose();
    super.dispose();
  }

  void _handleInputChanged() {
    if (mounted) setState(() {});
  }

  Map<String, int> _wordCounts(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => _caseSensitive ? word : word.toLowerCase());
    final counts = <String, int>{};
    for (final word in words) {
      counts[word] = (counts[word] ?? 0) + 1;
    }
    return counts;
  }

  List<int> _lineColumnForOffset(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length).toInt();
    var line = 1;
    var column = 1;
    for (var i = 0; i < safeOffset; i++) {
      if (text.codeUnitAt(i) == 10) {
        line++;
        column = 1;
      } else {
        column++;
      }
    }
    return [line, column];
  }

  void _setSample() {
    _input.text = 'This is a special emoji 😀.\nAwesome, right?';
  }

  void _clear() {
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final text = _input.text;
    final chars = text.characters.length;
    final bytes = utf8.encode(text).length;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final lines = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    final counts = _wordCounts(text);
    final sortedCounts = counts.entries.toList()
      ..sort((a, b) {
        final countOrder = b.value.compareTo(a.value);
        if (countOrder != 0) return countOrder;
        return a.key.compareTo(b.key);
      });
    final maxCount = sortedCounts.isEmpty ? 1 : sortedCounts.first.value;
    final selection = _input.selection;
    final cursorOffset = selection.isValid
        ? selection.extentOffset.clamp(0, text.length).toInt()
        : 0;
    final cursorPosition = _lineColumnForOffset(text, cursorOffset);
    final selectedChars = selection.isValid && !selection.isCollapsed
        ? selection.textInside(text).characters.length
        : 0;

    return _ResizableSplit(
      horizontal: false,
      initialRatio: 0.30,
      minFirstExtent: 140,
      minSecondExtent: 300,
      first: EditorPane(
        label: 'Input',
        actions: [
          ToolButton(label: 'Sample', onPressed: _setSample),
          ToolButton(label: 'Clear', onPressed: _clear),
        ],
        controller: _input,
        placeholder: 'Type or paste text to inspect...',
        showHeader: false,
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 920 ? 7 : 4;
              const gap = 8.0;
              final width =
                  (constraints.maxWidth - ((columns - 1) * gap)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _InspectorMetricTile(
                    label: 'Characters',
                    value: '$chars',
                    width: width,
                  ),
                  _InspectorMetricTile(
                    label: 'Bytes',
                    value: '$bytes',
                    width: width,
                  ),
                  _InspectorMetricTile(
                    label: 'Words',
                    value: '$words',
                    width: width,
                  ),
                  _InspectorMetricTile(
                    label: 'Lines',
                    value: '$lines',
                    width: width,
                  ),
                  _InspectorMetricTile(
                    label: 'Unique',
                    value: '${counts.length}',
                    width: width,
                  ),
                  _InspectorMetricTile(
                    label: 'Cursor',
                    value: '${cursorPosition[0]}:${cursorPosition[1]}',
                    width: width,
                  ),
                  _InspectorMetricTile(
                    label: 'Selected',
                    value: '$selectedChars',
                    width: width,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: _toolSurfaceDecoration(context),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Word distribution',
                        style: TextStyle(
                          color: context.appColors.editorText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Checkbox(
                        value: _caseSensitive,
                        onChanged: (value) =>
                            setState(() => _caseSensitive = value ?? true),
                      ),
                      Text(
                        'Case sensitive',
                        style: TextStyle(color: context.appColors.editorText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: sortedCounts.isEmpty
                        ? Center(
                            child: Text(
                              'No words yet',
                              style: _mutedToolTextStyle(context),
                            ),
                          )
                        : ListView.separated(
                            itemCount: sortedCounts.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final entry = sortedCounts[index];
                              return _WordDistributionRow(
                                word: entry.key,
                                count: entry.value,
                                fraction: entry.value / maxCount,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorMetricTile extends StatelessWidget {
  const _InspectorMetricTile({
    required this.label,
    required this.value,
    required this.width,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return SizedBox(
      width: max(96, width),
      child: Container(
        decoration: _toolSurfaceDecoration(context, radius: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appColors.mutedText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appColors.editorText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordDistributionRow extends StatelessWidget {
  const _WordDistributionRow({
    required this.word,
    required this.count,
    required this.fraction,
  });

  final String word;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                word,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: appColors.editorText,
                  fontFamily: 'Menlo',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$count',
              style: TextStyle(
                color: appColors.mutedText,
                fontFamily: 'Menlo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1).toDouble(),
            minHeight: 3,
            color: appColors.accent,
            backgroundColor: appColors.border.withAlpha(90),
          ),
        ),
      ],
    );
  }
}

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
    final text = await _readClipboardText();
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
      setState(() => _error = _friendlyFileReadError(error));
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
    final split = _ResizableSplit(
      horizontal: false,
      initialRatio: 0.42,
      minFirstExtent: 110,
      minSecondExtent: 120,
      first: _FileDropTargetRegion(
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
          overlay: _SourceFileControls(
            onPickFile: _pickFile,
            fileName: _sourceFileName,
            tooltip: 'Choose Markdown file',
          ),
        ),
      ),
      second: _RenderedPreviewPane(
        label: 'Preview',
        html: markdownToHtmlForPreview(_input.text),
        badge: 'Rendered Markdown',
      ),
    );
    if (_error == null) return split;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_error!, style: _errorToolTextStyle(context)),
        const SizedBox(height: 8),
        Expanded(child: split),
      ],
    );
  }
}

class _RenderedPreviewPane extends StatelessWidget {
  const _RenderedPreviewPane({
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
                _PreviewBadge(label: badge),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _HtmlRenderedPreview(
            html: html,
            overlay: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.label});

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

class _SqlFormatterView extends StatefulWidget {
  const _SqlFormatterView();

  @override
  State<_SqlFormatterView> createState() => _SqlFormatterViewState();
}

class _SqlFormatterViewState extends State<_SqlFormatterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _mode = 'Format';
  String _case = 'Uppercase';
  String _indent = '2 spaces';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    if (_mode == 'SQL to English') {
      final explanation = _SqlExplainer().explain(_input.text);
      _output.text = _formatSqlExplanation(explanation);
      setState(() {});
      return;
    }
    _output.text = _formatSql(_input.text, _case, _indentFor(_indent));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(
          label: 'Clipboard',
          onPressed: () async {
            final text = await _readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = 'select * from users where id = 1');
            _run();
          },
        ),
        ToolButton(
          label: 'Clear',
          onPressed: () {
            setState(() => _input.clear());
            _output.clear();
          },
        ),
        const SmallDropdown(
          items: ['General SQL'],
          initialValue: 'General SQL',
        ),
      ],
      outputActions: [
        SmallDropdown(
          items: const ['Format', 'SQL to English'],
          initialValue: _mode,
          onChanged: (value) {
            setState(() => _mode = value);
            _run();
          },
        ),
        if (_mode == 'Format')
          SmallDropdown(
            items: const ['Uppercase', 'Lowercase'],
            initialValue: _case,
            onChanged: (value) {
              setState(() => _case = value);
              _run();
            },
          ),
        if (_mode == 'Format')
          SmallDropdown(
            items: const ['2 spaces', '4 spaces', 'Tabs'],
            initialValue: _indent,
            onChanged: (value) {
              setState(() => _indent = value);
              _run();
            },
          ),
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
    );
  }
}

String _formatSql(String source, String keywordCase, String indentString) {
  final compact = _compactSqlWhitespace(source);
  if (compact.isEmpty) return '';

  final cased = _caseSqlKeywords(compact, keywordCase);
  final clausePattern = RegExp(
    r'\s+((?:left|right|inner|outer|full|cross)\s+join|join|from|where|having|group\s+by|order\s+by|limit|offset|union(?:\s+all)?|values|set)\b',
    caseSensitive: false,
  );
  var text = cased.replaceAllMapped(clausePattern, (match) {
    return '\n${_caseSqlKeyword(match.group(1)!, keywordCase)}';
  });
  text = _breakSqlCommas(text, indentString);

  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';

  final formatted = <String>[];
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (lower.startsWith(',') ||
        lower.startsWith('and ') ||
        lower.startsWith('or ')) {
      formatted.add('$indentString$line');
    } else {
      formatted.add(line);
    }
  }
  return formatted.join('\n');
}

String _compactSqlWhitespace(String source) {
  final buffer = StringBuffer();
  String? quote;
  var previousWasSpace = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      buffer.write(char);
      if (char == quote && (i == 0 || source[i - 1] != '\\')) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
      previousWasSpace = false;
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
  return buffer.toString().trim();
}

String _caseSqlKeywords(String source, String keywordCase) {
  const keywords = [
    'select',
    'distinct',
    'from',
    'where',
    'and',
    'or',
    'join',
    'left',
    'right',
    'inner',
    'outer',
    'full',
    'cross',
    'on',
    'group',
    'order',
    'by',
    'having',
    'limit',
    'offset',
    'union',
    'all',
    'insert',
    'into',
    'update',
    'delete',
    'values',
    'set',
    'as',
    'case',
    'when',
    'then',
    'else',
    'end',
    'is',
    'not',
    'null',
    'like',
    'in',
    'exists',
  ];
  var output = source;
  for (final keyword in keywords) {
    output = output.replaceAllMapped(
      RegExp('\\b${RegExp.escape(keyword)}\\b', caseSensitive: false),
      (match) => _caseSqlKeyword(match.group(0)!, keywordCase),
    );
  }
  return output;
}

String _caseSqlKeyword(String keyword, String keywordCase) {
  return keywordCase == 'Uppercase'
      ? keyword.toUpperCase()
      : keyword.toLowerCase();
}

String _breakSqlCommas(String source, String indentString) {
  final buffer = StringBuffer();
  String? quote;
  var depth = 0;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      buffer.write(char);
      if (char == quote && (i == 0 || source[i - 1] != '\\')) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
      continue;
    }
    if (char == '(') depth += 1;
    if (char == ')') depth = max(0, depth - 1);
    if (char == ',' && depth == 0) {
      buffer.write('\n$indentString, ');
      while (i + 1 < source.length && RegExp(r'\s').hasMatch(source[i + 1])) {
        i++;
      }
      continue;
    }
    buffer.write(char);
  }
  return buffer.toString();
}

String _formatSqlExplanation(_SqlExplanation explanation) {
  final buffer = StringBuffer();
  buffer.writeln('SUMMARY:');
  buffer.writeln(explanation.summary);
  buffer.writeln();
  buffer.writeln('BREAKDOWN:');
  for (final component in explanation.breakdown) {
    buffer.writeln('  [${component.clause}] ${component.explanation}');
  }
  if (explanation.tables.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Tables: ${explanation.tables.join(", ")}');
  }
  if (explanation.columns.isNotEmpty) {
    buffer.writeln('Columns: ${explanation.columns.join(", ")}');
  }
  if (explanation.conditions.isNotEmpty) {
    buffer.writeln('Conditions: ${explanation.conditions.join("; ")}');
  }
  return buffer.toString().trimRight();
}

class _SqlExplanation {
  _SqlExplanation({
    required this.summary,
    required this.breakdown,
    required this.tables,
    required this.columns,
    required this.conditions,
    required this.queryType,
  });

  final String summary;
  final List<_SqlComponent> breakdown;
  final List<String> tables;
  final List<String> columns;
  final List<String> conditions;
  final _SqlQueryType queryType;
}

class _SqlComponent {
  _SqlComponent({required this.clause, required this.explanation});

  final String clause;
  final String explanation;
}

enum _SqlQueryType {
  select,
  insert,
  update,
  delete,
  create,
  alter,
  drop,
  unknown,
}

class _SqlExplainer {
  _SqlExplanation explain(String sql) {
    final normalized = _normalizeSql(sql);
    final type = _detectQueryType(normalized);
    switch (type) {
      case _SqlQueryType.select:
        return _explainSelect(normalized);
      case _SqlQueryType.insert:
        return _explainInsert(normalized);
      case _SqlQueryType.update:
        return _explainUpdate(normalized);
      case _SqlQueryType.delete:
        return _explainDelete(normalized);
      case _SqlQueryType.create:
        return _explainCreate(normalized);
      case _SqlQueryType.drop:
        return _explainDrop(normalized);
      case _SqlQueryType.alter:
        return _explainGeneric(normalized, type);
      case _SqlQueryType.unknown:
        return _explainGeneric(normalized, type);
    }
  }

  _SqlExplanation _explainSelect(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];
    final conditions = <String>[];
    final summaryParts = <String>[];

    final selectMatch = _firstMatch(
      sql,
      r'SELECT\s+(DISTINCT\s+)?(.+?)\s+FROM',
    );
    if (selectMatch != null) {
      final selectClause = selectMatch.group(0)!;
      final isDistinct = selectClause.toUpperCase().contains('DISTINCT');
      final colString = selectMatch.group(2)!.trim();
      if (colString == '*') {
        columns.add('all columns');
        components.add(
          _SqlComponent(
            clause: 'SELECT *',
            explanation: 'Retrieves all columns',
          ),
        );
      } else {
        columns.addAll(
          colString
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty),
        );
        final colDesc = columns.length > 3
            ? '${columns.length} columns'
            : columns.join(', ');
        components.add(
          _SqlComponent(clause: 'SELECT', explanation: 'Retrieves $colDesc'),
        );
      }
      if (isDistinct) {
        components.add(
          _SqlComponent(
            clause: 'DISTINCT',
            explanation: 'Removes duplicate rows from results',
          ),
        );
      }
    }

    final fromMatch = _firstMatch(
      sql,
      r'FROM\s+([\w\s,\.`"]+?)(?:\s+(?:WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|GROUP|ORDER|LIMIT|HAVING|UNION|$))',
    );
    if (fromMatch != null) {
      final tablesPart = fromMatch
          .group(1)!
          .replaceAll(
            RegExp(
              r'\s+(WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|GROUP|ORDER|LIMIT|HAVING|UNION).*',
            ),
            '',
          )
          .trim();
      final parsedTables = tablesPart
          .split(',')
          .map((item) => item.trim())
          .map((item) => item.split(' ').first)
          .where((item) => item.isNotEmpty)
          .toList();
      tables.addAll(parsedTables);
      if (parsedTables.isNotEmpty) {
        final tableDesc = parsedTables.length == 1
            ? "the '${parsedTables[0]}' table"
            : 'tables: ${parsedTables.join(', ')}';
        components.add(
          _SqlComponent(clause: 'FROM', explanation: 'From $tableDesc'),
        );
        summaryParts.add('from $tableDesc');
      }
    }

    const joinPattern =
        r'(LEFT\s+OUTER\s+|RIGHT\s+OUTER\s+|LEFT\s+|RIGHT\s+|INNER\s+|OUTER\s+|CROSS\s+)?JOIN\s+([\w\.`"]+)(?:\s+(?:AS\s+)?(\w+))?(?:\s+ON\s+(.+?))?(?=\s+(?:LEFT|RIGHT|INNER|OUTER|CROSS|JOIN|WHERE|GROUP|ORDER|LIMIT|HAVING|$))';
    for (final match in _allMatches(sql, joinPattern)) {
      final joinType = (match.group(1) ?? '').trim().toUpperCase();
      final joinTable = match.group(2) ?? '';
      final joinCondition = match.group(4) ?? '';
      if (joinTable.isEmpty) {
        continue;
      }
      tables.add(joinTable);
      final joinDesc = _describeJoin(joinType, joinTable, joinCondition);
      components.add(
        _SqlComponent(clause: '${joinType}JOIN', explanation: joinDesc),
      );
      summaryParts.add(joinDesc.toLowerCase());
    }

    final whereMatch = _firstMatch(
      sql,
      r'WHERE\s+(.+?)(?:\s+(?:GROUP|ORDER|LIMIT|HAVING|UNION|$))',
    );
    if (whereMatch != null) {
      final whereClause = whereMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(GROUP|ORDER|LIMIT|HAVING|UNION).*'), '')
          .trim();
      final explained = _explainConditions(whereClause);
      conditions.addAll(explained.map((item) => item.raw));
      components.add(
        _SqlComponent(
          clause: 'WHERE',
          explanation:
              'Filters results where: ${explained.map((item) => item.explanation).join('; ')}',
        ),
      );
      summaryParts.add(
        'filtered by ${conditions.length} condition${conditions.length == 1 ? '' : 's'}',
      );
    }

    final groupMatch = _firstMatch(
      sql,
      r'GROUP\s+BY\s+(.+?)(?:\s+(?:HAVING|ORDER|LIMIT|UNION|$))',
    );
    if (groupMatch != null) {
      final groupClause = groupMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(HAVING|ORDER|LIMIT|UNION).*'), '')
          .trim();
      final groupCols = groupClause
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (groupCols.isNotEmpty) {
        components.add(
          _SqlComponent(
            clause: 'GROUP BY',
            explanation: 'Groups results by ${groupCols.join(', ')}',
          ),
        );
        summaryParts.add('grouped by ${groupCols.join(', ')}');
      }
    }

    final havingMatch = _firstMatch(
      sql,
      r'HAVING\s+(.+?)(?:\s+(?:ORDER|LIMIT|UNION|$))',
    );
    if (havingMatch != null) {
      final havingClause = havingMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(ORDER|LIMIT|UNION).*'), '')
          .trim();
      if (havingClause.isNotEmpty) {
        components.add(
          _SqlComponent(
            clause: 'HAVING',
            explanation: 'Filters groups where: $havingClause',
          ),
        );
      }
    }

    final orderMatch = _firstMatch(
      sql,
      r'ORDER\s+BY\s+(.+?)(?:\s+(?:LIMIT|OFFSET|UNION|$))',
    );
    if (orderMatch != null) {
      final orderClause = orderMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(LIMIT|OFFSET|UNION).*'), '')
          .trim();
      if (orderClause.isNotEmpty) {
        final orderExplanation = _explainOrderBy(orderClause);
        components.add(
          _SqlComponent(clause: 'ORDER BY', explanation: orderExplanation),
        );
        summaryParts.add('sorted by $orderClause');
      }
    }

    final limitMatch = _firstMatch(sql, r'LIMIT\s+(\d+)(?:\s+OFFSET\s+(\d+))?');
    if (limitMatch != null) {
      final limitValue = int.tryParse(limitMatch.group(1) ?? '');
      final offsetValue = int.tryParse(limitMatch.group(2) ?? '');
      if (limitValue != null) {
        var limitExplanation =
            'Returns only the first $limitValue result${limitValue == 1 ? '' : 's'}';
        if (offsetValue != null) {
          limitExplanation += ', skipping the first $offsetValue';
        }
        components.add(
          _SqlComponent(clause: 'LIMIT', explanation: limitExplanation),
        );
        summaryParts.add('limited to $limitValue rows');
      }
    }

    final columnSummary = columns.firstOrNull == 'all columns'
        ? 'all columns'
        : '${columns.length} column${columns.length == 1 ? '' : 's'}';
    var summary = 'Retrieves $columnSummary';
    if (summaryParts.isNotEmpty) {
      summary = '$summary ${summaryParts.join(', ')}';
    }

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: conditions,
      queryType: _SqlQueryType.select,
    );
  }

  _SqlExplanation _explainInsert(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'INSERT\s+INTO\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tablePart = tableMatch.group(1)!;
      tables.add(tablePart);
      components.add(
        _SqlComponent(
          clause: 'INSERT INTO',
          explanation: "Adds new row(s) to the '$tablePart' table",
        ),
      );
    }

    final colMatch = _firstMatch(
      sql,
      r'\(([^)]+)\)\s*VALUES',
      caseInsensitive: true,
    );
    if (colMatch != null) {
      final colPart = colMatch.group(1)!;
      columns.addAll(
        colPart
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
      components.add(
        _SqlComponent(
          clause: 'COLUMNS',
          explanation: 'Sets values for: ${columns.join(', ')}',
        ),
      );
    }

    final valuesCount = RegExp(r'\)\s*,\s*\(').allMatches(sql).length + 1;
    components.add(
      _SqlComponent(
        clause: 'VALUES',
        explanation: 'Inserting $valuesCount row${valuesCount == 1 ? '' : 's'}',
      ),
    );

    if (sql.toUpperCase().contains('SELECT')) {
      components.add(
        _SqlComponent(
          clause: 'SELECT',
          explanation: 'Values come from a subquery',
        ),
      );
    }

    final summary =
        "Inserts $valuesCount row${valuesCount == 1 ? '' : 's'} into '${tables.firstOrNull ?? 'table'}' with ${columns.length} column${columns.length == 1 ? '' : 's'}";

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: const [],
      queryType: _SqlQueryType.insert,
    );
  }

  _SqlExplanation _explainUpdate(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];
    final conditions = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'UPDATE\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tablePart = tableMatch.group(1)!;
      tables.add(tablePart);
      components.add(
        _SqlComponent(
          clause: 'UPDATE',
          explanation: "Modifies rows in the '$tablePart' table",
        ),
      );
    }

    final setMatch = _firstMatch(
      sql,
      r'SET\s+(.+?)(?:\s+WHERE|$)',
      caseInsensitive: true,
    );
    if (setMatch != null) {
      final setPart = setMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+WHERE.*', caseSensitive: false), '')
          .trim();
      final assignments = setPart
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      columns.addAll(
        assignments
            .map((assignment) => assignment.split('=').first.trim())
            .where((value) => value.isNotEmpty),
      );

      final setExplanations = <String>[];
      for (final assignment in assignments) {
        final parts = assignment.split('=').map((part) => part.trim()).toList();
        if (parts.length == 2) {
          setExplanations.add("'${parts[0]}' to ${parts[1]}");
        }
      }
      components.add(
        _SqlComponent(
          clause: 'SET',
          explanation: 'Changes: ${setExplanations.join(', ')}',
        ),
      );
    }

    final whereMatch = _firstMatch(
      sql,
      r'WHERE\s+(.+?)$',
      caseInsensitive: true,
    );
    if (whereMatch != null) {
      final whereClause = whereMatch.group(1)!.trim();
      final explained = _explainConditions(whereClause);
      conditions.addAll(explained.map((item) => item.raw));
      components.add(
        _SqlComponent(
          clause: 'WHERE',
          explanation:
              'Only affects rows where: ${explained.map((item) => item.explanation).join('; ')}',
        ),
      );
    } else {
      components.add(
        _SqlComponent(
          clause: 'WARNING',
          explanation: 'No WHERE clause - this will update ALL rows.',
        ),
      );
    }

    final summary =
        "Updates ${columns.length} column${columns.length == 1 ? '' : 's'} in '${tables.firstOrNull ?? 'table'}'"
        '${conditions.isEmpty ? ' (ALL ROWS)' : ' with ${conditions.length} filter condition${conditions.length == 1 ? '' : 's'}'}';

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: conditions,
      queryType: _SqlQueryType.update,
    );
  }

  _SqlExplanation _explainDelete(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final conditions = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'DELETE\s+FROM\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tablePart = tableMatch.group(1)!;
      tables.add(tablePart);
      components.add(
        _SqlComponent(
          clause: 'DELETE FROM',
          explanation: "Removes rows from the '$tablePart' table",
        ),
      );
    }

    final whereMatch = _firstMatch(
      sql,
      r'WHERE\s+(.+?)$',
      caseInsensitive: true,
    );
    if (whereMatch != null) {
      final whereClause = whereMatch.group(1)!.trim();
      final explained = _explainConditions(whereClause);
      conditions.addAll(explained.map((item) => item.raw));
      components.add(
        _SqlComponent(
          clause: 'WHERE',
          explanation:
              'Only deletes rows where: ${explained.map((item) => item.explanation).join('; ')}',
        ),
      );
    } else {
      components.add(
        _SqlComponent(
          clause: 'WARNING',
          explanation: 'No WHERE clause - this will delete ALL rows.',
        ),
      );
    }

    final summary =
        "Deletes rows from '${tables.firstOrNull ?? 'table'}'"
        '${conditions.isEmpty ? ' (ALL ROWS)' : ' where ${conditions.length} condition${conditions.length == 1 ? '' : 's'} match'}';

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: const [],
      conditions: conditions,
      queryType: _SqlQueryType.delete,
    );
  }

  _SqlExplanation _explainCreate(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tableName = tableMatch.group(2)!;
      tables.add(tableName);
      final ifNotExists = tableMatch.group(1) != null;
      var explanation = "Creates a new table called '$tableName'";
      if (ifNotExists) {
        explanation += ' (only if it does not already exist)';
      }
      components.add(
        _SqlComponent(clause: 'CREATE TABLE', explanation: explanation),
      );

      final colSection = _firstMatch(sql, r'\((.+)\)', caseInsensitive: true);
      if (colSection != null) {
        final colPart = colSection.group(1) ?? '';
        final colDefs = _splitColumnDefinitions(colPart);
        for (final def in colDefs) {
          final explained = _explainColumnDefinition(def);
          columns.add(explained.name);
          components.add(
            _SqlComponent(clause: 'COLUMN', explanation: explained.explanation),
          );
        }
      }
    }

    final indexMatch = _firstMatch(
      sql,
      r'CREATE\s+(UNIQUE\s+)?INDEX\s+([\w\.`"]+)\s+ON\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (indexMatch != null) {
      final isUnique = indexMatch.group(1) != null;
      components.add(
        _SqlComponent(
          clause: 'CREATE INDEX',
          explanation:
              'Creates a${isUnique ? ' unique' : 'n'} index for faster lookups',
        ),
      );
    }

    final summary =
        "Creates table '${tables.firstOrNull ?? ''}' with ${columns.length} column${columns.length == 1 ? '' : 's'}";
    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: const [],
      queryType: _SqlQueryType.create,
    );
  }

  _SqlExplanation _explainDrop(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];

    final dropMatch = _firstMatch(
      sql,
      r'DROP\s+(TABLE|INDEX|DATABASE)\s+(IF\s+EXISTS\s+)?([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (dropMatch != null) {
      final objectType = dropMatch.group(1)!.toUpperCase();
      final objectName = dropMatch.group(3)!;
      final ifExists = dropMatch.group(2) != null;
      tables.add(objectName);
      var explanation =
          'Permanently deletes the ${objectType.toLowerCase()} \'$objectName\'';
      if (ifExists) {
        explanation += ' (only if it exists)';
      }
      components.add(_SqlComponent(clause: 'DROP', explanation: explanation));
    }

    return _SqlExplanation(
      summary:
          "Drops (deletes) '${tables.firstOrNull ?? 'object'}' permanently",
      breakdown: components,
      tables: tables,
      columns: const [],
      conditions: const [],
      queryType: _SqlQueryType.drop,
    );
  }

  _SqlExplanation _explainGeneric(String sql, _SqlQueryType type) {
    return _SqlExplanation(
      summary: 'Executes a ${type.name.toUpperCase()} statement',
      breakdown: [
        _SqlComponent(
          clause: type.name.toUpperCase(),
          explanation: 'Unable to parse detailed structure',
        ),
      ],
      tables: const [],
      columns: const [],
      conditions: const [],
      queryType: type,
    );
  }

  String _normalizeSql(String sql) {
    var result = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    result = result.replaceAll(RegExp(r'--.*?(?=\n|$)'), '');
    result = result.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    return result;
  }

  _SqlQueryType _detectQueryType(String sql) {
    final upper = sql.trim().toUpperCase();
    if (upper.startsWith('SELECT')) return _SqlQueryType.select;
    if (upper.startsWith('INSERT')) return _SqlQueryType.insert;
    if (upper.startsWith('UPDATE')) return _SqlQueryType.update;
    if (upper.startsWith('DELETE')) return _SqlQueryType.delete;
    if (upper.startsWith('CREATE')) return _SqlQueryType.create;
    if (upper.startsWith('ALTER')) return _SqlQueryType.alter;
    if (upper.startsWith('DROP')) return _SqlQueryType.drop;
    return _SqlQueryType.unknown;
  }

  String _describeJoin(String type, String table, String condition) {
    String desc;
    switch (type.trim()) {
      case 'LEFT':
      case 'LEFT OUTER':
        desc =
            "Includes all rows from the left table, plus matching rows from '$table'";
        break;
      case 'RIGHT':
      case 'RIGHT OUTER':
        desc =
            "Includes all rows from '$table', plus matching rows from the left table";
        break;
      case 'OUTER':
      case 'FULL OUTER':
        desc = 'Includes all rows from both tables, matching where possible';
        break;
      case 'CROSS':
        desc =
            "Combines every row with every row from '$table' (cartesian product)";
        break;
      default:
        desc = "Combines with '$table' where matches exist";
    }
    if (condition.isNotEmpty) {
      desc += ' on $condition';
    }
    return desc;
  }

  List<_SqlCondition> _explainConditions(String whereClause) {
    final parts = whereClause
        .replaceAll(RegExp(r'\s+AND\s+', caseSensitive: false), '§AND§')
        .replaceAll(RegExp(r'\s+OR\s+', caseSensitive: false), '§OR§')
        .split('§')
        .where((item) => item.isNotEmpty)
        .toList();
    final explained = <_SqlCondition>[];
    for (final part in parts) {
      if (part == 'AND' || part == 'OR') {
        continue;
      }
      explained.add(
        _SqlCondition(
          raw: part.trim(),
          explanation: _explainSingleCondition(part),
        ),
      );
    }
    return explained;
  }

  String _explainSingleCondition(String condition) {
    final cond = condition.trim();
    final upper = cond.toUpperCase();
    if (upper.contains(' IS NULL')) {
      final col = cond.replaceAll(
        RegExp(r'\s+IS\s+NULL', caseSensitive: false),
        '',
      );
      return "'$col' has no value";
    }
    if (upper.contains(' IS NOT NULL')) {
      final col = cond.replaceAll(
        RegExp(r'\s+IS\s+NOT\s+NULL', caseSensitive: false),
        '',
      );
      return "'$col' has a value";
    }
    if (upper.contains(' IN ')) {
      final match = _firstMatch(
        cond,
        r'(.+?)\s+IN\s*\((.+?)\)',
        caseInsensitive: true,
      );
      if (match != null) {
        final parts = match
            .group(0)!
            .split(RegExp(r'\s+IN\s+', caseSensitive: false));
        if (parts.length == 2) {
          return "'${parts[0]}' is one of ${parts[1]}";
        }
      }
    }
    if (upper.contains(' LIKE ')) {
      final parts = cond
          .split(RegExp(r'\s+LIKE\s+', caseSensitive: false))
          .map((item) => item.trim())
          .toList();
      if (parts.length == 2) {
        final pattern = parts[1].replaceAll("'", '');
        if (pattern.startsWith('%') && pattern.endsWith('%')) {
          final text = pattern.replaceAll('%', '');
          return "'${parts[0]}' contains '$text'";
        }
        if (pattern.startsWith('%')) {
          final text = pattern.replaceAll('%', '');
          return "'${parts[0]}' ends with '$text'";
        }
        if (pattern.endsWith('%')) {
          final text = pattern.replaceAll('%', '');
          return "'${parts[0]}' starts with '$text'";
        }
        return "'${parts[0]}' matches pattern '$pattern'";
      }
    }
    if (upper.contains(' BETWEEN ')) {
      final match = _firstMatch(
        cond,
        r'(.+?)\s+BETWEEN\s+(.+?)\s+AND\s+(.+)',
        caseInsensitive: true,
      );
      if (match != null) {
        final col = match.group(1)!.trim();
        final low = match.group(2)!.trim();
        final high = match.group(3)!.trim();
        return "'$col' is between $low and $high";
      }
    }
    const operators = [
      ['>=', 'is greater than or equal to'],
      ['<=', 'is less than or equal to'],
      ['<>', 'is not equal to'],
      ['!=', 'is not equal to'],
      ['=', 'equals'],
      ['>', 'is greater than'],
      ['<', 'is less than'],
    ];
    for (final entry in operators) {
      final op = entry[0];
      final desc = entry[1];
      if (cond.contains(op)) {
        final parts = cond.split(op).map((item) => item.trim()).toList();
        if (parts.length == 2) {
          return "'${parts[0]}' $desc ${parts[1]}";
        }
      }
    }
    return cond;
  }

  String _explainOrderBy(String clause) {
    final parts = clause
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final explanations = <String>[];
    for (final part in parts) {
      final upper = part.toUpperCase();
      final col = part
          .replaceAll(RegExp(r'\s+(ASC|DESC)$', caseSensitive: false), '')
          .trim();
      if (upper.endsWith('DESC')) {
        explanations.add("'$col' descending (Z->A, 9->0)");
      } else {
        explanations.add("'$col' ascending (A->Z, 0->9)");
      }
    }
    return 'Sorts by ${explanations.join(', then by ')}';
  }

  List<String> _splitColumnDefinitions(String section) {
    final definitions = <String>[];
    var current = StringBuffer();
    var parenDepth = 0;
    for (final char in section.split('')) {
      if (char == '(') {
        parenDepth += 1;
      } else if (char == ')') {
        parenDepth = parenDepth > 0 ? parenDepth - 1 : 0;
      }
      if (char == ',' && parenDepth == 0) {
        final value = current.toString().trim();
        if (value.isNotEmpty) {
          definitions.add(value);
        }
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    final tail = current.toString().trim();
    if (tail.isNotEmpty) {
      definitions.add(tail);
    }
    return definitions;
  }

  _SqlColumnExplanation _explainColumnDefinition(String definition) {
    final parts = definition
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return _SqlColumnExplanation(name: '', explanation: definition);
    }
    final upperDef = definition.toUpperCase();
    if (upperDef.startsWith('PRIMARY KEY') ||
        upperDef.startsWith('FOREIGN KEY') ||
        upperDef.startsWith('UNIQUE') ||
        upperDef.startsWith('CHECK') ||
        upperDef.startsWith('CONSTRAINT')) {
      return _SqlColumnExplanation(
        name: 'constraint',
        explanation: _explainConstraint(definition),
      );
    }
    final name = parts[0];
    final type = parts.length > 1 ? parts[1] : 'unknown';
    final attributes = <String>[];
    if (upperDef.contains('PRIMARY KEY')) attributes.add('primary key');
    if (upperDef.contains('NOT NULL')) attributes.add('required');
    if (upperDef.contains('UNIQUE')) attributes.add('unique');
    if (upperDef.contains('AUTO_INCREMENT') ||
        upperDef.contains('AUTOINCREMENT')) {
      attributes.add('auto-generated');
    }
    if (upperDef.contains('DEFAULT')) attributes.add('has default value');
    if (upperDef.contains('REFERENCES')) attributes.add('foreign key');
    var explanation = "'$name' (${_describeDataType(type)}";
    if (attributes.isNotEmpty) {
      explanation += ', ${attributes.join(', ')}';
    }
    explanation += ')';
    return _SqlColumnExplanation(name: name, explanation: explanation);
  }

  String _describeDataType(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('INT')) return 'whole number';
    if (upper.contains('VARCHAR') || upper.contains('CHAR')) return 'text';
    if (upper.contains('TEXT')) return 'long text';
    if (upper.contains('DECIMAL') ||
        upper.contains('NUMERIC') ||
        upper.contains('FLOAT') ||
        upper.contains('DOUBLE')) {
      return 'decimal number';
    }
    if (upper.contains('BOOL')) return 'true/false';
    if (upper.contains('DATE') && upper.contains('TIME')) {
      return 'date and time';
    }
    if (upper.contains('DATE')) return 'date';
    if (upper.contains('TIME')) return 'time';
    if (upper.contains('BLOB') || upper.contains('BINARY')) {
      return 'binary data';
    }
    if (upper.contains('JSON')) return 'JSON data';
    if (upper.contains('UUID')) return 'unique identifier';
    return type.toLowerCase();
  }

  String _explainConstraint(String definition) {
    final upper = definition.toUpperCase();
    if (upper.contains('PRIMARY KEY')) {
      return 'Primary key constraint - uniquely identifies each row';
    }
    if (upper.contains('FOREIGN KEY')) {
      final refMatch = _firstMatch(
        definition,
        r'REFERENCES\s+([\w\.]+)',
        caseInsensitive: true,
      );
      if (refMatch != null) {
        final refTable = refMatch.group(1) ?? '';
        return "Foreign key - links to '$refTable'";
      }
      return 'Foreign key constraint - links to another table';
    }
    if (upper.contains('UNIQUE')) {
      return 'Unique constraint - no duplicate values allowed';
    }
    if (upper.contains('CHECK')) {
      return 'Check constraint - validates data before insert/update';
    }
    return definition;
  }

  RegExpMatch? _firstMatch(
    String input,
    String pattern, {
    bool caseInsensitive = true,
  }) {
    return RegExp(
      pattern,
      caseSensitive: !caseInsensitive,
      dotAll: true,
    ).firstMatch(input);
  }

  Iterable<RegExpMatch> _allMatches(String input, String pattern) {
    return RegExp(
      pattern,
      caseSensitive: false,
      dotAll: true,
    ).allMatches(input);
  }
}

class _SqlCondition {
  _SqlCondition({required this.raw, required this.explanation});

  final String raw;
  final String explanation;
}

class _SqlColumnExplanation {
  _SqlColumnExplanation({required this.name, required this.explanation});

  final String name;
  final String explanation;
}

extension _FirstOrNullExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _StringCaseConverterView extends StatefulWidget {
  const _StringCaseConverterView();

  @override
  State<_StringCaseConverterView> createState() =>
      _StringCaseConverterViewState();
}

class _StringCaseConverterViewState extends State<_StringCaseConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _mode = 'camelCase';
  static const _caseModes = [
    'camelCase',
    'PascalCase',
    'snake_case',
    'CONSTANT_CASE',
    'kebab-case',
    'Title Case',
    'Sentence case',
    'lowercase',
    'UPPERCASE',
  ];

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final lines = _input.text.split('\n');
    final converted = lines.map(_convert).join('\n');
    _output.text = converted;
    setState(() {});
  }

  String _convert(String input) {
    final words = _caseWords(input);
    if (words.isEmpty) return '';
    final lowerWords = words.map((word) => word.toLowerCase()).toList();
    switch (_mode) {
      case 'PascalCase':
        return lowerWords.map(_capitalizeWord).join();
      case 'snake_case':
        return lowerWords.join('_');
      case 'CONSTANT_CASE':
        return lowerWords.join('_').toUpperCase();
      case 'kebab-case':
        return lowerWords.join('-');
      case 'Title Case':
        return lowerWords.map(_capitalizeWord).join(' ');
      case 'Sentence case':
        return _capitalizeWord(lowerWords.join(' '));
      case 'lowercase':
        return lowerWords.join(' ');
      case 'UPPERCASE':
        return lowerWords.join(' ').toUpperCase();
      case 'camelCase':
      default:
        final first = lowerWords.first;
        final rest = lowerWords.skip(1).map(_capitalizeWord);
        return ([first, ...rest]).join();
    }
  }

  List<String> _caseWords(String input) {
    final spaced = input
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAll(RegExp(r'[_\-.\/]+'), ' ');
    return spaced
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
  }

  String _capitalizeWord(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(
          label: 'Clipboard',
          onPressed: () async {
            final text = await _readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = 'request URL decoder ID');
            _run();
          },
        ),
        ToolButton(
          label: 'Clear',
          onPressed: () {
            setState(() => _input.clear());
            _output.clear();
          },
        ),
      ],
      outputActions: [
        SmallDropdown(
          items: _caseModes,
          initialValue: _mode,
          onChanged: (value) {
            setState(() => _mode = value);
            _run();
          },
        ),
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
      onInputChanged: (_) => _run(),
    );
  }
}

class _CronJobParserView extends StatefulWidget {
  const _CronJobParserView();

  @override
  State<_CronJobParserView> createState() => _CronJobParserViewState();
}

class _CronJobParserViewState extends State<_CronJobParserView> {
  final TextEditingController _input = TextEditingController(
    text: '*/5 * * * *',
  );
  String _summary = 'Every 5 minutes';
  String _minutes = '';
  List<String> _next = [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  void _parse() {
    final parts = _input.text.trim().split(RegExp(r'\s+'));
    if (parts.length < 5) {
      setState(() {
        _summary = 'Invalid cron expression';
        _minutes = '';
        _next = [];
      });
      return;
    }
    final minute = parts[0];
    if (minute.startsWith('*/')) {
      final step = int.tryParse(minute.substring(2)) ?? 1;
      _summary = 'Every $step minutes';
      final mins = <String>[];
      for (var m = 0; m < 60; m += step) {
        mins.add(m.toString().padLeft(2, '0'));
      }
      _minutes = mins.join(', ');
      _next = _nextExecutions(step);
    } else if (minute == '*') {
      _summary = 'Every minute';
      _minutes = '(All)';
      _next = _nextExecutions(1);
    } else {
      _summary = 'At minute $minute';
      _minutes = minute;
      final step = int.tryParse(minute) ?? 0;
      _next = step >= 0 ? _nextExecutions(60) : [];
    }
    setState(() {});
  }

  List<String> _nextExecutions(int stepMinutes) {
    final now = DateTime.now();
    final list = <String>[];
    var current = now.add(
      Duration(minutes: stepMinutes - (now.minute % stepMinutes)),
    );
    for (var i = 0; i < 5; i++) {
      list.add(current.toString());
      current = current.add(Duration(minutes: stepMinutes));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ToolButton(
                  label: 'Clipboard',
                  onPressed: () async {
                    final text = await _readClipboardText();
                    setState(() => _input.text = text);
                    _parse();
                  },
                ),
                const SizedBox(width: 8),
                ToolButton(
                  label: 'Sample',
                  onPressed: () {
                    setState(() => _input.text = '*/5 * * * *');
                    _parse();
                  },
                ),
                const SizedBox(width: 8),
                ToolButton(
                  label: 'Clear',
                  onPressed: () {
                    setState(() => _input.clear());
                    _parse();
                  },
                ),
                const SizedBox(width: 8),
                ToolButton(
                  label: 'Copy',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _input.text)),
                ),
                const Spacer(),
                const SmallDropdown(
                  items: ['Pick an example...'],
                  initialValue: 'Pick an example...',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InlineTextField(
              hintText: '*/5 * * * *',
              controller: _input,
              onChanged: (_) => _parse(),
            ),
            const SizedBox(height: 12),
            Text(_summary),
            const SizedBox(height: 12),
            Text('Minutes: $_minutes'),
            const Text('Hours: (All)'),
            const Text('Day of Month: (All)'),
            const Text('Months: (All)'),
            const Text('Day of Week: (All)'),
            const SizedBox(height: 12),
            const Text('Next executions:'),
            for (final item in _next) Text(item),
          ],
        ),
      ),
    );
  }
}

class _ColorConverterView extends StatefulWidget {
  const _ColorConverterView();

  @override
  State<_ColorConverterView> createState() => _ColorConverterViewState();
}

class _ColorConverterViewState extends State<_ColorConverterView> {
  final TextEditingController _input = TextEditingController(text: '#5CC07F');
  final TextEditingController _hex = TextEditingController();
  final TextEditingController _hexAlpha = TextEditingController();
  final TextEditingController _rgb = TextEditingController();
  final TextEditingController _rgba = TextEditingController();
  final TextEditingController _hsl = TextEditingController();
  final TextEditingController _hsla = TextEditingController();
  final TextEditingController _hsv = TextEditingController();
  final TextEditingController _hwb = TextEditingController();
  final TextEditingController _cmyk = TextEditingController();
  Color _color = const Color(0xFF5CC07F);
  String? _error;

  @override
  void initState() {
    super.initState();
    _setColor(_color);
  }

  void _updateFromInput(String text) {
    final color = _parseColorValue(text);
    if (color == null) {
      setState(() => _error = text.trim().isEmpty ? null : 'Invalid color.');
      return;
    }
    _setColor(color, updateInput: false);
  }

  void _setColor(Color color, {bool updateInput = true}) {
    _color = color;
    _error = null;
    if (updateInput) {
      _input.text = _cssHex(color).toUpperCase();
    }
    _fillFields(color);
    setState(() {});
  }

  void _fillFields(Color color) {
    final r = _colorComponent(color.r);
    final g = _colorComponent(color.g);
    final b = _colorComponent(color.b);
    final alpha = _colorComponent(color.a);
    final a = alpha / 255;
    _hex.text = _cssHex(color);
    _hexAlpha.text = _cssHex(color, includeAlpha: true);
    _rgb.text = 'rgb($r, $g, $b)';
    _rgba.text = 'rgba($r, $g, $b, ${a.toStringAsFixed(2)})';
    final hsl = _rgbToHsl(r, g, b);
    _hsl.text = 'hsl(${hsl[0]}deg, ${hsl[1]}%, ${hsl[2]}%)';
    _hsla.text =
        'hsla(${hsl[0]}deg, ${hsl[1]}%, ${hsl[2]}%, ${a.toStringAsFixed(2)})';
    final hsv = _rgbToHsv(r, g, b);
    _hsv.text = 'hsb(${hsv[0]}deg, ${hsv[1]}%, ${hsv[2]}%)';
    _hwb.text = 'hwb(${hsv[0]}deg, ${hsv[1]}%, ${100 - hsv[1]}%)';
    final cmyk = _rgbToCmyk(r, g, b);
    _cmyk.text = 'cmyk(${cmyk[0]}%, ${cmyk[1]}%, ${cmyk[2]}%, ${cmyk[3]}%)';
  }

  List<int> _rgbToHsl(int r, int g, int b) {
    final rf = r / 255;
    final gf = g / 255;
    final bf = b / 255;
    final max = [rf, gf, bf].reduce(maxOf);
    final min = [rf, gf, bf].reduce(minOf);
    var h = 0.0;
    var s = 0.0;
    final l = (max + min) / 2;
    if (max != min) {
      final d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      if (max == rf) {
        h = (gf - bf) / d + (gf < bf ? 6 : 0);
      } else if (max == gf) {
        h = (bf - rf) / d + 2;
      } else {
        h = (rf - gf) / d + 4;
      }
      h /= 6;
    }
    return [(h * 360).round(), (s * 100).round(), (l * 100).round()];
  }

  List<int> _rgbToHsv(int r, int g, int b) {
    final rf = r / 255;
    final gf = g / 255;
    final bf = b / 255;
    final max = [rf, gf, bf].reduce(maxOf);
    final min = [rf, gf, bf].reduce(minOf);
    final d = max - min;
    var h = 0.0;
    final s = max == 0 ? 0 : d / max;
    if (max != min) {
      if (max == rf) {
        h = (gf - bf) / d + (gf < bf ? 6 : 0);
      } else if (max == gf) {
        h = (bf - rf) / d + 2;
      } else {
        h = (rf - gf) / d + 4;
      }
      h /= 6;
    }
    return [(h * 360).round(), (s * 100).round(), (max * 100).round()];
  }

  List<int> _rgbToCmyk(int r, int g, int b) {
    final rf = r / 255;
    final gf = g / 255;
    final bf = b / 255;
    final k = 1 - [rf, gf, bf].reduce(maxOf);
    if (k == 1) return [0, 0, 0, 100];
    final c = (1 - rf - k) / (1 - k);
    final m = (1 - gf - k) / (1 - k);
    final y = (1 - bf - k) / (1 - k);
    return [
      (c * 100).round(),
      (m * 100).round(),
      (y * 100).round(),
      (k * 100).round(),
    ];
  }

  double maxOf(double a, double b) => a > b ? a : b;
  double minOf(double a, double b) => a < b ? a : b;

  @override
  Widget build(BuildContext context) {
    return _ResizableSplit(
      horizontal: true,
      initialRatio: 0.74,
      minFirstExtent: 420,
      minSecondExtent: 280,
      first: _buildColorDetails(context),
      second: _ColorPalettePanel(
        color: _color,
        hex: _hex.text,
        rgb: _rgb.text,
        onColorChanged: _setColor,
      ),
    );
  }

  Widget _buildColorDetails(BuildContext context) {
    final appColors = context.appColors;
    final rows = [
      ('Hex', _hex.text),
      ('Hex alpha', _hexAlpha.text),
      ('RGB', _rgb.text),
      ('RGBA', _rgba.text),
      ('HSL', _hsl.text),
      ('HSLA', _hsla.text),
      ('HSB (HSV)', _hsv.text),
      ('HWB', _hwb.text),
      ('CMYK', _cmyk.text),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: _toolSurfaceDecoration(context),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Input',
                  style: TextStyle(
                    color: appColors.editorText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InlineTextField(
                    hintText: '#5CC07F, rgb(92, 192, 127)',
                    controller: _input,
                    onChanged: _updateFromInput,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: _errorToolTextStyle(context)),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return _ColorValueRow(label: row.$1, value: row.$2);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Color?> _showColorPickerDialog(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _ColorPickerDialog(initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexField;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexField = TextEditingController(
      text: _cssHex(widget.initial).toUpperCase(),
    );
  }

  @override
  void dispose() {
    _hexField.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  void _update(HSVColor next) {
    setState(() {
      _hsv = next;
      _hexField.text = _cssHex(next.toColor()).toUpperCase();
    });
  }

  void _applyHex(String text) {
    final parsed = _parseColorValue(text);
    if (parsed != null) {
      setState(() => _hsv = HSVColor.fromColor(parsed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Dialog(
      backgroundColor: appColors.panelElevated,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.5,
                child: _SvPicker(hsv: _hsv, onChanged: _update),
              ),
              const SizedBox(height: 12),
              _HueBar(
                hue: _hsv.hue,
                onChanged: (hue) => _update(_hsv.withHue(hue)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: appColors.border),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _hexField,
                      onChanged: _applyHex,
                      onSubmitted: _applyHex,
                      style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_color),
                    child: const Text('Select'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SvPicker extends StatelessWidget {
  const _SvPicker({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        void handle(Offset position) {
          final saturation = (position.dx / width).clamp(0.0, 1.0);
          final value = (1 - position.dy / height).clamp(0.0, 1.0);
          onChanged(hsv.withSaturation(saturation).withValue(value));
        }

        return GestureDetector(
          onPanDown: (details) => handle(details.localPosition),
          onPanUpdate: (details) => handle(details.localPosition),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: hueColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.white, Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: hsv.saturation * width - 8,
                top: (1 - hsv.value) * height - 8,
                child: _PickerThumb(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void handle(Offset position) {
          onChanged((position.dx / width * 360).clamp(0.0, 360.0));
        }

        return GestureDetector(
          onPanDown: (details) => handle(details.localPosition),
          onPanUpdate: (details) => handle(details.localPosition),
          child: SizedBox(
            height: 18,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF0000),
                          Color(0xFFFFFF00),
                          Color(0xFF00FF00),
                          Color(0xFF00FFFF),
                          Color(0xFF0000FF),
                          Color(0xFFFF00FF),
                          Color(0xFFFF0000),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: hue / 360 * width - 8,
                  top: 1,
                  child: _PickerThumb(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PickerThumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
      ),
    );
  }
}

class _ColorPalettePanel extends StatelessWidget {
  const _ColorPalettePanel({
    required this.color,
    required this.hex,
    required this.rgb,
    required this.onColorChanged,
  });

  final Color color;
  final String hex;
  final String rgb;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final hsv = HSVColor.fromColor(color);
    final alpha = _colorComponent(color.a);
    final textColor = _readableTextColor(color);
    final presets = const [
      Color(0xFFE11D48),
      Color(0xFFF97316),
      Color(0xFFEAB308),
      Color(0xFF22C55E),
      Color(0xFF14B8A6),
      Color(0xFF06B6D4),
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFF111827),
      Color(0xFF6B7280),
      Color(0xFFF8FAFC),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
      child: Container(
        key: const ValueKey('color-converter-swatch-panel'),
        decoration: _toolSurfaceDecoration(context),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Palette',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () async {
                    final picked = await _showColorPickerDialog(context, color);
                    if (picked != null) onColorChanged(picked);
                  },
                  child: Tooltip(
                    message: 'Click to pick a color',
                    child: Container(
                      height: 104,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: appColors.border),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            hex.isEmpty ? '#000000' : hex.toUpperCase(),
                            style: TextStyle(
                              color: textColor,
                              fontFamily: 'Menlo',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rgb,
                            style: TextStyle(
                              color: textColor.withAlpha(225),
                              fontFamily: 'Menlo',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ColorSlider(
                label: 'Hue',
                value: hsv.hue,
                min: 0,
                max: 360,
                divisions: 360,
                displayValue: '${hsv.hue.round()}deg',
                onChanged: (value) {
                  onColorChanged(hsv.withHue(value).toColor());
                },
              ),
              _ColorSlider(
                label: 'Saturation',
                value: hsv.saturation * 100,
                min: 0,
                max: 100,
                divisions: 100,
                displayValue: '${(hsv.saturation * 100).round()}%',
                onChanged: (value) {
                  onColorChanged(hsv.withSaturation(value / 100).toColor());
                },
              ),
              _ColorSlider(
                label: 'Value',
                value: hsv.value * 100,
                min: 0,
                max: 100,
                divisions: 100,
                displayValue: '${(hsv.value * 100).round()}%',
                onChanged: (value) {
                  onColorChanged(hsv.withValue(value / 100).toColor());
                },
              ),
              _ColorSlider(
                label: 'Alpha',
                value: alpha.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                displayValue: alpha.toString(),
                onChanged: (value) {
                  onColorChanged(
                    Color.fromARGB(
                      value.round(),
                      _colorComponent(color.r),
                      _colorComponent(color.g),
                      _colorComponent(color.b),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Presets',
                style: TextStyle(
                  color: appColors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in presets)
                    _PaletteChip(
                      color: preset,
                      selected: _sameColorIgnoringAlpha(color, preset),
                      onTap: () {
                        onColorChanged(
                          Color.fromARGB(
                            alpha,
                            _colorComponent(preset.r),
                            _colorComponent(preset.g),
                            _colorComponent(preset.b),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                displayValue,
                style: TextStyle(
                  color: appColors.mutedText,
                  fontFamily: 'Menlo',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Semantics(
      button: true,
      label: 'Pick ${_cssHex(color).toUpperCase()}',
      child: InkWell(
        key: ValueKey('color-preset-${_cssHex(color)}'),
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? appColors.accent : appColors.border,
              width: selected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorValueRow extends StatelessWidget {
  const _ColorValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Listener(
      onPointerDown: (event) {
        if ((event.buttons & kSecondaryMouseButton) != 0) {
          showMenu<String>(
            context: context,
            color: appColors.panelElevated,
            position: RelativeRect.fromLTRB(
              event.position.dx,
              event.position.dy,
              event.position.dx,
              event.position.dy,
            ),
            items: const [
              PopupMenuItem(value: 'copy', child: Text('Copy value')),
            ],
          ).then((selected) {
            if (selected == 'copy') {
              Clipboard.setData(ClipboardData(text: value));
            }
          });
        }
      },
      child: Container(
        decoration: _toolSurfaceDecoration(context, radius: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: Text(
                label,
                style: TextStyle(
                  color: appColors.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  value,
                  style: TextStyle(
                    color: appColors.editorText,
                    fontFamily: 'Menlo',
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color? _parseColorValue(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;

  final rgbMatch = RegExp(
    r'^rgba?\(([^)]+)\)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (rgbMatch != null) {
    final parts = rgbMatch
        .group(1)!
        .split(RegExp(r'\s*,\s*|\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3 || parts.length > 4) return null;
    final r = _parseColorByte(parts[0]);
    final g = _parseColorByte(parts[1]);
    final b = _parseColorByte(parts[2]);
    if (r == null || g == null || b == null) return null;
    final alpha = parts.length == 4 ? _parseAlpha(parts[3]) : 255;
    if (alpha == null) return null;
    return Color.fromARGB(alpha, r, g, b);
  }

  if (value.startsWith('#')) {
    value = value.substring(1);
  } else if (value.toLowerCase().startsWith('0x')) {
    final hex = value.substring(2).replaceAll(RegExp(r'[\s_]+'), '');
    if (hex.length != 8) return null;
    final argb = int.tryParse(hex, radix: 16);
    return argb == null ? null : Color(argb);
  }

  final hex = value.replaceAll(RegExp(r'[\s_]+'), '');
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;

  String expandShort(String input) =>
      input.split('').map((char) => '$char$char').join();

  final normalized = switch (hex.length) {
    3 => '${expandShort(hex)}ff',
    4 => expandShort(hex),
    6 => '${hex}ff',
    8 => hex,
    _ => '',
  };
  if (normalized.isEmpty) return null;
  final r = int.parse(normalized.substring(0, 2), radix: 16);
  final g = int.parse(normalized.substring(2, 4), radix: 16);
  final b = int.parse(normalized.substring(4, 6), radix: 16);
  final a = int.parse(normalized.substring(6, 8), radix: 16);
  return Color.fromARGB(a, r, g, b);
}

int? _parseColorByte(String text) {
  if (text.endsWith('%')) {
    final percent = double.tryParse(text.substring(0, text.length - 1));
    if (percent == null || percent < 0 || percent > 100) return null;
    return (percent * 2.55).round().clamp(0, 255);
  }
  final value = int.tryParse(text);
  if (value == null || value < 0 || value > 255) return null;
  return value;
}

int? _parseAlpha(String text) {
  if (text.endsWith('%')) {
    final percent = double.tryParse(text.substring(0, text.length - 1));
    if (percent == null || percent < 0 || percent > 100) return null;
    return (percent * 2.55).round().clamp(0, 255);
  }
  final decimal = double.tryParse(text);
  if (decimal == null) return null;
  if (decimal >= 0 && decimal <= 1) return (decimal * 255).round();
  if (decimal >= 0 && decimal <= 255) return decimal.round();
  return null;
}

String _cssHex(Color color, {bool includeAlpha = false}) {
  final values = [
    _colorComponent(color.r),
    _colorComponent(color.g),
    _colorComponent(color.b),
    if (includeAlpha) _colorComponent(color.a),
  ];
  return '#${_bytesToHex(values, lower: true)}';
}

bool _sameColorIgnoringAlpha(Color a, Color b) {
  return _colorComponent(a.r) == _colorComponent(b.r) &&
      _colorComponent(a.g) == _colorComponent(b.g) &&
      _colorComponent(a.b) == _colorComponent(b.b);
}

Color _readableTextColor(Color color) {
  final r = _colorComponent(color.r);
  final g = _colorComponent(color.g);
  final b = _colorComponent(color.b);
  final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.58 ? const Color(0xFF111827) : Colors.white;
}

class _RandomStringGeneratorView extends StatefulWidget {
  const _RandomStringGeneratorView();

  @override
  State<_RandomStringGeneratorView> createState() =>
      _RandomStringGeneratorViewState();
}

class _RandomStringGeneratorViewState
    extends State<_RandomStringGeneratorView> {
  final TextEditingController _seed = TextEditingController(
    text: '904731371168665084',
  );
  final TextEditingController _upper = TextEditingController(text: '18');
  final TextEditingController _lower = TextEditingController(text: '18');
  final TextEditingController _symbols = TextEditingController(text: '2');
  final TextEditingController _digits = TextEditingController(text: '8');
  final TextEditingController _words = TextEditingController(text: '0');
  final TextEditingController _output = TextEditingController();
  String _preset = 'Password';
  String _count = 'x10';

  @override
  void dispose() {
    _seed.dispose();
    _upper.dispose();
    _lower.dispose();
    _symbols.dispose();
    _digits.dispose();
    _words.dispose();
    _output.dispose();
    super.dispose();
  }

  void _generate() {
    final rand = Random();
    final uppers = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final lowers = 'abcdefghijklmnopqrstuvwxyz';
    final symbols = '!@#\$%^&*';
    final digits = '0123456789';
    final upCount = int.tryParse(_upper.text) ?? 0;
    final lowCount = int.tryParse(_lower.text) ?? 0;
    final symCount = int.tryParse(_symbols.text) ?? 0;
    final digCount = int.tryParse(_digits.text) ?? 0;
    final totalCount = (int.tryParse(_count.replaceAll('x', '')) ?? 10);
    final lines = <String>[];
    for (var i = 0; i < totalCount; i++) {
      final buffer = StringBuffer();
      for (var j = 0; j < upCount; j++) {
        buffer.write(uppers[rand.nextInt(uppers.length)]);
      }
      for (var j = 0; j < lowCount; j++) {
        buffer.write(lowers[rand.nextInt(lowers.length)]);
      }
      for (var j = 0; j < symCount; j++) {
        buffer.write(symbols[rand.nextInt(symbols.length)]);
      }
      for (var j = 0; j < digCount; j++) {
        buffer.write(digits[rand.nextInt(digits.length)]);
      }
      lines.add(buffer.toString());
    }
    _output.text = lines.join('\n');
    setState(() {});
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _applyPreset(String preset) {
    final values = switch (preset) {
      'API key' => ('0', '32', '0', '16'),
      'PIN' => ('0', '0', '0', '6'),
      'Token' => ('12', '24', '0', '12'),
      'Slug' => ('0', '24', '0', '4'),
      _ => ('4', '14', '4', '6'),
    };
    setState(() {
      _preset = preset;
      _upper.text = values.$1;
      _lower.text = values.$2;
      _symbols.text = values.$3;
      _digits.text = values.$4;
    });
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    return _ResizableSplit(
      horizontal: true,
      initialRatio: 0.62,
      minFirstExtent: 360,
      minSecondExtent: 320,
      first: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Presets:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SmallDropdown(
                    items: const [
                      'Password',
                      'API key',
                      'PIN',
                      'Token',
                      'Slug',
                    ],
                    initialValue: _preset,
                    onChanged: _applyPreset,
                  ),
                  ToolButton(label: 'Sample', onPressed: _generate),
                ],
              ),
              const SizedBox(height: 12),
              LabeledField(label: 'Seed', controller: _seed),
              LabeledField(label: 'Uppercased Characters', controller: _upper),
              LabeledField(label: 'Lowercased Characters', controller: _lower),
              LabeledField(label: 'Symbols', controller: _symbols),
              LabeledField(label: 'Digits', controller: _digits),
              LabeledField(label: 'Words', controller: _words),
              const LabeledField(label: 'Separator'),
              const LabeledField(label: 'Separating Group Size'),
              const LabeledField(label: 'Custom Character Set'),
            ],
          ),
        ),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Checkbox(value: true, onChanged: null),
              const Text('Colors'),
              const Spacer(),
              SmallDropdown(
                items: const ['x10', 'x20'],
                initialValue: _count,
                onChanged: (value) => setState(() => _count = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EditorPane(
              label: '',
              actions: const [],
              controller: _output,
              readOnly: true,
              placeholder: 'Generated strings...',
              copyAction: _copyOutput,
            ),
          ),
        ],
      ),
    );
  }
}

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
    final data = _format == 'URL Encoded' ? Uri.encodeComponent(svg) : svg;
    _output.text = "background-image: url('data:image/svg+xml,$data');";
    setState(() {});
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
      setState(() => _error = _friendlyFileReadError(error));
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

  void _clear() {
    setState(() {
      _sourceFileName = null;
      _error = null;
      _input.clear();
      _output.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(_error!, style: _errorToolTextStyle(context)),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: _ResizableSplit(
            horizontal: false,
            initialRatio: 0.68,
            first: _ResizableSplit(
              horizontal: false,
              initialRatio: 0.52,
              first: _FileDropTargetRegion(
                targetId: _dropTargetId,
                onDropped: (paths) {
                  if (paths.isNotEmpty) unawaited(_loadSvgFile(paths.first));
                },
                child: EditorPane(
                  label: 'Source',
                  actions: [
                    ToolButton(label: 'Sample', onPressed: _setSample),
                    ToolButton(label: 'Clear', onPressed: _clear),
                  ],
                  controller: _input,
                  onChanged: (_) {
                    _sourceFileName = null;
                    _run();
                  },
                  placeholder: 'Drop an .svg file here or paste SVG source...',
                  showHeader: false,
                  enableFileDrop: false,
                  overlay: _SourceFileControls(
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
                showHeader: false,
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
    );
  }
}

class _FileDropTargetRegion extends StatefulWidget {
  const _FileDropTargetRegion({
    required this.targetId,
    required this.onDropped,
    required this.child,
  });

  final String targetId;
  final FileDropHandler onDropped;
  final Widget child;

  @override
  State<_FileDropTargetRegion> createState() => _FileDropTargetRegionState();
}

class _FileDropTargetRegionState extends State<_FileDropTargetRegion> {
  final GlobalKey _dropKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _registerTarget();
  }

  @override
  void didUpdateWidget(covariant _FileDropTargetRegion oldWidget) {
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

class _SourceFileControls extends StatelessWidget {
  const _SourceFileControls({
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

class _SvgPreviewPane extends StatelessWidget {
  const _SvgPreviewPane({required this.svg});

  final String svg;

  @override
  Widget build(BuildContext context) {
    final trimmed = svg.trim();
    if (trimmed.isEmpty) {
      return Container(
        decoration: _toolSurfaceDecoration(context),
        child: Center(
          child: Text(
            'SVG preview',
            style: TextStyle(color: context.appColors.mutedText),
          ),
        ),
      );
    }
    return _HtmlRenderedPreview(
      html: trimmed,
      overlay: const SizedBox.shrink(),
    );
  }
}

String _friendlyFileReadError(Object error) {
  if (error is FileSystemException) {
    final message = error.message.isEmpty
        ? 'Could not read file.'
        : error.message;
    return error.path == null ? message : '$message: ${error.path}';
  }
  return 'Could not read file: $error';
}

class _CurlToCodeView extends StatefulWidget {
  const _CurlToCodeView();

  @override
  State<_CurlToCodeView> createState() => _CurlToCodeViewState();
}

class _CurlToCodeViewState extends State<_CurlToCodeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _lang = 'NodeJS / Fetch';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final command = _parseCurlCommand(_input.text);
    if (command == null) {
      _output.text = '';
      setState(() {});
      return;
    }
    _output.text = _codeFor(command, _lang);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(
          label: 'Clipboard',
          onPressed: () async {
            final text = await _readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = "curl 'https://devutils.com/'");
            _run();
          },
        ),
        ToolButton(
          label: 'Clear',
          onPressed: () {
            setState(() => _input.clear());
            _output.clear();
          },
        ),
      ],
      outputActions: [
        SmallDropdown(
          items: const [
            'NodeJS / Fetch',
            'JavaScript / axios',
            'JavaScript / node:http',
            'Python / Requests',
            'PHP / cURL',
            'PHP / Guzzle',
            'Go / net/http',
            'Rust / reqwest',
            'C# / HttpClient',
            'Java / HttpClient',
            'Ruby / Net::HTTP',
            'Ruby / Faraday',
            'Swift / URLSession',
            'Dart / http',
            'Dart / dio',
            'wget',
          ],
          initialValue: _lang,
          onChanged: (value) {
            setState(() => _lang = value);
            _run();
          },
        ),
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
    );
  }

  String _codeFor(_CurlCommand command, String language) {
    final url = command.url;
    if (language == 'wget') {
      final output = command.downloadFileName;
      if (output != null) {
        return "wget -O '${_shellEscape(output)}' '${_shellEscape(url)}'";
      }
      return "wget '${_shellEscape(url)}'";
    }
    if (language == 'NodeJS / Fetch') {
      return _nodeFetchCode(command);
    }
    if (language == 'JavaScript / axios') {
      return "import axios from 'axios';\n\naxios.get('$url')\n  .then(res => console.log(res.data))\n  .catch(console.error);";
    }
    if (language == 'JavaScript / node:http') {
      final isHttps = url.startsWith('https');
      final module = isHttps ? 'https' : 'http';
      return "const $module = require('$module');\n\n$module.get('$url', res => {\n  let data = '';\n  res.on('data', chunk => data += chunk);\n  res.on('end', () => console.log(data));\n}).on('error', console.error);";
    }
    if (language == 'Python / Requests') {
      return "import requests\n\nresponse = requests.get('$url')\nprint(response.text)";
    }
    if (language == 'PHP / cURL') {
      return "<?php\n\$ch = curl_init();\ncurl_setopt(\$ch, CURLOPT_URL, '$url');\ncurl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);\n\$response = curl_exec(\$ch);\ncurl_close(\$ch);\n\necho \$response;\n";
    }
    if (language == 'PHP / Guzzle') {
      return "<?php\nrequire 'vendor/autoload.php';\n\n\$client = new GuzzleHttp\\\\Client();\n\$response = \$client->get('$url');\n\necho \$response->getBody();\n";
    }
    if (language == 'Go / net/http') {
      return "package main\n\nimport (\n  \"fmt\"\n  \"io\"\n  \"net/http\"\n)\n\nfunc main() {\n  resp, err := http.Get(\"$url\")\n  if err != nil {\n    panic(err)\n  }\n  defer resp.Body.Close()\n  body, _ := io.ReadAll(resp.Body)\n  fmt.Println(string(body))\n}\n";
    }
    if (language == 'Rust / reqwest') {
      return "use reqwest::blocking;\n\nfn main() -> Result<(), Box<dyn std::error::Error>> {\n  let body = blocking::get(\"$url\")?.text()?;\n  println!(\"{}\", body);\n  Ok(())\n}\n";
    }
    if (language == 'C# / HttpClient') {
      return "using System.Net.Http;\n\nvar client = new HttpClient();\nvar response = await client.GetStringAsync(\"$url\");\nConsole.WriteLine(response);";
    }
    if (language == 'Java / HttpClient') {
      return "import java.net.URI;\nimport java.net.http.HttpClient;\nimport java.net.http.HttpRequest;\nimport java.net.http.HttpResponse;\n\nHttpClient client = HttpClient.newHttpClient();\nHttpRequest request = HttpRequest.newBuilder()\n  .uri(URI.create(\"$url\"))\n  .build();\n\nHttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());\nSystem.out.println(response.body());";
    }
    if (language == 'Ruby / Net::HTTP') {
      return "require 'net/http'\nrequire 'uri'\n\nuri = URI.parse('$url')\nresponse = Net::HTTP.get_response(uri)\nputs response.body";
    }
    if (language == 'Ruby / Faraday') {
      return "require 'faraday'\n\nresponse = Faraday.get('$url')\nputs response.body";
    }
    if (language == 'Swift / URLSession') {
      return "import Foundation\n\nlet url = URL(string: \"$url\")!\nlet task = URLSession.shared.dataTask(with: url) { data, _, error in\n  if let error = error {\n    print(error)\n    return\n  }\n  if let data = data, let text = String(data: data, encoding: .utf8) {\n    print(text)\n  }\n}\n\ntask.resume()\n";
    }
    if (language == 'Dart / http') {
      return "import 'package:http/http.dart' as http;\n\nvoid main() async {\n  final response = await http.get(Uri.parse('$url'));\n  print(response.body);\n}\n";
    }
    if (language == 'Dart / dio') {
      return "import 'package:dio/dio.dart';\n\nvoid main() async {\n  final dio = Dio();\n  final response = await dio.get('$url');\n  print(response.data);\n}\n";
    }
    return "fetch('$url')\n  .then(res => res.text())\n  .then(console.log);";
  }
}

class _CurlCommand {
  const _CurlCommand({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.body,
    this.outputFile,
    this.remoteName = false,
    this.followRedirects = false,
    this.insecure = false,
  });

  final String url;
  final String method;
  final Map<String, String> headers;
  final String? body;
  final String? outputFile;
  final bool remoteName;
  final bool followRedirects;
  final bool insecure;

  String? get downloadFileName {
    if (outputFile != null && outputFile!.isNotEmpty) return outputFile;
    if (!remoteName) return null;
    try {
      final path = Uri.parse(url).path;
      final fileName = p.basename(path);
      return fileName.isEmpty || fileName == '/' ? 'download' : fileName;
    } catch (_) {
      return 'download';
    }
  }
}

_CurlCommand? _parseCurlCommand(String input) {
  final tokens = _splitShellWords(input.trim());
  if (tokens.isEmpty) return null;
  var index = tokens.first == 'curl' ? 1 : 0;
  var method = 'GET';
  final headers = <String, String>{};
  String? body;
  String? url;
  String? outputFile;
  var remoteName = false;
  var followRedirects = false;
  var insecure = false;

  String? nextValue() {
    if (index + 1 >= tokens.length) return null;
    index += 1;
    return tokens[index];
  }

  void parseHeader(String value) {
    final separator = value.indexOf(':');
    if (separator <= 0) return;
    final name = value.substring(0, separator).trim();
    final headerValue = value.substring(separator + 1).trim();
    if (name.isNotEmpty) headers[name] = headerValue;
  }

  const optionsWithValue = {
    '--connect-timeout',
    '--max-time',
    '--retry',
    '--proxy',
    '--resolve',
    '--cacert',
    '--cert',
    '--key',
    '--interface',
    '--user-agent',
    '--referer',
    '-A',
    '-e',
  };

  while (index < tokens.length) {
    final token = tokens[index];
    if (token == '-X' || token == '--request') {
      method = (nextValue() ?? method).toUpperCase();
    } else if (token.startsWith('-X') && token.length > 2) {
      method = token.substring(2).toUpperCase();
    } else if (token == '-H' || token == '--header') {
      final value = nextValue();
      if (value != null) parseHeader(value);
    } else if (token.startsWith('--header=')) {
      parseHeader(token.substring('--header='.length));
    } else if (token == '-d' ||
        token == '--data' ||
        token == '--data-raw' ||
        token == '--data-binary' ||
        token == '--data-urlencode') {
      body = nextValue() ?? '';
      if (method == 'GET') method = 'POST';
    } else if (token.startsWith('--data=')) {
      body = token.substring('--data='.length);
      if (method == 'GET') method = 'POST';
    } else if (token == '-o' || token == '--output') {
      outputFile = nextValue();
    } else if (token.startsWith('--output=')) {
      outputFile = token.substring('--output='.length);
    } else if (token == '-O' || token == '--remote-name') {
      remoteName = true;
    } else if (token == '-I' || token == '--head') {
      method = 'HEAD';
    } else if (token == '-L' || token == '--location') {
      followRedirects = true;
    } else if (token == '-k' || token == '--insecure') {
      insecure = true;
    } else if (token == '-u' || token == '--user') {
      final value = nextValue();
      if (value != null) {
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(value))}';
      }
    } else if (token.startsWith('--user=')) {
      final value = token.substring('--user='.length);
      headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(value))}';
    } else if (optionsWithValue.contains(token)) {
      nextValue();
    } else if (!token.startsWith('-') && url == null) {
      url = token;
    }
    index += 1;
  }

  if (url == null || url.trim().isEmpty) return null;
  return _CurlCommand(
    url: url,
    method: method,
    headers: headers,
    body: body,
    outputFile: outputFile,
    remoteName: remoteName,
    followRedirects: followRedirects,
    insecure: insecure,
  );
}

List<String> _splitShellWords(String input) {
  final words = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaped = false;

  for (final codeUnit in input.codeUnits) {
    final char = String.fromCharCode(codeUnit);
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == '\\') {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (RegExp(r'\s').hasMatch(char)) {
      if (buffer.isNotEmpty) {
        words.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) words.add(buffer.toString());
  return words;
}

String _nodeFetchCode(_CurlCommand command) {
  final downloadFileName = command.downloadFileName;
  final options = _nodeFetchOptions(command);
  final optionsArg = options.isEmpty ? '' : ', $options';
  final fetchLine = 'fetch(${_jsString(command.url)}$optionsArg)';
  if (downloadFileName != null) {
    return "const fs = require('node:fs');\n\n"
        '$fetchLine\n'
        '  .then(async (res) => {\n'
        r'    if (!res.ok) throw new Error(`HTTP ${res.status}`);'
        '\n'
        '    const buffer = Buffer.from(await res.arrayBuffer());\n'
        '    fs.writeFileSync(${_jsString(downloadFileName)}, buffer);\n'
        '  });';
  }
  return '$fetchLine\n'
      '  .then(async (res) => {\n'
      r'    if (!res.ok) throw new Error(`HTTP ${res.status}`);'
      '\n'
      '    return res.text();\n'
      '  })\n'
      '  .then(console.log);';
}

String _nodeFetchOptions(_CurlCommand command) {
  final lines = <String>[];
  if (command.method != 'GET') lines.add("method: '${command.method}'");
  if (command.headers.isNotEmpty) {
    final headerLines = command.headers.entries
        .map(
          (entry) => '    ${_jsString(entry.key)}: ${_jsString(entry.value)},',
        )
        .join('\n');
    lines.add('headers: {\n$headerLines\n  }');
  }
  if (command.body != null) lines.add('body: ${_jsString(command.body!)}');
  if (lines.isEmpty) return '';
  return '{\n  ${lines.join(',\n  ')}\n}';
}

String _jsString(String value) {
  return "'${value.replaceAll('\\', r'\\').replaceAll("'", r"\'")}'";
}

String _shellEscape(String value) {
  return value.replaceAll("'", "'\\''");
}

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
      setState(() => _error = _friendlyFileReadError(error));
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
    final optionsPanel = Container(
      padding: const EdgeInsets.all(12),
      decoration: _toolSurfaceDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Options',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
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
              style: _mutedToolTextStyle(context, fontSize: 12),
            ),
        ],
      ),
    );
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final editors = _ResizableSplit(
          horizontal: true,
          first: _FileDropTargetRegion(
            targetId: _dropTargetId,
            onDropped: (paths) {
              if (paths.isNotEmpty) unawaited(_loadFile(paths.first));
            },
            child: EditorPane(
              label: 'Input',
              actions: [
                ToolButton(
                  label: 'Clipboard',
                  onPressed: () async {
                    final text = await _readClipboardText();
                    setState(() {
                      _sourceFileName = null;
                      _input.text = text;
                    });
                    _run();
                  },
                ),
                ToolButton(
                  label: 'Sample',
                  onPressed: () {
                    setState(() {
                      _sourceFileName = null;
                      _input.text = '{"name":"DevUtils"}';
                    });
                    _run();
                  },
                ),
                ToolButton(
                  label: 'Clear',
                  onPressed: () {
                    setState(() {
                      _sourceFileName = null;
                      _input.clear();
                    });
                    _output.clear();
                  },
                ),
                const SmallDropdown(items: ['JSON'], initialValue: 'JSON'),
              ],
              controller: _input,
              onChanged: (_) {
                _sourceFileName = null;
                _run();
              },
              placeholder: 'Drop a .json file here or enter your text...',
              enableFileDrop: false,
              overlay: _SourceFileControls(
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
          return _ResizableSplit(
            horizontal: true,
            initialRatio: 0.76,
            minSecondExtent: 260,
            first: editors,
            second: options,
          );
        }
        return _ResizableSplit(
          horizontal: false,
          initialRatio: 0.72,
          minSecondExtent: 220,
          first: editors,
          second: options,
        );
      },
    );

    if (_error == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_error!, style: _errorToolTextStyle(context)),
        const SizedBox(height: 8),
        Expanded(child: body),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// JSON -> source code generation (Swift / TypeScript / Kotlin)
// ---------------------------------------------------------------------------

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
            final type = _jsonTypeRef('Swift', f.type) + (f.optional ? '?' : '');
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

// ---------------------------------------------------------------------------
// PHP serialize() / unserialize()
// ---------------------------------------------------------------------------

String _phpSerialize(Object? value) {
  if (value == null) return 'N;';
  if (value is bool) return 'b:${value ? 1 : 0};';
  if (value is int) return 'i:$value;';
  if (value is double) {
    return 'd:${value == value.roundToDouble() ? value.toStringAsFixed(1) : value};';
  }
  if (value is num) return 'd:$value;';
  if (value is String) {
    return 's:${utf8.encode(value).length}:"$value";';
  }
  if (value is List) {
    final buffer = StringBuffer('a:${value.length}:{');
    for (var i = 0; i < value.length; i++) {
      buffer.write('i:$i;');
      buffer.write(_phpSerialize(value[i]));
    }
    buffer.write('}');
    return buffer.toString();
  }
  if (value is Map) {
    final buffer = StringBuffer('a:${value.length}:{');
    value.forEach((key, element) {
      buffer.write(_phpSerializeKey(key));
      buffer.write(_phpSerialize(element));
    });
    buffer.write('}');
    return buffer.toString();
  }
  return 'N;';
}

String _phpSerializeKey(Object? key) {
  final keyString = key.toString();
  final asInt = int.tryParse(keyString);
  if (asInt != null && asInt.toString() == keyString) return 'i:$asInt;';
  return 's:${utf8.encode(keyString).length}:"$keyString";';
}

Object? _phpUnserialize(String input) {
  final (value, next) = _phpParse(input, 0);
  final rest = input.substring(next).trim();
  if (rest.isNotEmpty) {
    throw FormatException('Unexpected trailing data at offset $next');
  }
  return value;
}

(Object?, int) _phpParse(String source, int index) {
  if (index >= source.length) {
    throw const FormatException('Unexpected end of input');
  }
  final type = source[index];
  switch (type) {
    case 'N':
      _expect(source, index + 1, ';');
      return (null, index + 2);
    case 'b':
      final semi = source.indexOf(';', index);
      if (semi == -1) throw const FormatException('Malformed boolean');
      return (source.substring(index + 2, semi) == '1', semi + 1);
    case 'i':
      final semi = source.indexOf(';', index);
      if (semi == -1) throw const FormatException('Malformed integer');
      return (int.parse(source.substring(index + 2, semi)), semi + 1);
    case 'd':
      final semi = source.indexOf(';', index);
      if (semi == -1) throw const FormatException('Malformed double');
      return (double.parse(source.substring(index + 2, semi)), semi + 1);
    case 's':
      final colon1 = source.indexOf(':', index);
      final colon2 = source.indexOf(':', colon1 + 1);
      final length = int.parse(source.substring(colon1 + 1, colon2));
      final start = colon2 + 2; // skip :"
      var consumed = 0;
      var cursor = start;
      while (cursor < source.length && consumed < length) {
        consumed += utf8.encode(source[cursor]).length;
        cursor++;
      }
      final text = source.substring(start, cursor);
      _expect(source, cursor, '"');
      _expect(source, cursor + 1, ';');
      return (text, cursor + 2);
    case 'a':
      final colon1 = source.indexOf(':', index);
      final colon2 = source.indexOf(':', colon1 + 1);
      final count = int.parse(source.substring(colon1 + 1, colon2));
      var cursor = colon2 + 2; // skip :{
      final entries = <Object?, Object?>{};
      var isList = true;
      for (var n = 0; n < count; n++) {
        final (key, afterKey) = _phpParse(source, cursor);
        final (element, afterValue) = _phpParse(source, afterKey);
        entries[key] = element;
        if (key != n) isList = false;
        cursor = afterValue;
      }
      _expect(source, cursor, '}');
      cursor += 1;
      if (isList) return (entries.values.toList(), cursor);
      final map = <String, Object?>{};
      entries.forEach((key, element) => map[key.toString()] = element);
      return (map, cursor);
    default:
      throw FormatException('Unsupported PHP type "$type" at offset $index');
  }
}

void _expect(String source, int index, String expected) {
  if (index >= source.length || source[index] != expected) {
    throw FormatException('Expected "$expected" at offset $index');
  }
}

class _PhpSerializerView extends StatefulWidget {
  const _PhpSerializerView({required this.serialize});

  /// `true` for the serializer (JSON -> PHP), `false` for the unserializer.
  final bool serialize;

  @override
  State<_PhpSerializerView> createState() => _PhpSerializerViewState();
}

class _PhpSerializerViewState extends State<_PhpSerializerView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _output.clear());
      return;
    }
    try {
      if (widget.serialize) {
        final decoded = jsonDecode(text);
        _output.text = _phpSerialize(decoded);
      } else {
        final value = _phpUnserialize(text);
        _output.text = const JsonEncoder.withIndent('  ').convert(value);
      }
    } catch (error) {
      _output.text = widget.serialize
          ? 'Invalid JSON input: $error'
          : 'Invalid PHP serialized input: $error';
    }
    setState(() {});
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _run();
  }

  void _setSample() {
    setState(() {
      _input.text = widget.serialize
          ? '{"name":"DevUtils","tags":["json","php"],"count":3,"active":true}'
          : 'a:3:{s:4:"name";s:8:"DevUtils";s:5:"count";i:3;s:6:"active";b:1;}';
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
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clear),
      ],
      outputActions: [
        ToolButton(
          label: 'Copy',
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
      onInputChanged: (_) => _run(),
      inputPlaceholder: widget.serialize
          ? 'Paste JSON to serialize into a PHP string...'
          : 'Paste a PHP serialized string to decode...',
      outputPlaceholder: widget.serialize
          ? 'PHP serialized output...'
          : 'Decoded JSON output...',
    );
  }
}

// ---------------------------------------------------------------------------
// XML / ERB beautify + minify
// ---------------------------------------------------------------------------

String _beautifyXml(String xml, String indent) {
  final trimmed = xml.trim();
  if (trimmed.isEmpty) return '';
  final tokens = RegExp(
    r'<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<[^>]+>|[^<]+',
  ).allMatches(trimmed);
  final lines = <String>[];
  var level = 0;
  String pad() => List.filled(level, indent).join();
  for (final match in tokens) {
    final token = match.group(0) ?? '';
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) continue;
    if (trimmedToken.startsWith('<')) {
      final isComment = trimmedToken.startsWith('<!--');
      final isCdata = trimmedToken.startsWith('<![CDATA[');
      final isDeclaration =
          trimmedToken.startsWith('<?') || trimmedToken.startsWith('<!');
      final isClosing = trimmedToken.startsWith('</');
      final isSelfClosing =
          trimmedToken.endsWith('/>') || isComment || isCdata || isDeclaration;
      if (isClosing) level = max(0, level - 1);
      lines.add('${pad()}$trimmedToken');
      if (!isClosing && !isSelfClosing) level += 1;
    } else {
      final text = trimmedToken.replaceAll(RegExp(r'\s+'), ' ');
      if (text.isNotEmpty) lines.add('${pad()}$text');
    }
  }
  return lines.join('\n');
}

String _minifyXml(String xml, bool keepComments) {
  var output = xml;
  if (!keepComments) {
    output = output.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  }
  output = output.replaceAll(RegExp(r'>\s+<'), '><');
  output = output.replaceAll(RegExp(r'\s{2,}'), ' ');
  return output.trim();
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
    final continuation =
        RegExp(r'^(else\b|elsif\b|when\b|in\b|rescue\b|ensure\b)').hasMatch(line);
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

class _MarkupBeautifyMinifyView extends StatefulWidget {
  const _MarkupBeautifyMinifyView({
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
  State<_MarkupBeautifyMinifyView> createState() =>
      _MarkupBeautifyMinifyViewState();
}

class _MarkupBeautifyMinifyViewState extends State<_MarkupBeautifyMinifyView> {
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
        : widget.beautify(text, _indentFor(_indent));
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
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: _output.text)),
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

// ---------------------------------------------------------------------------
// X.509 certificate decoding (minimal self-contained DER/ASN.1 parser)
// ---------------------------------------------------------------------------

class _Asn1Node {
  _Asn1Node(this.tag, this.content, this.children);
  final int tag;
  final Uint8List content;
  final List<_Asn1Node> children;
}

class _DerParser {
  _DerParser(this.bytes);
  final Uint8List bytes;
  int _pos = 0;

  _Asn1Node parse() => _parseNode();

  _Asn1Node _parseNode() {
    if (_pos + 2 > bytes.length) {
      throw const FormatException('Truncated DER data');
    }
    final tag = bytes[_pos++];
    var length = bytes[_pos++];
    if ((length & 0x80) != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4) {
        throw const FormatException('Unsupported DER length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[_pos++];
      }
    }
    final contentStart = _pos;
    final contentEnd = contentStart + length;
    if (contentEnd > bytes.length) {
      throw const FormatException('DER length exceeds data');
    }
    final content = Uint8List.sublistView(bytes, contentStart, contentEnd);
    final children = <_Asn1Node>[];
    final constructed = (tag & 0x20) != 0;
    if (constructed) {
      while (_pos < contentEnd) {
        children.add(_parseNode());
      }
    } else {
      _pos = contentEnd;
    }
    return _Asn1Node(tag, content, children);
  }
}

const _x509Oids = <String, String>{
  '2.5.4.3': 'CN',
  '2.5.4.4': 'SN',
  '2.5.4.5': 'serialNumber',
  '2.5.4.6': 'C',
  '2.5.4.7': 'L',
  '2.5.4.8': 'ST',
  '2.5.4.9': 'street',
  '2.5.4.10': 'O',
  '2.5.4.11': 'OU',
  '1.2.840.113549.1.9.1': 'email',
  '1.2.840.113549.1.1.1': 'RSA',
  '1.2.840.113549.1.1.5': 'sha1WithRSA',
  '1.2.840.113549.1.1.11': 'sha256WithRSA',
  '1.2.840.113549.1.1.12': 'sha384WithRSA',
  '1.2.840.113549.1.1.13': 'sha512WithRSA',
  '1.2.840.10045.2.1': 'EC',
  '1.2.840.10045.4.3.2': 'ecdsa-with-SHA256',
  '1.2.840.10045.4.3.3': 'ecdsa-with-SHA384',
  '1.2.840.10045.3.1.7': 'P-256',
  '1.3.132.0.34': 'P-384',
  '1.3.132.0.35': 'P-521',
  '2.5.29.14': 'Subject Key Identifier',
  '2.5.29.15': 'Key Usage',
  '2.5.29.17': 'Subject Alternative Name',
  '2.5.29.19': 'Basic Constraints',
  '2.5.29.31': 'CRL Distribution Points',
  '2.5.29.32': 'Certificate Policies',
  '2.5.29.35': 'Authority Key Identifier',
  '2.5.29.37': 'Extended Key Usage',
  '1.3.6.1.5.5.7.1.1': 'Authority Information Access',
};

String _decodeAsn1Oid(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  final parts = <int>[bytes[0] ~/ 40, bytes[0] % 40];
  var value = 0;
  for (var i = 1; i < bytes.length; i++) {
    value = (value << 7) | (bytes[i] & 0x7f);
    if ((bytes[i] & 0x80) == 0) {
      parts.add(value);
      value = 0;
    }
  }
  return parts.join('.');
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

String _hexColons(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');

String _decodeAsn1Name(_Asn1Node name) {
  final parts = <String>[];
  for (final rdn in name.children) {
    for (final atv in rdn.children) {
      if (atv.children.length >= 2) {
        final oid = _decodeAsn1Oid(atv.children[0].content);
        final key = _x509Oids[oid] ?? oid;
        final value = _decodeAsn1String(atv.children[1]);
        parts.add('$key=$value');
      }
    }
  }
  return parts.isEmpty ? '(none)' : parts.join(', ');
}

String _decodeAsn1String(_Asn1Node node) {
  try {
    return utf8.decode(node.content);
  } catch (_) {
    return latin1.decode(node.content);
  }
}

String _decodeAsn1Time(_Asn1Node node) {
  final raw = ascii.decode(node.content);
  try {
    if (node.tag == 0x17) {
      // UTCTime: YYMMDDHHMMSSZ
      final yy = int.parse(raw.substring(0, 2));
      final year = yy >= 50 ? 1900 + yy : 2000 + yy;
      return '$year-${raw.substring(2, 4)}-${raw.substring(4, 6)} '
          '${raw.substring(6, 8)}:${raw.substring(8, 10)}:${raw.substring(10, 12)} UTC';
    }
    // GeneralizedTime: YYYYMMDDHHMMSSZ
    return '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)} '
        '${raw.substring(8, 10)}:${raw.substring(10, 12)}:${raw.substring(12, 14)} UTC';
  } catch (_) {
    return raw;
  }
}

String _decodeX509Certificate(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'-----(BEGIN|END)[^-]*-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) {
    throw const FormatException('No certificate data found');
  }
  final der = base64.decode(cleaned);
  final root = _DerParser(Uint8List.fromList(der)).parse();
  if (root.children.length < 3) {
    throw const FormatException('Not a valid X.509 certificate structure');
  }
  final tbs = root.children[0];
  final signatureAlgorithm = root.children[1];

  var index = 0;
  var version = 1;
  if (tbs.children.isNotEmpty && (tbs.children[0].tag & 0xff) == 0xA0) {
    final versionNode = tbs.children[0].children.isNotEmpty
        ? tbs.children[0].children[0]
        : null;
    if (versionNode != null) {
      version = _bytesToBigInt(versionNode.content).toInt() + 1;
    }
    index = 1;
  }

  final serial = tbs.children[index++];
  index++; // inner signature algorithm (same as outer)
  final issuer = tbs.children[index++];
  final validity = tbs.children[index++];
  final subject = tbs.children[index++];
  final spki = tbs.children[index++];

  _Asn1Node? extensionsNode;
  for (var i = index; i < tbs.children.length; i++) {
    if ((tbs.children[i].tag & 0xff) == 0xA3) {
      extensionsNode = tbs.children[i];
    }
  }

  final sigOid = _decodeAsn1Oid(signatureAlgorithm.children.first.content);
  final notBefore = validity.children.isNotEmpty
      ? _decodeAsn1Time(validity.children[0])
      : '?';
  final notAfter = validity.children.length > 1
      ? _decodeAsn1Time(validity.children[1])
      : '?';

  final buffer = StringBuffer();
  buffer.writeln('Version: v$version');
  buffer.writeln('Serial Number: ${_hexColons(serial.content)}');
  buffer.writeln('Signature Algorithm: ${_x509Oids[sigOid] ?? sigOid}');
  buffer.writeln();
  buffer.writeln('Issuer: ${_decodeAsn1Name(issuer)}');
  buffer.writeln('Subject: ${_decodeAsn1Name(subject)}');
  buffer.writeln();
  buffer.writeln('Not Before: $notBefore');
  buffer.writeln('Not After:  $notAfter');
  buffer.writeln();
  buffer.writeln('Public Key: ${_describePublicKey(spki)}');

  if (extensionsNode != null && extensionsNode.children.isNotEmpty) {
    final extensionList = extensionsNode.children[0];
    final sans = <String>[];
    final names = <String>[];
    for (final ext in extensionList.children) {
      if (ext.children.isEmpty) continue;
      final oid = _decodeAsn1Oid(ext.children[0].content);
      names.add(_x509Oids[oid] ?? oid);
      if (oid == '2.5.29.17') {
        try {
          final inner = _DerParser(
            Uint8List.fromList(ext.children.last.content),
          ).parse();
          for (final generalName in inner.children) {
            if ((generalName.tag & 0x1f) == 2) {
              sans.add(ascii.decode(generalName.content));
            }
          }
        } catch (_) {
          // Ignore malformed SAN.
        }
      }
    }
    buffer.writeln();
    if (sans.isNotEmpty) {
      buffer.writeln('Subject Alternative Names: ${sans.join(', ')}');
    }
    if (names.isNotEmpty) {
      buffer.writeln('Extensions: ${names.join(', ')}');
    }
  }

  return buffer.toString().trimRight();
}

String _describePublicKey(_Asn1Node spki) {
  if (spki.children.length < 2) return 'Unknown';
  final algorithm = spki.children[0];
  final algOid = _decodeAsn1Oid(algorithm.children.first.content);
  if (algOid == '1.2.840.113549.1.1.1') {
    try {
      final bitString = spki.children[1];
      final inner = _DerParser(
        Uint8List.fromList(bitString.content.sublist(1)),
      ).parse();
      if (inner.children.isNotEmpty) {
        final modulus = inner.children[0].content;
        var bits = modulus.length * 8;
        if (modulus.isNotEmpty && modulus[0] == 0) bits -= 8;
        return 'RSA $bits-bit';
      }
    } catch (_) {
      // fall through
    }
    return 'RSA';
  }
  if (algOid == '1.2.840.10045.2.1') {
    if (algorithm.children.length > 1 && algorithm.children[1].tag == 0x06) {
      final curveOid = _decodeAsn1Oid(algorithm.children[1].content);
      return 'EC (${_x509Oids[curveOid] ?? curveOid})';
    }
    return 'EC';
  }
  return _x509Oids[algOid] ?? algOid;
}

class _CertificateDecoderView extends StatefulWidget {
  const _CertificateDecoderView();

  @override
  State<_CertificateDecoderView> createState() =>
      _CertificateDecoderViewState();
}

class _CertificateDecoderViewState extends State<_CertificateDecoderView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _output.clear());
      return;
    }
    try {
      _output.text = _decodeX509Certificate(text);
    } catch (error) {
      _output.text = 'Could not decode certificate: $error';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(
          label: 'Clipboard',
          onPressed: () async {
            final text = await _readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = _sampleCertificate);
            _run();
          },
        ),
        ToolButton(
          label: 'Clear',
          onPressed: () {
            setState(() => _input.clear());
            _output.clear();
          },
        ),
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
      inputPlaceholder: 'Paste a PEM certificate (-----BEGIN CERTIFICATE-----)...',
      outputPlaceholder: 'Decoded certificate details...',
    );
  }
}

const _sampleCertificate = '''-----BEGIN CERTIFICATE-----
MIIB7DCCAZOgAwIBAgIUVoA8oGwVpSjBzBTZcGW+bY77CmswCgYIKoZIzj0EAwIw
ODEWMBQGA1UEAwwNRGV2VXRpbHMgRGVtbzERMA8GA1UECgwIRGV2VXRpbHMxCzAJ
BgNVBAYTAlVTMB4XDTI2MDUzMDE2NDc1MFoXDTM2MDUyNzE2NDc1MFowODEWMBQG
A1UEAwwNRGV2VXRpbHMgRGVtbzERMA8GA1UECgwIRGV2VXRpbHMxCzAJBgNVBAYT
AlVTMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE7XbscG+Ek23v6rDBkdnGa1OE
3rI7vDAyBcAUqZnU1p4LZiCMNlVdVFt6bjqVjBxbWOwBwnYswRy8YJ4i6ZOMnaN7
MHkwHQYDVR0OBBYEFJrW+aR5bA8mT7OWm0E73Ygwmh3MMB8GA1UdIwQYMBaAFJrW
+aR5bA8mT7OWm0E73Ygwmh3MMA8GA1UdEwEB/wQFMAMBAf8wJgYDVR0RBB8wHYIO
ZGV2dXRpbHMubG9jYWyCC2V4YW1wbGUuY29tMAoGCCqGSM49BAMCA0cAMEQCIHAo
w6Cw52/VHxNACem1bTn7QXTHGITl/14Yw2rHvmblAiBkFlK4UR9TuVb5xhfbDlGf
P5PAClqna/CMiQUAYnkaxQ==
-----END CERTIFICATE-----''';

class _PhpToJsView extends StatefulWidget {
  const _PhpToJsView();

  @override
  State<_PhpToJsView> createState() => _PhpToJsViewState();
}

class _PhpToJsViewState extends State<_PhpToJsView> {
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
        _output.clear();
        _error = null;
      });
      return;
    }
    try {
      _output.text = PhpToJsConverter.convert(_input.text);
      _error = null;
    } catch (error) {
      _output.clear();
      _error = 'Could not convert: $error';
    }
    setState(() {});
  }

  void _setSample() {
    setState(() {
      _input.text = r'''<?php

class UserCard {
    public $name;
    private $createdAt;

    public function __construct($name) {
        $this->name = $name;
        $this->createdAt = new Date();
    }

    public function greet($times = 1) {
        $message = "";
        foreach ($this->items as $key => $item) {
            $message .= "Hello $item! ";
        }
        return $message;
    }
}
''';
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(_error!, style: _errorToolTextStyle(context)),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: buildSplitEditors(
            horizontal: true,
            inputController: _input,
            outputController: _output,
            onInputChanged: (_) => _run(),
            inputActions: [
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(
                label: 'Clear',
                onPressed: () {
                  setState(() {
                    _input.clear();
                    _output.clear();
                    _error = null;
                  });
                },
              ),
            ],
            outputActions: [
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            inputPlaceholder: '<?php\n\$name = "DevUtils";\necho "Hello \$name";',
            outputPlaceholder: 'JavaScript output...',
            showInputHeader: false,
            showOutputHeader: false,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Heuristic transpile (token state machine, ported from '
          'Danack/PHP-to-Javascript) — review output for complex code.',
          style: _mutedToolTextStyle(context, fontSize: 12),
        ),
      ],
    );
  }
}

class _HexAsciiConverterView extends StatefulWidget {
  const _HexAsciiConverterView();

  @override
  State<_HexAsciiConverterView> createState() => _HexAsciiConverterViewState();
}

class _HexAsciiConverterViewState extends State<_HexAsciiConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  bool _hexToAscii = true;
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
      if (_hexToAscii) {
        final bytes = <int>[];
        final parts = text.split(RegExp(r'\s+'));
        for (final part in parts) {
          if (part.trim().isEmpty) continue;
          var token = part.trim();
          if (token.startsWith('0x') || token.startsWith('0X')) {
            token = token.substring(2);
          }
          if (token.length.isOdd) {
            token = '0$token';
          }
          for (var i = 0; i < token.length; i += 2) {
            final hexPair = token.substring(i, i + 2);
            bytes.add(int.parse(hexPair, radix: 16));
          }
        }
        _output.text = String.fromCharCodes(bytes);
      } else {
        final bytes = text.codeUnits;
        final buffer = StringBuffer();
        for (var i = 0; i < bytes.length; i++) {
          if (i > 0) buffer.write(' ');
          buffer.write(
            bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase(),
          );
        }
        _output.text = buffer.toString();
      }
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(
                label: 'Clipboard',
                onPressed: () async {
                  final text = await _readClipboardText();
                  setState(() => _input.text = text);
                  _run();
                },
              ),
              ToolButton(
                label: 'Sample',
                onPressed: () {
                  setState(
                    () =>
                        _input.text = _hexToAscii ? '48 65 6C 6C 6F' : 'Hello',
                  );
                  _run();
                },
              ),
              ToolButton(
                label: 'Clear',
                onPressed: () {
                  setState(() => _input.clear());
                  _output.clear();
                },
              ),
              SegmentedToggle(
                options: const ['Hex → ASCII', 'ASCII → Hex'],
                initialIndex: _hexToAscii ? 0 : 1,
                onChanged: (index) {
                  setState(() => _hexToAscii = index == 0);
                  _run();
                },
              ),
            ],
            outputActions: [
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: _hexToAscii ? '48 65 6C 6C 6F' : 'Hello',
            outputPlaceholder: _hexToAscii ? 'Hello' : '48 65 6C 6C 6F',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!, style: _errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

class _AuthTotpView extends StatefulWidget {
  const _AuthTotpView();

  @override
  State<_AuthTotpView> createState() => _AuthTotpViewState();
}

class _AuthTotpViewState extends State<_AuthTotpView> {
  List<_TotpEntry> _entries = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('totp_entries');
      if (raw == null || raw.isEmpty) {
        setState(() {
          _entries = [
            _TotpEntry(
              name: 'twitter',
              secret: 'JBSWY3DPEHPK3PXP',
              color: const Color(0xFFE6E6E6),
            ),
          ];
        });
      } else {
        final decoded = jsonDecode(raw) as List<dynamic>;
        setState(() {
          _entries = decoded
              .map(
                (entry) => _TotpEntry(
                  name: entry['name'] as String? ?? 'New app',
                  secret: entry['secret'] as String? ?? '',
                  color: Color(entry['color'] as int? ?? 0xFFE6E6E6),
                ),
              )
              .toList();
        });
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _openAddDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => _TotpAddDialog(
        onAdd: (entry) {
          setState(() => _entries.add(entry));
          _saveEntries();
        },
      ),
    );
  }

  void _openEditDialog(int index) {
    final entry = _entries[index];
    showDialog<void>(
      context: context,
      builder: (context) => _TotpAddDialog(
        title: 'Edit application',
        actionLabel: 'Save',
        initialEntry: entry,
        onAdd: (updated) {
          setState(() => _entries[index] = updated);
          _saveEntries();
        },
      ),
    );
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _entries
          .map(
            (entry) => {
              'name': entry.name,
              'secret': entry.secret,
              'color': entry.color.toARGB32(),
            },
          )
          .toList(),
    );
    await prefs.setString('totp_entries', encoded);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (var i = 0; i < _entries.length; i++)
            _TotpCard(entry: _entries[i], onEdit: () => _openEditDialog(i)),
          _TotpAddCard(onTap: _openAddDialog),
        ],
      ),
    );
  }
}

class _TotpEntry {
  _TotpEntry({required this.name, required this.secret, required this.color});

  final String name;
  final String secret;
  final Color color;
}

class _TotpCard extends StatelessWidget {
  const _TotpCard({required this.entry, required this.onEdit});

  final _TotpEntry entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final current = _totpCode(entry.secret, now);
    final next = _totpCode(entry.secret, now + 30);
    final secondsRemaining = 30 - (now % 30);
    final warn = secondsRemaining <= 5;
    final blink = warn && (now % 2 == 0);
    final currentColor = blink ? appColors.error : appColors.editorText;
    final nextColor = blink ? appColors.error : appColors.mutedText;
    return Container(
      width: 240,
      height: 132,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: appColors.panelElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
        boxShadow: [
          BoxShadow(
            color: appColors.shadow.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: entry.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current',
                    style: _mutedToolTextStyle(context, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    current,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: currentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next',
                    style: _mutedToolTextStyle(context, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  Text(next, style: TextStyle(fontSize: 14, color: nextColor)),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${secondsRemaining}s',
                    style: _mutedToolTextStyle(context, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: Icon(
                      Icons.edit,
                      size: 16,
                      color: appColors.mutedText,
                    ),
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.name,
            style: TextStyle(fontSize: 13, color: appColors.editorText),
          ),
        ],
      ),
    );
  }
}

class _TotpAddCard extends StatelessWidget {
  const _TotpAddCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 240,
        height: 132,
        decoration: BoxDecoration(
          color: appColors.panelElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: appColors.border),
        ),
        child: Center(
          child: Icon(Icons.add, size: 40, color: appColors.mutedText),
        ),
      ),
    );
  }
}

class _TotpAddDialog extends StatefulWidget {
  const _TotpAddDialog({
    required this.onAdd,
    this.initialEntry,
    this.title = 'New application',
    this.actionLabel = 'Add',
  });

  final ValueChanged<_TotpEntry> onAdd;
  final _TotpEntry? initialEntry;
  final String title;
  final String actionLabel;

  @override
  State<_TotpAddDialog> createState() => _TotpAddDialogState();
}

class _TotpAddDialogState extends State<_TotpAddDialog> {
  final TextEditingController _secret = TextEditingController();
  final TextEditingController _name = TextEditingController();
  Color _selected = const Color(0xFFE6E6E6);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEntry;
    if (initial != null) {
      _secret.text = initial.secret;
      _name.text = initial.name;
      _selected = initial.color;
    }
  }

  @override
  void dispose() {
    _secret.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final secret = _secret.text.trim();
    final name = _name.text.trim().isEmpty ? 'New app' : _name.text.trim();
    if (secret.isEmpty) return;
    widget.onAdd(_TotpEntry(name: name, secret: secret, color: _selected));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: appColors.panelHeader,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Secret key',
                      style: _mutedToolTextStyle(context, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    _InlineTextField(
                      hintText: 'Paste or enter secret',
                      controller: _secret,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Application name',
                      style: _mutedToolTextStyle(context, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    _InlineTextField(
                      hintText: 'Optional label',
                      controller: _name,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Accent color',
                      style: _mutedToolTextStyle(context, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _totpPalette
                          .map(
                            (color) => GestureDetector(
                              onTap: () => setState(() => _selected = color),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _selected == color
                                        ? appColors.editorText
                                        : appColors.border,
                                    width: _selected == color ? 2 : 1,
                                  ),
                                  boxShadow: _selected == color
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x22000000),
                                            blurRadius: 6,
                                            offset: Offset(0, 2),
                                          ),
                                        ]
                                      : const [],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appColors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(widget.actionLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<Color> _totpPalette = [
  Colors.white,
  Colors.black,
  Color(0xFFFF4A3D),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
  Color(0xFF673AB7),
  Color(0xFF3F51B5),
  Color(0xFF2196F3),
  Color(0xFF03A9F4),
  Color(0xFF00BCD4),
  Color(0xFF009688),
  Color(0xFF4CAF50),
  Color(0xFF8BC34A),
  Color(0xFFCDDC39),
  Color(0xFFFFEB3B),
  Color(0xFFFFC107),
  Color(0xFFFF9800),
  Color(0xFFFF5722),
  Color(0xFF795548),
  Color(0xFF9E9E9E),
  Color(0xFF607D8B),
];

String _totpCode(String secret, int timestampSeconds) {
  final key = _base32Decode(secret);
  if (key.isEmpty) return '------';
  final counter = timestampSeconds ~/ 30;
  final bytes = ByteData(8)..setInt64(0, counter);
  final hmac = crypto.Hmac(crypto.sha1, key);
  final digest = hmac.convert(bytes.buffer.asUint8List()).bytes;
  final offset = digest.last & 0x0f;
  final code =
      ((digest[offset] & 0x7f) << 24) |
      ((digest[offset + 1] & 0xff) << 16) |
      ((digest[offset + 2] & 0xff) << 8) |
      (digest[offset + 3] & 0xff);
  final otp = code % 1000000;
  return otp.toString().padLeft(6, '0');
}

List<int> _base32Decode(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final output = <int>[];
  for (final char in cleaned.split('')) {
    final index = alphabet.indexOf(char);
    if (index == -1) continue;
    buffer = (buffer << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      output.add((buffer >> bits) & 0xff);
    }
  }
  return output;
}

class _YamlToJsonView extends StatefulWidget {
  const _YamlToJsonView();

  @override
  State<_YamlToJsonView> createState() => _YamlToJsonViewState();
}

class _YamlToJsonViewState extends State<_YamlToJsonView> {
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
      final yamlNode = loadYaml(text);
      final normalized = _normalizeYaml(yamlNode);
      final encoder = JsonEncoder.withIndent(_indentFor(_indent));
      _output.text = encoder.convert(normalized);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    const sample =
        '- item: Super Hoop\n  quantity: 1\n- item: Basketball\n  quantity: 4';
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
            inputController: _input,
            outputController: _output,
            inputPlaceholder: '---\n- item: Super Hoop',
            outputPlaceholder: '[]',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!, style: _errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

dynamic _normalizeYaml(dynamic node) {
  if (node is YamlMap) {
    return node.map(
      (key, value) => MapEntry(key.toString(), _normalizeYaml(value)),
    );
  }
  if (node is YamlList) {
    return node.map(_normalizeYaml).toList();
  }
  return node;
}

class _YamlJsonConverterView extends StatefulWidget {
  const _YamlJsonConverterView();

  @override
  State<_YamlJsonConverterView> createState() => _YamlJsonConverterViewState();
}

class _YamlJsonConverterViewState extends State<_YamlJsonConverterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _indent = '2 spaces';
  bool _yamlToJson = true;
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
      if (_yamlToJson) {
        final yamlNode = loadYaml(text);
        final normalized = _normalizeYaml(yamlNode);
        final encoder = JsonEncoder.withIndent(_indentFor(_indent));
        _output.text = encoder.convert(normalized);
      } else {
        final jsonData = jsonDecode(text);
        _output.text = _toYamlString(jsonData);
      }
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(() {
      _input.text = _yamlToJson
          ? '- item: Super Hoop\n  quantity: 1\n- item: Basketball\n  quantity: 4'
          : '{"store":{"book":[{"category":"reference","title":"Sayings"}]}}';
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
              SegmentedToggle(
                options: const ['YAML → JSON', 'JSON → YAML'],
                initialIndex: _yamlToJson ? 0 : 1,
                onChanged: (index) {
                  setState(() => _yamlToJson = index == 0);
                  _run();
                },
              ),
            ],
            outputActions: [
              if (_yamlToJson)
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
            inputPlaceholder: _yamlToJson
                ? '---\n- item: Super Hoop'
                : '{"store": {"book": []}}',
            outputPlaceholder: _yamlToJson ? '[]' : 'store:\n  book: []',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!, style: _errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

class _JsonToYamlView extends StatefulWidget {
  const _JsonToYamlView();

  @override
  State<_JsonToYamlView> createState() => _JsonToYamlViewState();
}

class _JsonToYamlViewState extends State<_JsonToYamlView> {
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
      final jsonData = jsonDecode(text);
      _output.text = _toYamlString(jsonData);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    const sample =
        '{"store":{"book":[{"category":"reference","title":"Sayings"}]}}';
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
            ],
            outputActions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
            inputController: _input,
            outputController: _output,
            inputPlaceholder: '{"store": {"book": []}}',
            outputPlaceholder: 'store:\n  book: []',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!, style: _errorToolTextStyle(context)),
          ),
        ],
      ],
    );
  }
}

String _toYamlString(dynamic value, {int indent = 0}) {
  final pad = '  ' * indent;
  if (value is Map) {
    final buffer = StringBuffer();
    for (final entry in value.entries) {
      buffer.write('$pad${entry.key}:');
      if (entry.value is Map || entry.value is List) {
        buffer.write('\n');
        buffer.write(_toYamlString(entry.value, indent: indent + 1));
      } else {
        buffer.write(' ${_yamlScalar(entry.value)}\n');
      }
    }
    return buffer.toString().trimRight();
  }
  if (value is List) {
    final buffer = StringBuffer();
    for (final item in value) {
      if (item is Map || item is List) {
        buffer.write('$pad- \n');
        buffer.write(_toYamlString(item, indent: indent + 1));
        buffer.write('\n');
      } else {
        buffer.write('$pad- ${_yamlScalar(item)}\n');
      }
    }
    return buffer.toString().trimRight();
  }
  return '$pad${_yamlScalar(value)}';
}

String _yamlScalar(dynamic value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  final text = value.toString();
  if (text.contains(':') ||
      text.contains('#') ||
      text.contains('"') ||
      text.contains('\n')) {
    final escaped = text.replaceAll('"', '\\"');
    return '"$escaped"';
  }
  return text;
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
    final text = await _readClipboardText();
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
            child: Text(_error!, style: _errorToolTextStyle(context)),
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
          final encoder = JsonEncoder.withIndent(_indentFor(_indent));
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
    return _JsonSplitEditors(
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

class _HashGeneratorView extends StatefulWidget {
  const _HashGeneratorView();

  @override
  State<_HashGeneratorView> createState() => _HashGeneratorViewState();
}

class _HashGeneratorViewState extends State<_HashGeneratorView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _lookupInput = TextEditingController();
  final TextEditingController _wordlist = TextEditingController();
  final TextEditingController _lookupReport = TextEditingController();
  late final HashLookupService _lookupService = HashLookupService();
  bool _lowercase = false;
  bool _lookupRunning = false;
  bool _useDefaultWordlist = true;
  var _hashMode = 0;
  var _lookupStatus = 'Paste a hash, a log line, or text containing hashes.';
  final Map<String, String> _hashes = {};

  @override
  void dispose() {
    _lookupService.close();
    _input.dispose();
    _lookupInput.dispose();
    _wordlist.dispose();
    _lookupReport.dispose();
    super.dispose();
  }

  void _compute() {
    final bytes = utf8.encode(_input.text);
    final digestMap = <String, String>{
      'MD2': _digestHex(MD2Digest(), bytes),
      'MD4': _digestHex(MD4Digest(), bytes),
      'MD5': _digestHex(MD5Digest(), bytes),
      'SHA1': _digestHex(SHA1Digest(), bytes),
      'SHA224': _digestHex(SHA224Digest(), bytes),
      'SHA256': _digestHex(SHA256Digest(), bytes),
      'SHA384': _digestHex(SHA384Digest(), bytes),
      'SHA512': _digestHex(SHA512Digest(), bytes),
      'RIPEMD-128': _digestHex(RIPEMD128Digest(), bytes),
      'RIPEMD-160': _digestHex(RIPEMD160Digest(), bytes),
      'RIPEMD-320': _digestHex(RIPEMD320Digest(), bytes),
      'Tiger': _digestHex(TigerDigest(), bytes),
      'Whirlpool': _digestHex(WhirlpoolDigest(), bytes),
      'Keccak-256': _digestHex(KeccakDigest(256), bytes),
    };
    _hashes
      ..clear()
      ..addAll(
        digestMap.map(
          (key, value) =>
              MapEntry(key, _lowercase ? value.toLowerCase() : value),
        ),
      );
    setState(() {});
  }

  String _digestHex(dynamic digest, List<int> bytes) {
    final out = digest.process(Uint8List.fromList(bytes));
    return _bytesToHex(out);
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _compute();
  }

  void _setSample() {
    setState(() => _input.text = 'Ut quidam aut expedita porro ut ipsa ea et');
    _compute();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _hashes.clear();
    });
  }

  Future<void> _copyHash(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  void _useGeneratedHash(String algorithm) {
    final hash = _hashes[algorithm];
    if (hash == null || hash.isEmpty) return;
    setState(() {
      _hashMode = 1;
      _lookupInput.text = hash;
      _lookupStatus = 'Loaded $algorithm hash for lookup.';
    });
    _analyzeLookup();
  }

  List<String> _lookupWords() {
    final words = <String>[
      if (_useDefaultWordlist) ...HashLookupService.defaultWordlist,
      ...const LineSplitter().convert(_wordlist.text),
    ];
    return words;
  }

  void _analyzeLookup() {
    final candidates = HashLookupService.extractCandidates(_lookupInput.text);
    setState(() {
      _lookupStatus = candidates.isEmpty
          ? 'No supported hex hashes found.'
          : '${candidates.length} supported hash${candidates.length == 1 ? '' : 'es'} found.';
      _lookupReport.text = _hashCandidateReport(candidates);
    });
  }

  Future<void> _crackLocal() async {
    if (_lookupRunning) return;
    setState(() {
      _lookupRunning = true;
      _lookupStatus = 'Trying local wordlist...';
    });
    final results = await _lookupService.crackWithWordlist(
      input: _lookupInput.text,
      words: _lookupWords(),
    );
    if (!mounted) return;
    setState(() {
      _lookupRunning = false;
      _lookupStatus = _resultStatus(results, source: 'local wordlist');
      _lookupReport.text = _hashResultReport(results);
    });
  }

  Future<void> _lookupOnline() async {
    if (_lookupRunning) return;
    setState(() {
      _lookupRunning = true;
      _lookupStatus = 'Checking online hash databases...';
    });
    final results = await _lookupService.lookupOnline(input: _lookupInput.text);
    if (!mounted) return;
    setState(() {
      _lookupRunning = false;
      _lookupStatus = _resultStatus(results, source: 'online lookup');
      _lookupReport.text = _hashResultReport(results);
    });
  }

  String _resultStatus(
    List<HashCrackResult> results, {
    required String source,
  }) {
    if (results.isEmpty) return 'No supported hashes found.';
    final cracked = results.where((result) => result.cracked).length;
    if (cracked == 0) return 'No matches from $source.';
    return '$cracked of ${results.length} hash${results.length == 1 ? '' : 'es'} matched from $source.';
  }

  String _hashCandidateReport(List<HashCandidate> candidates) {
    if (candidates.isEmpty) {
      return 'Supported hash lengths: MD5/MD4/MD2, SHA1, SHA224, SHA256, SHA384, SHA512, Keccak-256.';
    }
    final buffer = StringBuffer();
    for (final candidate in candidates) {
      buffer
        ..writeln(candidate.value)
        ..writeln('  possible: ${candidate.label}')
        ..writeln();
    }
    return buffer.toString().trimRight();
  }

  String _hashResultReport(List<HashCrackResult> results) {
    if (results.isEmpty) return 'No supported hashes found.';
    final buffer = StringBuffer();
    for (final result in results) {
      buffer
        ..writeln(result.hash)
        ..writeln('  algorithm: ${result.algorithm}')
        ..writeln('  source: ${result.source}')
        ..writeln('  status: ${result.status}');
      if (result.plaintext != null) {
        buffer.writeln('  plaintext: ${result.plaintext}');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final byteCount = utf8.encode(_input.text).length;
    return _ResizableSplit(
      horizontal: true,
      initialRatio: 0.62,
      minSecondExtent: 360,
      first: EditorPane(
        label: 'Input',
        actions: [
          ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
          ToolButton(label: 'Sample', onPressed: _setSample),
          const ToolButton(label: 'Load file...'),
          ToolButton(label: 'Clear', onPressed: _clearInput),
        ],
        controller: _input,
        onChanged: (_) => _compute(),
        placeholder: 'Enter text to hash...',
      ),
      second: _buildHashSidePanel(context, byteCount),
    );
  }

  Widget _buildHashSidePanel(BuildContext context, int byteCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SegmentedToggle(
              options: const ['Generate', 'Lookup'],
              initialIndex: _hashMode,
              onChanged: (index) => setState(() => _hashMode = index),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _hashMode == 0
                    ? '$byteCount bytes (string)'
                    : 'Hash-Buster style lookup',
                overflow: TextOverflow.ellipsis,
                style: _mutedToolTextStyle(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _hashMode == 0
              ? _buildHashGeneratePanel(context)
              : _buildHashLookupPanel(context),
        ),
      ],
    );
  }

  Widget _buildHashGeneratePanel(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _lowercase,
                onChanged: (value) {
                  setState(() => _lowercase = value ?? false);
                  _compute();
                },
              ),
              Text(
                'lowercased',
                style: TextStyle(color: context.appColors.editorText),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _HashField(
            label: 'MD2',
            value: _hashes['MD2'] ?? '',
            onCopy: () => _copyHash(_hashes['MD2'] ?? ''),
          ),
          _HashField(
            label: 'MD4',
            value: _hashes['MD4'] ?? '',
            onCopy: () => _copyHash(_hashes['MD4'] ?? ''),
          ),
          _HashField(
            label: 'MD5',
            value: _hashes['MD5'] ?? '',
            onCopy: () => _copyHash(_hashes['MD5'] ?? ''),
            onUse: () => _useGeneratedHash('MD5'),
          ),
          _HashField(
            label: 'SHA1',
            value: _hashes['SHA1'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA1'] ?? ''),
            onUse: () => _useGeneratedHash('SHA1'),
          ),
          _HashField(
            label: 'SHA224',
            value: _hashes['SHA224'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA224'] ?? ''),
          ),
          _HashField(
            label: 'SHA256',
            value: _hashes['SHA256'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA256'] ?? ''),
            onUse: () => _useGeneratedHash('SHA256'),
          ),
          _HashField(
            label: 'SHA384',
            value: _hashes['SHA384'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA384'] ?? ''),
            onUse: () => _useGeneratedHash('SHA384'),
          ),
          _HashField(
            label: 'SHA512',
            value: _hashes['SHA512'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA512'] ?? ''),
            onUse: () => _useGeneratedHash('SHA512'),
          ),
          _HashField(
            label: 'Keccak-256',
            value: _hashes['Keccak-256'] ?? '',
            onCopy: () => _copyHash(_hashes['Keccak-256'] ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _buildHashLookupPanel(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: _toolSurfaceDecoration(context),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hash input',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _HashLookupTextField(
                key: const ValueKey('hash-lookup-input'),
                controller: _lookupInput,
                hint: 'Paste one hash or text containing hashes...',
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => _analyzeLookup(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(
                    value: _useDefaultWordlist,
                    onChanged: _lookupRunning
                        ? null
                        : (value) {
                            setState(() => _useDefaultWordlist = value ?? true);
                          },
                  ),
                  Expanded(
                    child: Text(
                      'Use small built-in wordlist',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: appColors.editorText),
                    ),
                  ),
                ],
              ),
              _HashLookupTextField(
                controller: _wordlist,
                hint: 'Optional wordlist, one candidate per line...',
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ToolButton(
                    label: 'Analyze',
                    onPressed: _lookupRunning ? null : _analyzeLookup,
                  ),
                  ToolButton(
                    label: 'Local crack',
                    onPressed: _lookupRunning ? null : _crackLocal,
                  ),
                  ToolButton(
                    label: 'Online lookup',
                    onPressed: _lookupRunning ? null : _lookupOnline,
                  ),
                  if (_lookupRunning)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_lookupStatus, style: _mutedToolTextStyle(context)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: EditorPane(
            label: 'Result',
            controller: _lookupReport,
            readOnly: true,
            placeholder: 'Hash analysis and crack results...',
            showHeader: false,
            actions: const [],
          ),
        ),
      ],
    );
  }
}

class _TextEncryptionView extends StatefulWidget {
  const _TextEncryptionView();

  @override
  State<_TextEncryptionView> createState() => _TextEncryptionViewState();
}

class _TextEncryptionViewState extends State<_TextEncryptionView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  final TextEditingController _key = TextEditingController();

  String _category = 'Modern';
  String _algorithm = 'AES-256-CBC';
  String _mode = 'Encrypt';
  String _outputFormat = 'Base64';
  String? _error;

  static const _categories = [
    'Modern',
    'Legacy',
    'Stream',
    'Lightweight',
    'Classical',
  ];

  static const _algorithmsByCategory = {
    'Modern': [
      'AES-128-ECB',
      'AES-128-CBC',
      'AES-128-CFB',
      'AES-128-OFB',
      'AES-128-CTR',
      'AES-192-ECB',
      'AES-192-CBC',
      'AES-192-CFB',
      'AES-192-OFB',
      'AES-192-CTR',
      'AES-256-ECB',
      'AES-256-CBC',
      'AES-256-CFB',
      'AES-256-OFB',
      'AES-256-CTR',
      'ChaCha20',
      'Salsa20',
    ],
    'Legacy': ['3DES-CBC', '3DES-ECB', 'RC2-CBC', 'RC2-ECB'],
    'Stream': ['RC4'],
    'Lightweight': ['TEA', 'XTEA'],
    'Classical': ['XOR', 'Vigenere', 'Caesar', 'ROT13', 'Atbash'],
  };

  List<String> get _algorithms => _algorithmsByCategory[_category] ?? [];

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _key.dispose();
    super.dispose();
  }

  void _process() {
    final inputText = _input.text;
    final keyText = _key.text;

    if (inputText.isEmpty) {
      setState(() {
        _output.clear();
        _error = null;
      });
      return;
    }

    if (keyText.isEmpty) {
      setState(() {
        _output.clear();
        _error = 'Please enter a password/key';
      });
      return;
    }

    try {
      String result;
      if (_mode == 'Encrypt') {
        result = _encrypt(inputText, keyText);
      } else {
        result = _decrypt(inputText, keyText);
      }
      setState(() {
        _output.text = result;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _output.clear();
        _error = 'Error: ${e.toString()}';
      });
    }
  }

  String _encrypt(String plaintext, String password) {
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));

    // Classical ciphers - text-based, no binary output
    if (_category == 'Classical') {
      return _encryptClassical(plaintext, password);
    }

    Uint8List result;

    if (_algorithm.startsWith('AES')) {
      result = _encryptAES(plaintextBytes, password);
    } else if (_algorithm == 'ChaCha20') {
      result = _encryptChaCha20(plaintextBytes, password);
    } else if (_algorithm == 'Salsa20') {
      result = _encryptSalsa20(plaintextBytes, password);
    } else if (_algorithm.startsWith('3DES')) {
      result = _encrypt3DES(plaintextBytes, password);
    } else if (_algorithm.startsWith('RC2')) {
      result = _encryptRC2(plaintextBytes, password);
    } else if (_algorithm == 'RC4') {
      result = _encryptRC4(plaintextBytes, password);
    } else if (_algorithm == 'TEA') {
      result = _encryptTEA(plaintextBytes, password);
    } else if (_algorithm == 'XTEA') {
      result = _encryptXTEA(plaintextBytes, password);
    } else {
      throw Exception('Unknown algorithm: $_algorithm');
    }

    return _outputFormat == 'Base64'
        ? base64Encode(result)
        : _bytesToHex(result);
  }

  String _encryptClassical(String plaintext, String key) {
    switch (_algorithm) {
      case 'XOR':
        final keyBytes = utf8.encode(key);
        final textBytes = utf8.encode(plaintext);
        final result = Uint8List(textBytes.length);
        for (var i = 0; i < textBytes.length; i++) {
          result[i] = textBytes[i] ^ keyBytes[i % keyBytes.length];
        }
        return _outputFormat == 'Base64'
            ? base64Encode(result)
            : _bytesToHex(result);
      case 'Vigenere':
        return _vigenereEncrypt(plaintext, key);
      case 'Caesar':
        final shift = int.tryParse(key) ?? 3;
        return _caesarEncrypt(plaintext, shift);
      case 'ROT13':
        return _caesarEncrypt(plaintext, 13);
      case 'Atbash':
        return _atbashCipher(plaintext);
      default:
        throw Exception('Unknown classical cipher');
    }
  }

  Uint8List _encryptAES(Uint8List plaintext, String password) {
    final keySize = _algorithm.contains('128')
        ? 16
        : _algorithm.contains('192')
        ? 24
        : 32;
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, keySize));
    final iv = _generateIV(16);

    final mode = _algorithm.split('-').last;
    Uint8List ciphertext;

    switch (mode) {
      case 'ECB':
        ciphertext = _aesEcbEncrypt(_pkcs7Pad(plaintext, 16), key);
        return ciphertext; // No IV for ECB
      case 'CBC':
        ciphertext = _aesCbcEncrypt(_pkcs7Pad(plaintext, 16), key, iv);
        break;
      case 'CFB':
        ciphertext = _aesCfbEncrypt(plaintext, key, iv);
        break;
      case 'OFB':
        ciphertext = _aesOfbEncrypt(plaintext, key, iv);
        break;
      case 'CTR':
        ciphertext = _aesCtrEncrypt(plaintext, key, iv);
        break;
      default:
        throw Exception('Unknown AES mode: $mode');
    }

    return _combineIvAndCiphertext(iv, ciphertext);
  }

  Uint8List _encryptChaCha20(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = _generateIV(12);

    final cipher = ChaCha20Engine()
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    final ciphertext = cipher.process(plaintext);

    return _combineIvAndCiphertext(nonce, ciphertext);
  }

  Uint8List _encryptSalsa20(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = _generateIV(8);

    final cipher = Salsa20Engine()
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    final ciphertext = cipher.process(plaintext);

    return _combineIvAndCiphertext(nonce, ciphertext);
  }

  Uint8List _encrypt3DES(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 24));
    final padded = _pkcs7Pad(plaintext, 8);

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(DESedeEngine())
        ..init(true, pc.KeyParameter(key));
      return _processBlocks(cipher, padded, 8);
    } else {
      final iv = _generateIV(8);
      final cipher = CBCBlockCipher(DESedeEngine())
        ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _combineIvAndCiphertext(iv, _processBlocks(cipher, padded, 8));
    }
  }

  Uint8List _encryptRC2(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final padded = _pkcs7Pad(plaintext, 8);

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(RC2Engine())
        ..init(true, pc.KeyParameter(key));
      return _processBlocks(cipher, padded, 8);
    } else {
      final iv = _generateIV(8);
      final cipher = CBCBlockCipher(RC2Engine())
        ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _combineIvAndCiphertext(iv, _processBlocks(cipher, padded, 8));
    }
  }

  Uint8List _encryptRC4(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final cipher = RC4Engine()..init(true, pc.KeyParameter(key));
    return cipher.process(plaintext);
  }

  Uint8List _encryptTEA(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final padded = _pkcs7Pad(plaintext, 8);
    return _teaEncrypt(padded, key);
  }

  Uint8List _encryptXTEA(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final padded = _pkcs7Pad(plaintext, 8);
    return _xteaEncrypt(padded, key);
  }

  String _decrypt(String ciphertextStr, String password) {
    // Classical ciphers
    if (_category == 'Classical') {
      return _decryptClassical(ciphertextStr, password);
    }

    Uint8List combined;
    try {
      combined = _outputFormat == 'Base64'
          ? Uint8List.fromList(base64Decode(ciphertextStr.trim()))
          : _hexToBytes(ciphertextStr.trim());
    } catch (e) {
      throw Exception('Invalid $_outputFormat input');
    }

    Uint8List plaintext;

    if (_algorithm.startsWith('AES')) {
      plaintext = _decryptAES(combined, password);
    } else if (_algorithm == 'ChaCha20') {
      plaintext = _decryptChaCha20(combined, password);
    } else if (_algorithm == 'Salsa20') {
      plaintext = _decryptSalsa20(combined, password);
    } else if (_algorithm.startsWith('3DES')) {
      plaintext = _decrypt3DES(combined, password);
    } else if (_algorithm.startsWith('RC2')) {
      plaintext = _decryptRC2(combined, password);
    } else if (_algorithm == 'RC4') {
      plaintext = _decryptRC4(combined, password);
    } else if (_algorithm == 'TEA') {
      plaintext = _decryptTEA(combined, password);
    } else if (_algorithm == 'XTEA') {
      plaintext = _decryptXTEA(combined, password);
    } else {
      throw Exception('Unknown algorithm: $_algorithm');
    }

    return utf8.decode(plaintext);
  }

  String _decryptClassical(String ciphertext, String key) {
    switch (_algorithm) {
      case 'XOR':
        final keyBytes = utf8.encode(key);
        final ciphertextBytes = _outputFormat == 'Base64'
            ? base64Decode(ciphertext)
            : _hexToBytes(ciphertext);
        final result = Uint8List(ciphertextBytes.length);
        for (var i = 0; i < ciphertextBytes.length; i++) {
          result[i] = ciphertextBytes[i] ^ keyBytes[i % keyBytes.length];
        }
        return utf8.decode(result);
      case 'Vigenere':
        return _vigenereDecrypt(ciphertext, key);
      case 'Caesar':
        final shift = int.tryParse(key) ?? 3;
        return _caesarDecrypt(ciphertext, shift);
      case 'ROT13':
        return _caesarEncrypt(ciphertext, 13); // ROT13 is symmetric
      case 'Atbash':
        return _atbashCipher(ciphertext); // Atbash is symmetric
      default:
        throw Exception('Unknown classical cipher');
    }
  }

  Uint8List _decryptAES(Uint8List combined, String password) {
    final keySize = _algorithm.contains('128')
        ? 16
        : _algorithm.contains('192')
        ? 24
        : 32;
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, keySize));

    final mode = _algorithm.split('-').last;
    Uint8List ciphertext;
    Uint8List iv;

    if (mode == 'ECB') {
      ciphertext = combined;
      return _pkcs7Unpad(_aesEcbDecrypt(ciphertext, key));
    }

    if (combined.length < 17) throw Exception('Ciphertext too short');
    iv = Uint8List.fromList(combined.sublist(0, 16));
    ciphertext = Uint8List.fromList(combined.sublist(16));

    switch (mode) {
      case 'CBC':
        return _pkcs7Unpad(_aesCbcDecrypt(ciphertext, key, iv));
      case 'CFB':
        return _aesCfbDecrypt(ciphertext, key, iv);
      case 'OFB':
        return _aesOfbDecrypt(ciphertext, key, iv);
      case 'CTR':
        return _aesCtrDecrypt(ciphertext, key, iv);
      default:
        throw Exception('Unknown AES mode: $mode');
    }
  }

  Uint8List _decryptChaCha20(Uint8List combined, String password) {
    if (combined.length < 13) throw Exception('Ciphertext too short');
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = Uint8List.fromList(combined.sublist(0, 12));
    final ciphertext = Uint8List.fromList(combined.sublist(12));

    final cipher = ChaCha20Engine()
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    return cipher.process(ciphertext);
  }

  Uint8List _decryptSalsa20(Uint8List combined, String password) {
    if (combined.length < 9) throw Exception('Ciphertext too short');
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = Uint8List.fromList(combined.sublist(0, 8));
    final ciphertext = Uint8List.fromList(combined.sublist(8));

    final cipher = Salsa20Engine()
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    return cipher.process(ciphertext);
  }

  Uint8List _decrypt3DES(Uint8List combined, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 24));

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(DESedeEngine())
        ..init(false, pc.KeyParameter(key));
      return _pkcs7Unpad(_processBlocks(cipher, combined, 8));
    } else {
      if (combined.length < 9) throw Exception('Ciphertext too short');
      final iv = Uint8List.fromList(combined.sublist(0, 8));
      final ciphertext = Uint8List.fromList(combined.sublist(8));
      final cipher = CBCBlockCipher(DESedeEngine())
        ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _pkcs7Unpad(_processBlocks(cipher, ciphertext, 8));
    }
  }

  Uint8List _decryptRC2(Uint8List combined, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(RC2Engine())
        ..init(false, pc.KeyParameter(key));
      return _pkcs7Unpad(_processBlocks(cipher, combined, 8));
    } else {
      if (combined.length < 9) throw Exception('Ciphertext too short');
      final iv = Uint8List.fromList(combined.sublist(0, 8));
      final ciphertext = Uint8List.fromList(combined.sublist(8));
      final cipher = CBCBlockCipher(RC2Engine())
        ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _pkcs7Unpad(_processBlocks(cipher, ciphertext, 8));
    }
  }

  Uint8List _decryptRC4(Uint8List ciphertext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final cipher = RC4Engine()..init(false, pc.KeyParameter(key));
    return cipher.process(ciphertext);
  }

  Uint8List _decryptTEA(Uint8List ciphertext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    return _pkcs7Unpad(_teaDecrypt(ciphertext, key));
  }

  Uint8List _decryptXTEA(Uint8List ciphertext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    return _pkcs7Unpad(_xteaDecrypt(ciphertext, key));
  }

  // ============ Helper Methods ============

  Uint8List _generateIV(int size) {
    final iv = Uint8List(size);
    final random = Random.secure();
    for (var i = 0; i < size; i++) {
      iv[i] = random.nextInt(256);
    }
    return iv;
  }

  Uint8List _combineIvAndCiphertext(Uint8List iv, Uint8List ciphertext) {
    final combined = Uint8List(iv.length + ciphertext.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, ciphertext);
    return combined;
  }

  Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padLength = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setRange(0, data.length, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLength;
    }
    return padded;
  }

  Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLength = data.last;
    if (padLength > 0 && padLength <= 16 && padLength <= data.length) {
      return Uint8List.fromList(data.sublist(0, data.length - padLength));
    }
    return data;
  }

  Uint8List _processBlocks(dynamic cipher, Uint8List data, int blockSize) {
    final output = Uint8List(data.length);
    for (var offset = 0; offset < data.length; offset += blockSize) {
      cipher.processBlock(data, offset, output, offset);
    }
    return output;
  }

  // ============ AES Modes ============

  Uint8List _aesEcbEncrypt(Uint8List plaintext, Uint8List key) {
    final cipher = ECBBlockCipher(AESEngine())
      ..init(true, pc.KeyParameter(key));
    return _processBlocks(cipher, plaintext, 16);
  }

  Uint8List _aesEcbDecrypt(Uint8List ciphertext, Uint8List key) {
    final cipher = ECBBlockCipher(AESEngine())
      ..init(false, pc.KeyParameter(key));
    return _processBlocks(cipher, ciphertext, 16);
  }

  Uint8List _aesCbcEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processBlocks(cipher, plaintext, 16);
  }

  Uint8List _aesCbcDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processBlocks(cipher, ciphertext, 16);
  }

  Uint8List _aesCfbEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = CFBBlockCipher(AESEngine(), 128)
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(plaintext);
  }

  Uint8List _aesCfbDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CFBBlockCipher(AESEngine(), 128)
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(ciphertext);
  }

  Uint8List _aesOfbEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = OFBBlockCipher(AESEngine(), 128)
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(plaintext);
  }

  Uint8List _aesOfbDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = OFBBlockCipher(AESEngine(), 128)
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(ciphertext);
  }

  Uint8List _aesCtrEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(plaintext);
  }

  Uint8List _aesCtrDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(ciphertext);
  }

  // ============ TEA / XTEA ============

  Uint8List _teaEncrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = 0;

      for (var j = 0; j < 32; j++) {
        sum = (sum + delta) & 0xFFFFFFFF;
        v0 =
            (v0 + ((((v1 << 4) + k[0]) ^ (v1 + sum)) ^ ((v1 >> 5) + k[1]))) &
            0xFFFFFFFF;
        v1 =
            (v1 + ((((v0 << 4) + k[2]) ^ (v0 + sum)) ^ ((v0 >> 5) + k[3]))) &
            0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  Uint8List _teaDecrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = (delta * 32) & 0xFFFFFFFF;

      for (var j = 0; j < 32; j++) {
        v1 =
            (v1 - ((((v0 << 4) + k[2]) ^ (v0 + sum)) ^ ((v0 >> 5) + k[3]))) &
            0xFFFFFFFF;
        v0 =
            (v0 - ((((v1 << 4) + k[0]) ^ (v1 + sum)) ^ ((v1 >> 5) + k[1]))) &
            0xFFFFFFFF;
        sum = (sum - delta) & 0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  Uint8List _xteaEncrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = 0;

      for (var j = 0; j < 32; j++) {
        v0 =
            (v0 + ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + k[sum & 3]))) &
            0xFFFFFFFF;
        sum = (sum + delta) & 0xFFFFFFFF;
        v1 =
            (v1 +
                ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + k[(sum >> 11) & 3]))) &
            0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  Uint8List _xteaDecrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = (delta * 32) & 0xFFFFFFFF;

      for (var j = 0; j < 32; j++) {
        v1 =
            (v1 -
                ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + k[(sum >> 11) & 3]))) &
            0xFFFFFFFF;
        sum = (sum - delta) & 0xFFFFFFFF;
        v0 =
            (v0 - ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + k[sum & 3]))) &
            0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  int _bytesToUint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  List<int> _bytesToUint32List(Uint8List bytes) {
    final result = <int>[];
    for (var i = 0; i < bytes.length; i += 4) {
      result.add(_bytesToUint32(bytes, i));
    }
    return result;
  }

  List<int> _uint32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  // ============ Classical Ciphers ============

  String _vigenereEncrypt(String plaintext, String key) {
    final keyUpper = key.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (keyUpper.isEmpty) return plaintext;

    final result = StringBuffer();
    var keyIndex = 0;

    for (final char in plaintext.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final charValue = char - base;
        final keyValue = keyUpper.codeUnitAt(keyIndex % keyUpper.length) - 65;
        final encrypted = (charValue + keyValue) % 26;
        result.writeCharCode(base + encrypted);
        keyIndex++;
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  String _vigenereDecrypt(String ciphertext, String key) {
    final keyUpper = key.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (keyUpper.isEmpty) return ciphertext;

    final result = StringBuffer();
    var keyIndex = 0;

    for (final char in ciphertext.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final charValue = char - base;
        final keyValue = keyUpper.codeUnitAt(keyIndex % keyUpper.length) - 65;
        final decrypted = (charValue - keyValue + 26) % 26;
        result.writeCharCode(base + decrypted);
        keyIndex++;
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  String _caesarEncrypt(String text, int shift) {
    final normalizedShift = ((shift % 26) + 26) % 26;
    final result = StringBuffer();

    for (final char in text.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final shifted = (char - base + normalizedShift) % 26;
        result.writeCharCode(base + shifted);
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  String _caesarDecrypt(String text, int shift) {
    return _caesarEncrypt(text, -shift);
  }

  String _atbashCipher(String text) {
    final result = StringBuffer();

    for (final char in text.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final mirrored = 25 - (char - base);
        result.writeCharCode(base + mirrored);
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  // ============ Utility ============

  Uint8List _hexToBytes(String hex) {
    hex = hex.replaceAll(' ', '').replaceAll('\n', '');
    if (hex.length % 2 != 0) throw Exception('Invalid hex length');
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  void _swapInputOutput() {
    final temp = _input.text;
    setState(() {
      _input.text = _output.text;
      _output.text = temp;
      _mode = _mode == 'Encrypt' ? 'Decrypt' : 'Encrypt';
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    // Ensure algorithm is valid for current category
    if (!_algorithms.contains(_algorithm)) {
      _algorithm = _algorithms.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Controls row 1: Category & Algorithm
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Category:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SmallDropdown(
                  items: _categories,
                  initialValue: _category,
                  onChanged: (v) {
                    setState(() {
                      _category = v;
                      _algorithm = _algorithmsByCategory[v]!.first;
                    });
                    _process();
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Algorithm:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SmallDropdown(
                  items: _algorithms,
                  initialValue: _algorithm,
                  onChanged: (v) {
                    setState(() => _algorithm = v);
                    _process();
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Mode:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SegmentedToggle(
                  options: const ['Encrypt', 'Decrypt'],
                  initialIndex: _mode == 'Encrypt' ? 0 : 1,
                  onChanged: (i) {
                    setState(() => _mode = i == 0 ? 'Encrypt' : 'Decrypt');
                    _process();
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Output:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SegmentedToggle(
                  options: const ['Base64', 'Hex'],
                  initialIndex: _outputFormat == 'Base64' ? 0 : 1,
                  onChanged: (i) {
                    setState(() => _outputFormat = i == 0 ? 'Base64' : 'Hex');
                    _process();
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Key input row
        Row(
          children: [
            const Text(
              'Password/Key:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: _toolSurfaceDecoration(context, radius: 6),
                child: TextField(
                  controller: _key,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Enter password for encryption/decryption...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: appColors.mutedText),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  style: TextStyle(fontSize: 12, color: appColors.editorText),
                  onChanged: (_) => _process(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Input/Output editors
        Expanded(
          child: _ResizableSplit(
            horizontal: true,
            first: EditorPane(
              label: _mode == 'Encrypt' ? 'Plaintext' : 'Ciphertext',
              actions: [
                ToolButton(
                  label: 'Clipboard',
                  onPressed: () async {
                    final text = await _readClipboardText();
                    setState(() => _input.text = text);
                    _process();
                  },
                ),
                ToolButton(
                  label: 'Sample',
                  onPressed: () {
                    setState(
                      () => _input.text =
                          'Hello, World! This is a secret message.',
                    );
                    _process();
                  },
                ),
                ToolButton(
                  label: 'Clear',
                  onPressed: () {
                    setState(() {
                      _input.clear();
                      _output.clear();
                      _error = null;
                    });
                  },
                ),
                ToolIconButton(
                  icon: Icons.swap_horiz,
                  tooltip: 'Swap & toggle mode',
                  onPressed: _swapInputOutput,
                ),
              ],
              controller: _input,
              onChanged: (_) => _process(),
              placeholder: _mode == 'Encrypt'
                  ? 'Enter text to encrypt...'
                  : 'Enter ciphertext to decrypt...',
            ),
            second: EditorPane(
              label: _mode == 'Encrypt' ? 'Ciphertext' : 'Plaintext',
              actions: [
                ToolButton(
                  label: 'Copy',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _output.text)),
                ),
              ],
              controller: _output,
              readOnly: true,
              placeholder: _mode == 'Encrypt'
                  ? 'Encrypted output appears here...'
                  : 'Decrypted output appears here...',
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: _errorToolTextStyle(context)),
        ],
      ],
    );
  }
}

class _PayloadEmbedderView extends StatefulWidget {
  const _PayloadEmbedderView();

  @override
  State<_PayloadEmbedderView> createState() => _PayloadEmbedderViewState();
}

class _PayloadEmbedderViewState extends State<_PayloadEmbedderView> {
  final TextEditingController _carrierPath = TextEditingController();
  final TextEditingController _payloadPath = TextEditingController();
  final TextEditingController _outputPath = TextEditingController();
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _status = TextEditingController();
  late final String _dropTargetScope = identityHashCode(this).toRadixString(16);

  int _modeIndex = 0;
  bool _busy = false;
  String? _error;
  EmbeddedPayloadInfo? _info;

  bool get _isEmbed => _modeIndex == 0;
  bool get _isCheck => _modeIndex == 1;
  bool get _isDecode => _modeIndex == 2;
  String get _carrierDropTargetId => 'payload-carrier-file-$_dropTargetScope';
  String get _payloadDropTargetId => 'payload-payload-file-$_dropTargetScope';

  @override
  void dispose() {
    _carrierPath.dispose();
    _payloadPath.dispose();
    _outputPath.dispose();
    _passphrase.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _embed() async {
    await _runFileAction(() async {
      final carrierFile = File(_carrierPath.text.trim());
      final payloadFile = File(_payloadPath.text.trim());
      if (!await carrierFile.exists()) {
        throw const FileSystemException('Carrier/stego file does not exist');
      }
      if (!await payloadFile.exists()) {
        throw const FileSystemException('Payload file does not exist');
      }
      final outputPath = _resolvedEmbedOutputPath(carrierFile.path);
      final result = PayloadEmbeddingService.embed(
        carrier: await carrierFile.readAsBytes(),
        payload: await payloadFile.readAsBytes(),
        payloadFileName: p.basename(payloadFile.path),
        passphrase: _passphrase.text,
      );
      await File(outputPath).writeAsBytes(result.bytes);
      _info = result.info;
      _outputPath.text = outputPath;
      _status.text = [
        'Embedded encrypted file.',
        'Output: $outputPath',
        'Carrier: ${result.info.format.label}',
        'Method: ${result.info.method}',
        'Envelope: ${_formatPayloadBytes(result.info.envelopeSize)}',
        'PBKDF2 iterations: ${result.info.iterations}',
      ].join('\n');
    });
  }

  Future<void> _check({bool preferOutput = false}) async {
    final targetPath = _checkTargetPath(preferOutput: preferOutput);
    await _runFileAction(
      () async {
        final stegoFile = File(targetPath);
        if (!await stegoFile.exists()) {
          throw const FileSystemException('File does not exist');
        }
        final bytes = await stegoFile.readAsBytes();
        _info = PayloadEmbeddingService.inspect(bytes);
        if (_info == null) {
          _status.text = [
            'No DevUtils encrypted payload found.',
            'Checked: $targetPath',
          ].join('\n');
          return;
        }
        _status.text = [
          'Encrypted payload found.',
          'Checked: $targetPath',
          'Carrier: ${_info!.format.label}',
          'Method: ${_info!.method}',
          'Stored envelope: ${_formatPayloadBytes(_info!.envelopeSize)}',
          'Carrier size: ${_formatPayloadBytes(_info!.carrierSize)}',
          'Segments/chunks: ${_info!.segmentCount}',
          'PBKDF2 iterations: ${_info!.iterations}',
        ].join('\n');
      },
      requirePassphrase: false,
      requirePayloadPath: false,
      targetPath: targetPath,
    );
  }

  String _checkTargetPath({required bool preferOutput}) {
    final outputPath = _outputPath.text.trim();
    if (preferOutput && outputPath.isNotEmpty) return outputPath;
    return _carrierPath.text.trim();
  }

  Future<void> _decode() async {
    await _runFileAction(() async {
      final carrierFile = File(_carrierPath.text.trim());
      if (!await carrierFile.exists()) {
        throw const FileSystemException('Carrier/stego file does not exist');
      }
      final bytes = await carrierFile.readAsBytes();
      final decoded = PayloadEmbeddingService.extract(
        carrier: bytes,
        passphrase: _passphrase.text,
      );
      final outputPath = _resolvedDecodeOutputPath(
        carrierFile.path,
        decoded.fileName,
      );
      await File(outputPath).writeAsBytes(decoded.bytes);
      _outputPath.text = outputPath;
      _info = PayloadEmbeddingService.inspect(bytes);
      _status.text = [
        'Decoded embedded file.',
        'Output: $outputPath',
        'Embedded filename: ${decoded.fileName}',
        'Payload size: ${_formatPayloadBytes(decoded.bytes.length)}',
        if (decoded.embeddedAt != null)
          'Embedded at: ${decoded.embeddedAt!.toLocal()}',
      ].join('\n');
    });
  }

  Future<void> _runFileAction(
    Future<void> Function() action, {
    bool requirePassphrase = true,
    bool requirePayloadPath = true,
    String? targetPath,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status.clear();
      _info = null;
    });
    try {
      if ((targetPath ?? _carrierPath.text.trim()).isEmpty) {
        throw ArgumentError('Enter a carrier/stego file path.');
      }
      if (requirePassphrase && _passphrase.text.isEmpty) {
        throw ArgumentError('Enter the passphrase.');
      }
      if (requirePayloadPath && _isEmbed && _payloadPath.text.trim().isEmpty) {
        throw ArgumentError('Enter the payload file path.');
      }
      await action();
    } catch (e) {
      _status.text = '';
      _error = _friendlyPayloadError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _resolvedEmbedOutputPath(String carrierPath) {
    final explicit = _outputPath.text.trim();
    if (explicit.isNotEmpty) {
      final type = FileSystemEntity.typeSync(explicit);
      if (type == FileSystemEntityType.directory) {
        return p.join(explicit, _defaultEmbeddedFileName(carrierPath));
      }
      return explicit;
    }
    return p.join(
      p.dirname(carrierPath),
      _defaultEmbeddedFileName(carrierPath),
    );
  }

  String _defaultEmbeddedFileName(String carrierPath) {
    final extension = p.extension(carrierPath);
    final baseName = p.basenameWithoutExtension(carrierPath);
    return '$baseName.embedded$extension';
  }

  String _resolvedDecodeOutputPath(String carrierPath, String decodedFileName) {
    final explicit = _outputPath.text.trim();
    if (explicit.isNotEmpty) {
      final type = FileSystemEntity.typeSync(explicit);
      if (type == FileSystemEntityType.directory) {
        return p.join(explicit, decodedFileName);
      }
      return explicit;
    }
    final directory = p.dirname(carrierPath);
    return p.join(directory, decodedFileName);
  }

  Future<void> _pickCarrierFile() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'pdf'],
    );
    if (path == null || !mounted) return;
    setState(() {
      _carrierPath.text = path;
      _error = null;
    });
  }

  Future<void> _pickPayloadFile() async {
    final path = await FileDialogService.openFile();
    if (path == null || !mounted) return;
    setState(() {
      _payloadPath.text = path;
      _error = null;
    });
  }

  Future<void> _pickOutputFile() async {
    final carrierPath = _carrierPath.text.trim();
    final suggestedName = carrierPath.isEmpty
        ? (_isDecode ? 'decoded-payload' : 'embedded-output')
        : _isDecode
        ? p.basename(
            _outputPath.text.trim().isEmpty
                ? 'decoded-payload'
                : _outputPath.text.trim(),
          )
        : _defaultEmbeddedFileName(carrierPath);
    final directoryPath = carrierPath.isEmpty ? null : p.dirname(carrierPath);
    final path = await FileDialogService.saveFile(
      suggestedName: suggestedName,
      directoryPath: directoryPath,
      allowedExtensions: _isDecode
          ? const []
          : const ['png', 'jpg', 'jpeg', 'pdf'],
    );
    if (path == null || !mounted) return;
    setState(() {
      _outputPath.text = path;
      _error = null;
    });
  }

  Future<void> _pickOutputDirectory() async {
    final path = await FileDialogService.openDirectory();
    if (path == null || !mounted) return;
    setState(() {
      _outputPath.text = path;
      _error = null;
    });
  }

  void _setDroppedPath(TextEditingController controller, List<String> paths) {
    if (paths.isEmpty) return;
    setState(() {
      controller.text = paths.first;
      _error = null;
    });
  }

  void _setExamplePaths() {
    _carrierPath.text = '/Users/me/Desktop/image.png';
    _payloadPath.text = '/Users/me/Desktop/secret.txt';
    _outputPath.text = '/Users/me/Desktop/image.embedded.png';
    _status.text =
        'Use PNG, JPG, or PDF carriers. The embedded file is encrypted before it is stored.';
    setState(() {
      _error = null;
      _info = null;
    });
  }

  void _clear() {
    _carrierPath.clear();
    _payloadPath.clear();
    _outputPath.clear();
    _passphrase.clear();
    _status.clear();
    setState(() {
      _error = null;
      _info = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ResizableSplit(
      horizontal: true,
      initialRatio: 0.46,
      minFirstExtent: 420,
      minSecondExtent: 360,
      first: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedToggle(
                    options: const ['Embed', 'Check', 'Decode'],
                    initialIndex: _modeIndex,
                    onChanged: (index) => setState(() => _modeIndex = index),
                  ),
                  ToolButton(
                    label: 'Example paths',
                    onPressed: _setExamplePaths,
                  ),
                  ToolButton(label: 'Reset', onPressed: _clear),
                ],
              ),
              const SizedBox(height: 16),
              _PayloadPathField(
                label: _isEmbed ? 'Carrier file' : 'Stego file',
                controller: _carrierPath,
                hint: '/path/to/image.png, image.jpg, or document.pdf',
                onPickFile: _pickCarrierFile,
                dropTargetId: _carrierDropTargetId,
                onDropped: (paths) => _setDroppedPath(_carrierPath, paths),
              ),
              if (_isEmbed) ...[
                const SizedBox(height: 10),
                _PayloadPathField(
                  label: 'Payload file',
                  controller: _payloadPath,
                  hint: '/path/to/secret.txt',
                  onPickFile: _pickPayloadFile,
                  dropTargetId: _payloadDropTargetId,
                  onDropped: (paths) => _setDroppedPath(_payloadPath, paths),
                ),
              ],
              if (!_isCheck) ...[
                const SizedBox(height: 10),
                _PayloadPathField(
                  label: _isDecode ? 'Decoded output' : 'Output file',
                  controller: _outputPath,
                  hint: _isDecode
                      ? 'Leave empty to use embedded filename'
                      : 'Leave empty to create *.embedded.*',
                  onPickFile: _pickOutputFile,
                  onPickDirectory: _pickOutputDirectory,
                ),
              ],
              if (!_isCheck) ...[
                const SizedBox(height: 10),
                _PayloadPathField(
                  label: 'Passphrase',
                  controller: _passphrase,
                  hint: 'Required for encryption/decode',
                  obscureText: true,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_isEmbed)
                    ToolButton(
                      label: _busy ? 'Embedding...' : 'Embed encrypted',
                      onPressed: _busy ? null : _embed,
                    ),
                  if (_isCheck)
                    ToolButton(
                      label: _busy ? 'Checking...' : 'Check embedded data',
                      onPressed: _busy ? null : () => _check(),
                    ),
                  if (!_isCheck)
                    ToolButton(
                      label: _busy
                          ? 'Checking...'
                          : _isEmbed && _outputPath.text.trim().isNotEmpty
                          ? 'Check output'
                          : 'Check embedded data',
                      onPressed: _busy
                          ? null
                          : () => _check(preferOutput: _isEmbed),
                    ),
                  if (_isDecode)
                    ToolButton(
                      label: _busy ? 'Decoding...' : 'Decode',
                      onPressed: _busy ? null : _decode,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _PayloadMethodSummary(),
            ],
          ),
        ),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_info != null) ...[
            _PayloadInfoBar(info: _info!),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            Text(_error!, style: _errorToolTextStyle(context)),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: EditorPane(
              label: 'Result',
              actions: const [],
              controller: _status,
              readOnly: true,
              showHeader: false,
              placeholder:
                  'Embed, check, or decode encrypted files inside PNG, JPG, or PDF carriers...',
            ),
          ),
        ],
      ),
    );
  }
}

class _PayloadPathField extends StatelessWidget {
  const _PayloadPathField({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscureText = false,
    this.onPickFile,
    this.onPickDirectory,
    this.dropTargetId,
    this.onDropped,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final VoidCallback? onPickFile;
  final VoidCallback? onPickDirectory;
  final String? dropTargetId;
  final FileDropHandler? onDropped;

  @override
  Widget build(BuildContext context) {
    return _PayloadPathDropField(
      label: label,
      controller: controller,
      hint: hint,
      obscureText: obscureText,
      onPickFile: onPickFile,
      onPickDirectory: onPickDirectory,
      dropTargetId: dropTargetId,
      onDropped: onDropped,
    );
  }
}

class _PayloadPathDropField extends StatefulWidget {
  const _PayloadPathDropField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.obscureText,
    this.onPickFile,
    this.onPickDirectory,
    this.dropTargetId,
    this.onDropped,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final VoidCallback? onPickFile;
  final VoidCallback? onPickDirectory;
  final String? dropTargetId;
  final FileDropHandler? onDropped;

  @override
  State<_PayloadPathDropField> createState() => _PayloadPathDropFieldState();
}

class _PayloadPathDropFieldState extends State<_PayloadPathDropField> {
  final GlobalKey _dropKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _registerDropTarget();
  }

  @override
  void didUpdateWidget(covariant _PayloadPathDropField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dropTargetId != widget.dropTargetId ||
        oldWidget.onDropped != widget.onDropped) {
      if (oldWidget.dropTargetId != null) {
        FileDropService.unregisterTarget(oldWidget.dropTargetId!);
      }
      _registerDropTarget();
    }
  }

  @override
  void dispose() {
    final targetId = widget.dropTargetId;
    if (targetId != null) FileDropService.unregisterTarget(targetId);
    super.dispose();
  }

  void _registerDropTarget() {
    final targetId = widget.dropTargetId;
    final onDropped = widget.onDropped;
    if (targetId == null || onDropped == null) return;
    FileDropService.registerTarget(targetId, key: _dropKey, handler: onDropped);
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final targetId = widget.dropTargetId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: appColors.editorText,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        MouseRegion(
          onEnter: targetId == null
              ? null
              : (_) => FileDropService.setActiveTarget(targetId),
          onExit: targetId == null
              ? null
              : (_) => FileDropService.setActiveTarget(null),
          child: Row(
            key: _dropKey,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  obscureText: widget.obscureText,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    filled: true,
                    fillColor: appColors.panelElevated,
                  ),
                  style: TextStyle(color: appColors.editorText, fontSize: 13),
                ),
              ),
              if (widget.onPickFile != null) ...[
                const SizedBox(width: 6),
                ToolIconButton(
                  icon: Icons.insert_drive_file,
                  tooltip: 'Choose file',
                  onPressed: widget.onPickFile,
                ),
              ],
              if (widget.onPickDirectory != null) ...[
                const SizedBox(width: 6),
                ToolIconButton(
                  icon: Icons.folder_open,
                  tooltip: 'Choose folder',
                  onPressed: widget.onPickDirectory,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PayloadMethodSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final rows = const [
      ('PNG', 'private ancillary chunk'),
      ('JPG', 'APP15 metadata segments'),
      ('PDF', 'comment payload block'),
      ('Crypto', 'AES-256-CBC + HMAC-SHA256'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _toolSurfaceDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Format support',
            style: TextStyle(
              color: appColors.editorText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        color: appColors.mutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      style: TextStyle(color: appColors.editorText),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PayloadInfoBar extends StatelessWidget {
  const _PayloadInfoBar({required this.info});

  final EmbeddedPayloadInfo info;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: appColors.accentSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(
            info.format.label,
            style: TextStyle(
              color: appColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(info.method, style: TextStyle(color: appColors.editorText)),
          Text(
            _formatPayloadBytes(info.envelopeSize),
            style: TextStyle(color: appColors.mutedText),
          ),
        ],
      ),
    );
  }
}

String _friendlyPayloadError(Object error) {
  if (error is FileSystemException) {
    return error.message;
  }
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Invalid input.';
  }
  if (error is FormatException) {
    return error.message;
  }
  return error.toString();
}

String _formatPayloadBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _UserAgentToolView extends StatefulWidget {
  const _UserAgentToolView();

  @override
  State<_UserAgentToolView> createState() => _UserAgentToolViewState();
}

class _UserAgentToolViewState extends State<_UserAgentToolView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _browser = 'Chrome';
  String _platform = 'Any';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _generate() {
    final platform = _platform == 'Any'
        ? null
        : _UaPlatform.values.firstWhere((value) => value.label == _platform);
    final ua = _UaGenerator.generateFromSelection(_browser, platform);
    setState(() => _input.text = ua);
    _validate();
  }

  void _validate() {
    final result = _UaValidator.validate(_input.text);
    _output.text = _formatUserAgentResult(result);
    setState(() {});
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _validate();
  }

  void _setSample() {
    final sample = _UaGenerator.generate(
      browser: _UaBrowser.chrome,
      platform: _UaPlatform.macOS,
    );
    setState(() => _input.text = sample);
    _validate();
  }

  void _clear() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputLabel: 'User Agent',
      outputLabel: 'Analysis',
      inputActions: [
        ToolButton(label: 'Go', onPressed: _validate),
        ToolButton(label: 'Generate', onPressed: _generate),
        SmallDropdown(
          items: _UaGenerator.browserLabels,
          initialValue: _browser,
          onChanged: (value) => setState(() => _browser = value),
        ),
        SmallDropdown(
          items: _UaGenerator.platformLabels,
          initialValue: _platform,
          onChanged: (value) => setState(() => _platform = value),
        ),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
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
      inputPlaceholder: 'Paste or generate a user agent...',
      outputPlaceholder: 'Analysis appears here...',
      onInputChanged: (_) => _validate(),
    );
  }
}

String _formatUserAgentResult(_UaValidationResult result) {
  final parsed = result.parsed;
  final buffer = StringBuffer();
  buffer.writeln('Summary: ${result.summary}');
  buffer.writeln('Score: ${result.score}');
  buffer.writeln('Valid: ${result.isValid ? "Yes" : "No"}');
  buffer.writeln('Confidence: ${(parsed.confidence * 100).round()}%');
  buffer.writeln('Length: ${parsed.raw.length}');
  if (parsed.isBot) {
    buffer.writeln('Bot: ${parsed.botName ?? "Unknown"}');
  }
  if (parsed.browser != null) {
    final browser = parsed.browser!;
    buffer.writeln('Browser: ${browser.name} ${browser.version}');
    if (browser.isWebView) {
      buffer.writeln('WebView: Yes');
    }
  }
  if (parsed.webView != null) {
    final webView = parsed.webView!;
    buffer.writeln('WebView App: ${webView.app}');
    if (webView.appVersion != null) {
      buffer.writeln('App Version: ${webView.appVersion}');
    }
    if (webView.buildId != null) {
      buffer.writeln('Build ID: ${webView.buildId}');
    }
    if (webView.additionalInfo.isNotEmpty) {
      buffer.writeln('App Details:');
      webView.additionalInfo.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
    }
  }
  if (parsed.platform != null) {
    final platform = parsed.platform!;
    final parts = [
      platform.name,
      if (platform.version != null) platform.version!,
      if (platform.architecture != null) '(${platform.architecture})',
    ];
    buffer.writeln('Platform: ${parts.join(' ')}');
  }
  if (parsed.device != null) {
    final device = parsed.device!;
    final parts = [
      device.type.name,
      if (device.model != null) device.model!,
      if (device.vendor != null) '(${device.vendor})',
    ];
    buffer.writeln('Device: ${parts.join(' ')}');
  }
  if (parsed.engine != null) {
    final engine = parsed.engine!;
    buffer.writeln(
      'Engine: ${engine.name}${engine.version != null ? " ${engine.version}" : ""}',
    );
  }
  if (parsed.issues.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Issues:');
    for (final issue in parsed.issues) {
      buffer.writeln(
        '  ${issue.severity.name.toUpperCase()}: ${issue.message}',
      );
    }
  }
  return buffer.toString().trimRight();
}

enum _UaBrowser {
  chrome('Chrome'),
  safari('Safari'),
  firefox('Firefox'),
  edge('Edge'),
  brave('Brave'),
  chromium('Chromium'),
  facebook('Facebook'),
  instagram('Instagram'),
  twitter('Twitter'),
  tiktok('TikTok'),
  linkedin('LinkedIn'),
  snapchat('Snapchat'),
  pinterest('Pinterest'),
  whatsapp('WhatsApp'),
  telegram('Telegram'),
  discord('Discord'),
  slack('Slack'),
  wechat('WeChat'),
  line('Line');

  const _UaBrowser(this.label);
  final String label;
}

enum _UaPlatform {
  macOS('macOS'),
  windows('Windows'),
  linux('Linux'),
  iOS('iOS'),
  android('Android');

  const _UaPlatform(this.label);
  final String label;
}

class _UaGenerator {
  static final Random _rand = Random();

  static const List<String> chromeVersions = [
    '120.0.6099.109',
    '121.0.6167.85',
    '122.0.6261.94',
    '123.0.6312.58',
    '124.0.6367.91',
    '125.0.6422.76',
    '126.0.6478.126',
    '127.0.6533.72',
    '128.0.6613.84',
    '129.0.6668.70',
    '130.0.6723.91',
    '131.0.6778.85',
  ];

  static const List<String> chromiumVersions = [
    '120.0.6099.0',
    '121.0.6167.0',
    '122.0.6261.0',
    '123.0.6312.0',
    '124.0.6367.0',
    '125.0.6422.0',
    '126.0.6478.0',
    '127.0.6533.0',
    '128.0.6613.0',
    '129.0.6668.0',
    '130.0.6723.0',
    '131.0.6778.0',
  ];

  static const List<String> braveVersions = [
    '1.60.125',
    '1.61.109',
    '1.62.153',
    '1.63.165',
    '1.64.109',
    '1.65.132',
    '1.66.110',
    '1.67.123',
    '1.68.134',
    '1.69.153',
    '1.70.117',
    '1.71.114',
  ];

  static const List<String> firefoxVersions = [
    '121.0',
    '122.0',
    '123.0',
    '124.0',
    '125.0',
    '126.0',
    '127.0',
    '128.0',
    '129.0',
    '130.0',
    '131.0',
    '132.0',
  ];

  static const List<String> safariVersions = [
    '17.0',
    '17.1',
    '17.2',
    '17.3',
    '17.4',
    '17.5',
    '17.6',
    '18.0',
    '18.1',
  ];

  static const List<String> edgeVersions = [
    '120.0.2210.91',
    '121.0.2277.83',
    '122.0.2365.66',
    '123.0.2420.65',
    '124.0.2478.67',
    '125.0.2535.51',
    '126.0.2592.68',
    '127.0.2651.74',
    '128.0.2739.42',
    '129.0.2792.52',
    '130.0.2849.56',
    '131.0.2903.63',
  ];

  static const List<String> facebookAppVersions = [
    '450.0.0.40.109',
    '451.0.0.41.110',
    '452.0.0.42.111',
    '453.0.0.43.112',
    '454.0.0.44.113',
  ];
  static const List<String> instagramAppVersions = [
    '312.0.0.34.111',
    '313.0.0.35.112',
    '314.0.0.36.113',
    '315.0.0.37.114',
    '316.0.0.38.115',
  ];
  static const List<String> twitterAppVersions = [
    '10.23.0',
    '10.24.0',
    '10.25.0',
    '10.26.0',
    '10.27.0',
    '10.28.0',
  ];
  static const List<String> tiktokAppVersions = [
    '32.5.3',
    '32.6.4',
    '32.7.5',
    '33.0.3',
    '33.1.4',
    '33.2.5',
  ];
  static const List<String> linkedinAppVersions = [
    '9.29.5421',
    '9.30.5432',
    '9.31.5443',
    '9.32.5454',
    '9.33.5465',
  ];
  static const List<String> snapchatAppVersions = [
    '12.75.0.38',
    '12.76.0.39',
    '12.77.0.40',
    '12.78.0.41',
    '12.79.0.42',
  ];
  static const List<String> pinterestAppVersions = [
    '11.38.0',
    '11.39.0',
    '11.40.0',
    '11.41.0',
    '11.42.0',
  ];
  static const List<String> whatsappAppVersions = [
    '2.24.2.76',
    '2.24.3.77',
    '2.24.4.78',
    '2.24.5.79',
    '2.24.6.80',
  ];
  static const List<String> telegramAppVersions = [
    '10.6.2',
    '10.7.3',
    '10.8.4',
    '10.9.5',
    '10.10.6',
  ];
  static const List<String> discordAppVersions = [
    '223.0',
    '224.0',
    '225.0',
    '226.0',
    '227.0',
  ];
  static const List<String> slackAppVersions = [
    '24.01.10',
    '24.02.11',
    '24.03.12',
    '24.04.13',
    '24.05.14',
  ];
  static const List<String> wechatAppVersions = [
    '8.0.43',
    '8.0.44',
    '8.0.45',
    '8.0.46',
    '8.0.47',
  ];
  static const List<String> lineAppVersions = [
    '14.0.1',
    '14.1.2',
    '14.2.3',
    '14.3.4',
    '14.4.5',
  ];

  static const List<_UaPair> macOSVersions = [
    _UaPair('10_15_7', '10.15.7'),
    _UaPair('11_7_10', '11.7.10'),
    _UaPair('12_7_6', '12.7.6'),
    _UaPair('13_6_9', '13.6.9'),
    _UaPair('14_6_1', '14.6.1'),
    _UaPair('15_1', '15.1'),
  ];

  static const List<_UaPair> windowsVersions = [
    _UaPair('10.0; Win64; x64', '10'),
    _UaPair('10.0; Win64; x64', '11'),
  ];

  static const List<String> iOSVersions = [
    '16_6',
    '17_0',
    '17_1',
    '17_2',
    '17_3',
    '17_4',
    '17_5',
    '17_6',
    '18_0',
    '18_1',
  ];

  static const List<String> androidVersions = ['11', '12', '13', '14', '15'];

  static const List<_UaPair> iPhoneModels = [
    _UaPair('iPhone13,2', 'iPhone 12'),
    _UaPair('iPhone13,3', 'iPhone 12 Pro'),
    _UaPair('iPhone13,4', 'iPhone 12 Pro Max'),
    _UaPair('iPhone14,5', 'iPhone 13'),
    _UaPair('iPhone14,2', 'iPhone 13 Pro'),
    _UaPair('iPhone14,3', 'iPhone 13 Pro Max'),
    _UaPair('iPhone14,7', 'iPhone 14'),
    _UaPair('iPhone14,8', 'iPhone 14 Plus'),
    _UaPair('iPhone15,2', 'iPhone 14 Pro'),
    _UaPair('iPhone15,3', 'iPhone 14 Pro Max'),
    _UaPair('iPhone15,4', 'iPhone 15'),
    _UaPair('iPhone15,5', 'iPhone 15 Plus'),
    _UaPair('iPhone16,1', 'iPhone 15 Pro'),
    _UaPair('iPhone16,2', 'iPhone 15 Pro Max'),
    _UaPair('iPhone17,1', 'iPhone 16'),
    _UaPair('iPhone17,2', 'iPhone 16 Plus'),
    _UaPair('iPhone17,3', 'iPhone 16 Pro'),
    _UaPair('iPhone17,4', 'iPhone 16 Pro Max'),
  ];

  static const List<_UaDevice> androidDevices = [
    _UaDevice('Samsung', 'SM-S911B', 'Galaxy S23'),
    _UaDevice('Samsung', 'SM-S918B', 'Galaxy S23 Ultra'),
    _UaDevice('Samsung', 'SM-S921B', 'Galaxy S24'),
    _UaDevice('Samsung', 'SM-S928B', 'Galaxy S24 Ultra'),
    _UaDevice('Samsung', 'SM-A546B', 'Galaxy A54'),
    _UaDevice('Samsung', 'SM-A556B', 'Galaxy A55'),
    _UaDevice('Google', 'Pixel 7', 'Pixel 7'),
    _UaDevice('Google', 'Pixel 7 Pro', 'Pixel 7 Pro'),
    _UaDevice('Google', 'Pixel 8', 'Pixel 8'),
    _UaDevice('Google', 'Pixel 8 Pro', 'Pixel 8 Pro'),
    _UaDevice('Google', 'Pixel 9', 'Pixel 9'),
    _UaDevice('Google', 'Pixel 9 Pro', 'Pixel 9 Pro'),
    _UaDevice('OnePlus', 'CPH2449', 'OnePlus 11'),
    _UaDevice('OnePlus', 'CPH2551', 'OnePlus 12'),
    _UaDevice('Xiaomi', '2312DRA50G', 'Xiaomi 14'),
    _UaDevice('Xiaomi', '2311DRK48G', 'Xiaomi 14 Pro'),
    _UaDevice('Oppo', 'CPH2551', 'Find X7'),
    _UaDevice('Huawei', 'ALN-AL00', 'Mate 60 Pro'),
  ];

  static const String webkitVersion = '537.36';
  static const String geckoVersion = '20100101';
  static const List<String> facebookBuildIds = [
    '477985655',
    '478012312',
    '478123456',
    '478234567',
    '478345678',
  ];

  static const List<String> browserLabels = [
    'Random',
    'Random Standard',
    'Random WebView',
    'Chrome',
    'Safari',
    'Firefox',
    'Edge',
    'Brave',
    'Chromium',
    'Facebook',
    'Instagram',
    'Twitter',
    'TikTok',
    'LinkedIn',
    'Snapchat',
    'Pinterest',
    'WhatsApp',
    'Telegram',
    'Discord',
    'Slack',
    'WeChat',
    'Line',
  ];

  static const List<String> platformLabels = [
    'Any',
    'macOS',
    'Windows',
    'Linux',
    'iOS',
    'Android',
  ];

  static String generateFromSelection(String selection, _UaPlatform? platform) {
    if (selection == 'Random') {
      return random();
    }
    if (selection == 'Random Standard') {
      return randomStandardBrowser();
    }
    if (selection == 'Random WebView') {
      return randomWebView();
    }
    final browser = _UaBrowser.values.firstWhere(
      (value) => value.label == selection,
    );
    return generate(browser: browser, platform: platform);
  }

  static String generate({
    required _UaBrowser browser,
    _UaPlatform? platform,
    String? version,
  }) {
    final _UaPlatform platformValue = platform ?? _pick(_UaPlatform.values);
    switch (browser) {
      case _UaBrowser.chrome:
        return _generateChrome(platformValue, version);
      case _UaBrowser.safari:
        return _generateSafari(platformValue, version);
      case _UaBrowser.firefox:
        return _generateFirefox(platformValue, version);
      case _UaBrowser.edge:
        return _generateEdge(platformValue, version);
      case _UaBrowser.brave:
        return _generateBrave(platformValue, version);
      case _UaBrowser.chromium:
        return _generateChromium(platformValue, version);
      case _UaBrowser.facebook:
        return _generateFacebook(platformValue, version);
      case _UaBrowser.instagram:
        return _generateInstagram(platformValue, version);
      case _UaBrowser.twitter:
        return _generateTwitter(platformValue, version);
      case _UaBrowser.tiktok:
        return _generateTikTok(platformValue, version);
      case _UaBrowser.linkedin:
        return _generateLinkedIn(platformValue, version);
      case _UaBrowser.snapchat:
        return _generateSnapchat(platformValue, version);
      case _UaBrowser.pinterest:
        return _generatePinterest(platformValue, version);
      case _UaBrowser.whatsapp:
        return _generateWhatsApp(platformValue, version);
      case _UaBrowser.telegram:
        return _generateTelegram(platformValue, version);
      case _UaBrowser.discord:
        return _generateDiscord(platformValue, version);
      case _UaBrowser.slack:
        return _generateSlack(platformValue, version);
      case _UaBrowser.wechat:
        return _generateWeChat(platformValue, version);
      case _UaBrowser.line:
        return _generateLine(platformValue, version);
    }
  }

  static String random() {
    return generate(
      browser: _pick(_UaBrowser.values),
      platform: _pick(_UaPlatform.values),
    );
  }

  static String randomStandardBrowser() {
    const standard = [
      _UaBrowser.chrome,
      _UaBrowser.safari,
      _UaBrowser.firefox,
      _UaBrowser.edge,
      _UaBrowser.brave,
      _UaBrowser.chromium,
    ];
    return generate(
      browser: _pick(standard),
      platform: _pick(_UaPlatform.values),
    );
  }

  static String randomWebView() {
    const webviews = [
      _UaBrowser.facebook,
      _UaBrowser.instagram,
      _UaBrowser.twitter,
      _UaBrowser.tiktok,
      _UaBrowser.linkedin,
      _UaBrowser.snapchat,
      _UaBrowser.pinterest,
      _UaBrowser.whatsapp,
      _UaBrowser.telegram,
      _UaBrowser.discord,
      _UaBrowser.slack,
      _UaBrowser.wechat,
      _UaBrowser.line,
    ];
    const platforms = [_UaPlatform.iOS, _UaPlatform.android];
    return generate(browser: _pick(webviews), platform: _pick(platforms));
  }

  static String _generateChrome(_UaPlatform platform, String? version) {
    final chromeVersion = version ?? _pick(chromeVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/$webkitVersion (KHTML, like Gecko) CriOS/$chromeVersion Mobile/15E148 Safari/$webkitVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Mobile Safari/$webkitVersion';
    }
  }

  static String _generateChromium(_UaPlatform platform, String? version) {
    final chromiumVersion = version ?? _pick(chromiumVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Safari/$webkitVersion';
      case _UaPlatform.iOS:
        return _generateChrome(_UaPlatform.iOS, version);
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chromium/$chromiumVersion Chrome/$chromiumVersion Mobile Safari/$webkitVersion';
    }
  }

  static String _generateBrave(_UaPlatform platform, String? version) {
    final braveVersion = version ?? _pick(braveVersions);
    final chromeVersion = _pick(chromeVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Brave/$braveVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Brave/$braveVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Brave/$braveVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final safariVersion = _pick(safariVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariVersion Mobile/15E148 Safari/604.1 Brave/$braveVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Mobile Safari/$webkitVersion Brave/$braveVersion';
    }
  }

  static String _generateSafari(_UaPlatform platform, String? version) {
    final safariVersion = version ?? _pick(safariVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariVersion Safari/605.1.15';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariVersion Mobile/15E148 Safari/604.1';
      case _UaPlatform.windows:
      case _UaPlatform.linux:
      case _UaPlatform.android:
        return _generateSafari(_UaPlatform.macOS, version);
    }
  }

  static String _generateFirefox(_UaPlatform platform, String? version) {
    final firefoxVersion = version ?? _pick(firefoxVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer; rv:$firefoxVersion) Gecko/$geckoVersion Firefox/$firefoxVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer; rv:$firefoxVersion) Gecko/$geckoVersion Firefox/$firefoxVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64; rv:$firefoxVersion) Gecko/$geckoVersion Firefox/$firefoxVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/$firefoxVersion Mobile/15E148 Safari/605.1.15';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        return 'Mozilla/5.0 (Android $androidVer; Mobile; rv:$firefoxVersion) Gecko/$firefoxVersion Firefox/$firefoxVersion';
    }
  }

  static String _generateEdge(_UaPlatform platform, String? version) {
    final edgeVersion = version ?? _pick(edgeVersions);
    final chromeVersion = _pick(chromeVersions);
    switch (platform) {
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Edg/$edgeVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Edg/$edgeVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Safari/$webkitVersion Edg/$edgeVersion';
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final safariVersion = _pick(safariVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/$safariVersion EdgiOS/$edgeVersion Mobile/15E148 Safari/$webkitVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device) AppleWebKit/$webkitVersion (KHTML, like Gecko) Chrome/$chromeVersion Mobile Safari/$webkitVersion EdgA/$edgeVersion';
    }
  }

  static String _generateFacebook(_UaPlatform platform, String? version) {
    final fbVersion = version ?? _pick(facebookAppVersions);
    final buildId = _pick(facebookBuildIds);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final deviceId = _pick(iPhoneModels).key;
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/$fbVersion;FBBV/$buildId;FBDV/$deviceId;FBMD/iPhone;FBSN/iOS;FBSV/${iosVer.replaceAll("_", ".")};FBSS/3;FBID/phone;FBLC/en_US;FBOP/5]';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices);
        final dpi = _pick(['240', '320', '480', '640']);
        return 'Mozilla/5.0 (Linux; Android $androidVer; ${device.model} Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion [FB_IAB/FB4A;FBAV/$fbVersion;FBBV/$buildId;FBDM/{density=$dpi.0,width=1080,height=2340};FBLC/en_US;FBRV/$buildId;FBCR/;FBMF/${device.vendor};FBBD/${device.vendor};FBPN/com.facebook.katana;FBDV/${device.model};FBSV/$androidVer;FBOP/1;FBCA/armeabi-v7a:armeabi;]';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateFacebook(_UaPlatform.iOS, version);
    }
  }

  static String _generateInstagram(_UaPlatform platform, String? version) {
    final igVersion = version ?? _pick(instagramAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram $igVersion (iPhone; iOS ${iosVer.replaceAll("_", ".")}); en_US; en-US; scale=3.00; 1170x2532; ${_pick(facebookBuildIds)})';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices);
        return 'Mozilla/5.0 (Linux; Android $androidVer; ${device.model} Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Instagram $igVersion Android ($androidVer/${device.model}; 480dpi; 1080x2340; ${device.vendor}; ${device.model}; ${device.model.toLowerCase()}; qcom; en_US; ${_pick(facebookBuildIds)})';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateInstagram(_UaPlatform.iOS, version);
    }
  }

  static String _generateTwitter(_UaPlatform platform, String? version) {
    final twitterVersion = version ?? _pick(twitterAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Twitter for iPhone/$twitterVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Twitter for Android/$twitterVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateTwitter(_UaPlatform.iOS, version);
    }
  }

  static String _generateTikTok(_UaPlatform platform, String? version) {
    final tiktokVersion = version ?? _pick(tiktokAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        final deviceId = _pick(iPhoneModels).key;
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 BytedanceWebview/d8a21c6 musical_ly_$tiktokVersion JsSdk/1.0 NetType/WIFI Channel/App Store ByteLocale/en Region/US FalconTag/$deviceId';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices);
        return 'Mozilla/5.0 (Linux; Android $androidVer; ${device.model} Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion trill/$tiktokVersion BytedanceWebview/d8a21c6 JsSdk/1.0 NetType/wifi Channel/googleplay AppName/musical_ly app_version/$tiktokVersion ByteLocale/en Region/US';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateTikTok(_UaPlatform.iOS, version);
    }
  }

  static String _generateLinkedIn(_UaPlatform platform, String? version) {
    final linkedinVersion = version ?? _pick(linkedinAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [LinkedInApp]/$linkedinVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion [LinkedInApp]/$linkedinVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateLinkedIn(_UaPlatform.iOS, version);
    }
  }

  static String _generateSnapchat(_UaPlatform platform, String? version) {
    final snapVersion = version ?? _pick(snapchatAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Snapchat/$snapVersion (iPhone; iOS ${iosVer.replaceAll("_", ".")}; Scale/3.00)';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Snapchat/$snapVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateSnapchat(_UaPlatform.iOS, version);
    }
  }

  static String _generatePinterest(_UaPlatform platform, String? version) {
    final pinterestVersion = version ?? _pick(pinterestAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [Pinterest/iOS $pinterestVersion]';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion [Pinterest/Android $pinterestVersion]';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generatePinterest(_UaPlatform.iOS, version);
    }
  }

  static String _generateWhatsApp(_UaPlatform platform, String? version) {
    final waVersion = version ?? _pick(whatsappAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 WhatsApp/$waVersion w';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion WhatsApp/$waVersion a';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateWhatsApp(_UaPlatform.iOS, version);
    }
  }

  static String _generateTelegram(_UaPlatform platform, String? version) {
    final tgVersion = version ?? _pick(telegramAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Telegram-iOS/$tgVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion TelegramAndroid/$tgVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateTelegram(_UaPlatform.iOS, version);
    }
  }

  static String _generateDiscord(_UaPlatform platform, String? version) {
    final discordVersion = version ?? _pick(discordAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Discord/$discordVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion discord/$discordVersion';
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) discord/$discordVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) discord/$discordVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) discord/$discordVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
    }
  }

  static String _generateSlack(_UaPlatform platform, String? version) {
    final slackVersion = version ?? _pick(slackAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Slack/$slackVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Slack/$slackVersion';
      case _UaPlatform.macOS:
        final macVer = _pick(macOSVersions).key;
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X $macVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Slack/$slackVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.windows:
        final winVer = _pick(windowsVersions).key;
        return 'Mozilla/5.0 (Windows NT $winVer) AppleWebKit/$webkitVersion (KHTML, like Gecko) Slack/$slackVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
      case _UaPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/$webkitVersion (KHTML, like Gecko) Slack/$slackVersion Chrome/${_pick(chromeVersions)} Electron/28.1.0 Safari/$webkitVersion';
    }
  }

  static String _generateWeChat(_UaPlatform platform, String? version) {
    final wechatVersion = version ?? _pick(wechatAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/$wechatVersion NetType/WIFI Language/en';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion MicroMessenger/$wechatVersion NetType/WIFI Language/en';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateWeChat(_UaPlatform.iOS, version);
    }
  }

  static String _generateLine(_UaPlatform platform, String? version) {
    final lineVersion = version ?? _pick(lineAppVersions);
    switch (platform) {
      case _UaPlatform.iOS:
        final iosVer = _pick(iOSVersions);
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari Line/$lineVersion';
      case _UaPlatform.android:
        final androidVer = _pick(androidVersions);
        final device = _pick(androidDevices).model;
        return 'Mozilla/5.0 (Linux; Android $androidVer; $device Build/UP1A.231005.007; wv) AppleWebKit/$webkitVersion (KHTML, like Gecko) Version/4.0 Chrome/${_pick(chromeVersions)} Mobile Safari/$webkitVersion Line/$lineVersion';
      case _UaPlatform.macOS:
      case _UaPlatform.windows:
      case _UaPlatform.linux:
        return _generateLine(_UaPlatform.iOS, version);
    }
  }

  static T _pick<T>(List<T> items) => items[_rand.nextInt(items.length)];
}

class _UaPair {
  const _UaPair(this.key, this.value);
  final String key;
  final String value;
}

class _UaDevice {
  const _UaDevice(this.vendor, this.model, this.name);
  final String vendor;
  final String model;
  final String name;
}

class _UaValidationResult {
  const _UaValidationResult({
    required this.isValid,
    required this.parsed,
    required this.score,
    required this.summary,
  });

  final bool isValid;
  final _UaParsedUserAgent parsed;
  final int score;
  final String summary;
}

class _UaParsedUserAgent {
  const _UaParsedUserAgent({
    required this.raw,
    required this.browser,
    required this.platform,
    required this.device,
    required this.engine,
    required this.webView,
    required this.isBot,
    required this.botName,
    required this.isValid,
    required this.issues,
    required this.confidence,
  });

  final String raw;
  final _UaBrowserInfo? browser;
  final _UaPlatformInfo? platform;
  final _UaDeviceInfo? device;
  final _UaEngineInfo? engine;
  final _UaWebViewInfo? webView;
  final bool isBot;
  final String? botName;
  final bool isValid;
  final List<_UaValidationIssue> issues;
  final double confidence;
}

class _UaBrowserInfo {
  const _UaBrowserInfo({
    required this.name,
    required this.version,
    required this.majorVersion,
    required this.isWebView,
  });

  final String name;
  final String version;
  final int? majorVersion;
  final bool isWebView;
}

class _UaPlatformInfo {
  const _UaPlatformInfo({
    required this.name,
    required this.version,
    required this.architecture,
  });

  final String name;
  final String? version;
  final String? architecture;
}

class _UaDeviceInfo {
  const _UaDeviceInfo({
    required this.type,
    required this.model,
    required this.vendor,
  });

  final _UaDeviceType type;
  final String? model;
  final String? vendor;
}

class _UaEngineInfo {
  const _UaEngineInfo({required this.name, required this.version});
  final String name;
  final String? version;
}

class _UaWebViewInfo {
  const _UaWebViewInfo({
    required this.app,
    required this.appVersion,
    required this.buildId,
    required this.additionalInfo,
  });

  final String app;
  final String? appVersion;
  final String? buildId;
  final Map<String, String> additionalInfo;
}

enum _UaDeviceType { desktop, mobile, tablet, tv, bot, unknown }

class _UaValidationIssue {
  const _UaValidationIssue({
    required this.severity,
    required this.message,
    required this.field,
  });

  final _UaIssueSeverity severity;
  final String message;
  final String? field;
}

enum _UaIssueSeverity { error, warning, info }

class _UaRange {
  const _UaRange(this.min, this.max);
  final int min;
  final int max;
  bool contains(int value) => value >= min && value <= max;
}

class _UaValidator {
  static const List<_UaBotPattern> botPatterns = [
    _UaBotPattern('googlebot', 'Googlebot'),
    _UaBotPattern('bingbot', 'Bingbot'),
    _UaBotPattern('slurp', 'Yahoo Slurp'),
    _UaBotPattern('duckduckbot', 'DuckDuckBot'),
    _UaBotPattern('baiduspider', 'Baiduspider'),
    _UaBotPattern('yandexbot', 'YandexBot'),
    _UaBotPattern('facebookexternalhit', 'Facebook Bot'),
    _UaBotPattern('twitterbot', 'Twitter Bot'),
    _UaBotPattern('linkedinbot', 'LinkedIn Bot'),
    _UaBotPattern('applebot', 'Applebot'),
    _UaBotPattern('semrushbot', 'SEMrush Bot'),
    _UaBotPattern('ahrefsbot', 'Ahrefs Bot'),
    _UaBotPattern('mj12bot', 'Majestic Bot'),
    _UaBotPattern('dotbot', 'Moz Bot'),
    _UaBotPattern('rogerbot', 'Moz Bot'),
    _UaBotPattern('screaming frog', 'Screaming Frog'),
    _UaBotPattern('crawler', 'Generic Crawler'),
    _UaBotPattern('spider', 'Generic Spider'),
    _UaBotPattern('scraper', 'Scraper'),
    _UaBotPattern('headless', 'Headless Browser'),
    _UaBotPattern('phantom', 'PhantomJS'),
    _UaBotPattern('selenium', 'Selenium'),
    _UaBotPattern('puppeteer', 'Puppeteer'),
    _UaBotPattern('playwright', 'Playwright'),
    _UaBotPattern('wget', 'Wget'),
    _UaBotPattern('curl', 'cURL'),
    _UaBotPattern('python-requests', 'Python Requests'),
    _UaBotPattern('python-urllib', 'Python urllib'),
    _UaBotPattern('java/', 'Java Client'),
    _UaBotPattern('libwww', 'libwww'),
    _UaBotPattern('httpclient', 'HTTP Client'),
    _UaBotPattern('okhttp', 'OkHttp'),
    _UaBotPattern('axios', 'Axios'),
    _UaBotPattern('node-fetch', 'Node Fetch'),
    _UaBotPattern('go-http-client', 'Go HTTP Client'),
    _UaBotPattern('guzzle', 'Guzzle'),
  ];

  static const List<_UaBrowserPattern> browserPatterns = [
    _UaBrowserPattern('[fban/fbios', 'Facebook iOS', 'FBAV/([\\d.]+)', true),
    _UaBrowserPattern(
      '[fb_iab/fb4a',
      'Facebook Android',
      'FBAV/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('instagram', 'Instagram', 'Instagram ([\\d.]+)', true),
    _UaBrowserPattern(
      'twitter for iphone',
      'Twitter iOS',
      'Twitter for iPhone/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern(
      'twitter for android',
      'Twitter Android',
      'Twitter for Android/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern(
      'bytedancewebview',
      'TikTok',
      'musical_ly[_/]([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('trill/', 'TikTok', 'trill/([\\d.]+)', true),
    _UaBrowserPattern(
      '[linkedinapp]',
      'LinkedIn',
      '\\[LinkedInApp\\]/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('snapchat/', 'Snapchat', 'Snapchat/([\\d.]+)', true),
    _UaBrowserPattern('[pinterest', 'Pinterest', 'Pinterest', true),
    _UaBrowserPattern('whatsapp/', 'WhatsApp', 'WhatsApp/([\\d.]+)', true),
    _UaBrowserPattern(
      'telegram-ios',
      'Telegram iOS',
      'Telegram-iOS/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern(
      'telegramandroid',
      'Telegram Android',
      'TelegramAndroid/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('discord/', 'Discord', 'discord/([\\d.]+)', true),
    _UaBrowserPattern('slack/', 'Slack', 'Slack/([\\d.]+)', true),
    _UaBrowserPattern(
      'micromessenger/',
      'WeChat',
      'MicroMessenger/([\\d.]+)',
      true,
    ),
    _UaBrowserPattern('line/', 'Line', 'Line/([\\d.]+)', true),
    _UaBrowserPattern('edg/', 'Edge', 'Edg/([\\d.]+)', false),
    _UaBrowserPattern('edga/', 'Edge Android', 'EdgA/([\\d.]+)', false),
    _UaBrowserPattern('edgios/', 'Edge iOS', 'EdgiOS/([\\d.]+)', false),
    _UaBrowserPattern('opr/', 'Opera', 'OPR/([\\d.]+)', false),
    _UaBrowserPattern('opera', 'Opera', 'Opera[/ ]([\\d.]+)', false),
    _UaBrowserPattern('vivaldi/', 'Vivaldi', 'Vivaldi/([\\d.]+)', false),
    _UaBrowserPattern(
      'yabrowser/',
      'Yandex Browser',
      'YaBrowser/([\\d.]+)',
      false,
    ),
    _UaBrowserPattern('brave/', 'Brave', 'Brave/([\\d.]+)', false),
    _UaBrowserPattern('chromium/', 'Chromium', 'Chromium/([\\d.]+)', false),
    _UaBrowserPattern(
      'samsungbrowser/',
      'Samsung Browser',
      'SamsungBrowser/([\\d.]+)',
      false,
    ),
    _UaBrowserPattern('ucbrowser/', 'UC Browser', 'UCBrowser/([\\d.]+)', false),
    _UaBrowserPattern('crios/', 'Chrome iOS', 'CriOS/([\\d.]+)', false),
    _UaBrowserPattern('fxios/', 'Firefox iOS', 'FxiOS/([\\d.]+)', false),
    _UaBrowserPattern('firefox/', 'Firefox', 'Firefox/([\\d.]+)', false),
    _UaBrowserPattern('chrome/', 'Chrome', 'Chrome/([\\d.]+)', false),
    _UaBrowserPattern('safari/', 'Safari', 'Version/([\\d.]+)', false),
  ];

  static const Map<String, _UaRange> validVersionRanges = {
    'Chrome': _UaRange(70, 140),
    'Chrome iOS': _UaRange(70, 140),
    'Chromium': _UaRange(70, 140),
    'Firefox': _UaRange(70, 140),
    'Firefox iOS': _UaRange(70, 140),
    'Safari': _UaRange(12, 19),
    'Edge': _UaRange(80, 140),
    'Edge Android': _UaRange(80, 140),
    'Edge iOS': _UaRange(80, 140),
    'Opera': _UaRange(60, 115),
    'Brave': _UaRange(1, 2),
    'Vivaldi': _UaRange(5, 7),
    'Samsung Browser': _UaRange(18, 27),
    'UC Browser': _UaRange(13, 16),
    'Yandex Browser': _UaRange(23, 25),
  };

  static const Map<String, _UaRange> validWebViewRanges = {
    'Facebook iOS': _UaRange(400, 500),
    'Facebook Android': _UaRange(400, 500),
    'Instagram': _UaRange(280, 350),
    'Twitter iOS': _UaRange(9, 12),
    'Twitter Android': _UaRange(9, 12),
    'TikTok': _UaRange(28, 40),
    'WhatsApp': _UaRange(2, 3),
    'WeChat': _UaRange(8, 9),
    'Telegram iOS': _UaRange(9, 12),
    'Telegram Android': _UaRange(9, 12),
    'Discord': _UaRange(200, 250),
    'Slack': _UaRange(23, 26),
    'Snapchat': _UaRange(12, 14),
    'Line': _UaRange(13, 16),
  };

  static _UaValidationResult validate(String userAgent) {
    final parsed = parse(userAgent);
    final score = _calculateScore(parsed);
    final isValid = parsed.isValid && score.score >= 50;
    return _UaValidationResult(
      isValid: isValid,
      parsed: parsed,
      score: score.score,
      summary: score.summary,
    );
  }

  static _UaParsedUserAgent parse(String userAgent) {
    final ua = userAgent.trim();
    final issues = <_UaValidationIssue>[];

    if (ua.isEmpty) {
      return _UaParsedUserAgent(
        raw: ua,
        browser: null,
        platform: null,
        device: null,
        engine: null,
        webView: null,
        isBot: false,
        botName: null,
        isValid: false,
        issues: [
          const _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message: 'Empty user agent',
            field: null,
          ),
        ],
        confidence: 0,
      );
    }

    if (!ua.startsWith('Mozilla/') &&
        !_isKnownBot(ua) &&
        !_isKnownWebView(ua)) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Non-standard format: does not start with Mozilla/',
          field: 'format',
        ),
      );
    }

    final bot = _detectBot(ua);
    final browser = _parseBrowser(ua);
    if (browser == null && !bot.isBot) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Could not identify browser',
          field: 'browser',
        ),
      );
    }

    _UaWebViewInfo? webView;
    if (browser != null && browser.isWebView) {
      webView = _parseWebView(ua, browser.name);
    }

    if (browser != null && browser.majorVersion != null) {
      final major = browser.majorVersion!;
      if (browser.isWebView) {
        final range = validWebViewRanges[browser.name];
        if (range != null && !range.contains(major)) {
          issues.add(
            _UaValidationIssue(
              severity: major < range.min
                  ? _UaIssueSeverity.warning
                  : _UaIssueSeverity.info,
              message:
                  '${browser.name} version $major is outside expected range ${range.min}-${range.max}',
              field: 'browserVersion',
            ),
          );
        }
      } else {
        final range = validVersionRanges[browser.name];
        if (range != null && !range.contains(major)) {
          issues.add(
            _UaValidationIssue(
              severity: major < range.min
                  ? _UaIssueSeverity.warning
                  : _UaIssueSeverity.info,
              message:
                  '${browser.name} version $major is outside expected range ${range.min}-${range.max}',
              field: 'browserVersion',
            ),
          );
        }
      }
    }

    final platform = _parsePlatform(ua);
    if (platform == null && !bot.isBot) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Could not identify platform/OS',
          field: 'platform',
        ),
      );
    }

    final device = _parseDevice(
      ua,
      isBot: bot.isBot,
      isWebView: browser?.isWebView ?? false,
    );
    final engine = _parseEngine(ua);
    issues.addAll(
      _validateCombinations(browser, platform, engine, webView, ua),
    );
    issues.addAll(_checkSuspiciousPatterns(ua));

    final confidence = _calculateConfidence(
      browser,
      platform,
      engine,
      webView,
      issues,
      bot.isBot,
    );
    final hasErrors = issues.any(
      (issue) => issue.severity == _UaIssueSeverity.error,
    );
    final isValid =
        !hasErrors && (browser != null || bot.isBot) && confidence > 0.3;

    return _UaParsedUserAgent(
      raw: ua,
      browser: browser,
      platform: platform,
      device: device,
      engine: engine,
      webView: webView,
      isBot: bot.isBot,
      botName: bot.name,
      isValid: isValid,
      issues: issues,
      confidence: confidence,
    );
  }

  static bool _isKnownWebView(String ua) {
    final lower = ua.toLowerCase();
    const indicators = [
      '[fban/',
      '[fb_iab/',
      'instagram',
      'twitter for',
      'bytedancewebview',
      'trill/',
      '[linkedinapp]',
      'snapchat/',
      '[pinterest',
      'whatsapp/',
      'telegram-ios',
      'telegramandroid',
      'discord/',
      'slack/',
      'micromessenger/',
      'line/',
    ];
    return indicators.any(lower.contains);
  }

  static bool _isKnownBot(String ua) => _detectBot(ua).isBot;

  static _UaBotResult _detectBot(String ua) {
    final lower = ua.toLowerCase();
    if (_isKnownWebView(ua)) {
      return const _UaBotResult(false, null);
    }
    for (final pattern in botPatterns) {
      if (lower.contains(pattern.pattern)) {
        return _UaBotResult(true, pattern.name);
      }
    }
    return const _UaBotResult(false, null);
  }

  static _UaBrowserInfo? _parseBrowser(String ua) {
    final lower = ua.toLowerCase();
    for (final pattern in browserPatterns) {
      if (lower.contains(pattern.pattern)) {
        final version = _extractVersion(ua, pattern.versionPattern);
        final major = version != null
            ? int.tryParse(version.split('.').first)
            : null;
        return _UaBrowserInfo(
          name: pattern.name,
          version: version ?? 'unknown',
          majorVersion: major,
          isWebView: pattern.isWebView,
        );
      }
    }
    return null;
  }

  static _UaWebViewInfo? _parseWebView(String ua, String appName) {
    final base = appName.replaceAll(' iOS', '').replaceAll(' Android', '');
    String? appVersion;
    String? buildId;
    final additional = <String, String>{};

    const patterns = [
      _UaWebViewPattern('Facebook', [
        _UaKeyPattern('appVersion', 'FBAV/([\\d.]+)'),
        _UaKeyPattern('buildId', 'FBBV/([\\d]+)'),
        _UaKeyPattern('device', 'FBDV/([^;\\]]+)'),
        _UaKeyPattern('osVersion', 'FBSV/([\\d.]+)'),
        _UaKeyPattern('locale', 'FBLC/([^;\\]]+)'),
      ]),
      _UaWebViewPattern('Instagram', [
        _UaKeyPattern('appVersion', 'Instagram ([\\d.]+)'),
        _UaKeyPattern('scale', 'scale=([\\d.]+)'),
        _UaKeyPattern('resolution', '(\\d+x\\d+)'),
      ]),
      _UaWebViewPattern('TikTok', [
        _UaKeyPattern('appVersion', '(?:musical_ly[_/]|trill/)([\\d.]+)'),
        _UaKeyPattern('channel', 'Channel/([^\\s]+)'),
        _UaKeyPattern('region', 'Region/([A-Z]+)'),
        _UaKeyPattern('locale', 'ByteLocale/([a-z]+)'),
      ]),
      _UaWebViewPattern('WhatsApp', [
        _UaKeyPattern('appVersion', 'WhatsApp/([\\d.]+)'),
        _UaKeyPattern('platform', 'WhatsApp/[\\d.]+ ([wa])'),
      ]),
      _UaWebViewPattern('WeChat', [
        _UaKeyPattern('appVersion', 'MicroMessenger/([\\d.]+)'),
        _UaKeyPattern('netType', 'NetType/([^\\s]+)'),
        _UaKeyPattern('language', 'Language/([a-z]+)'),
      ]),
      _UaWebViewPattern('Telegram', [
        _UaKeyPattern('appVersion', 'Telegram(?:-iOS|Android)/([\\d.]+)'),
      ]),
      _UaWebViewPattern('Discord', [
        _UaKeyPattern('appVersion', 'discord/([\\d.]+)'),
        _UaKeyPattern('electronVersion', 'Electron/([\\d.]+)'),
      ]),
      _UaWebViewPattern('Slack', [
        _UaKeyPattern('appVersion', 'Slack/([\\d.]+)'),
        _UaKeyPattern('electronVersion', 'Electron/([\\d.]+)'),
      ]),
    ];

    for (final pattern in patterns) {
      if (base.contains(pattern.app) || pattern.app.contains(base)) {
        for (final pair in pattern.patterns) {
          final value = _extractVersion(ua, pair.regex);
          if (value == null) continue;
          switch (pair.key) {
            case 'appVersion':
              appVersion = value;
              break;
            case 'buildId':
              buildId = value;
              break;
            default:
              additional[pair.key] = value;
          }
        }
        break;
      }
    }

    if (base.contains('Facebook')) {
      appVersion ??= _extractVersion(ua, 'FBAV/([\\d.]+)');
      buildId ??= _extractVersion(ua, 'FBBV/([\\d]+)');
      additional['device'] ??= _extractVersion(ua, 'FBDV/([^;\\]]+)') ?? '';
      additional['osVersion'] ??= _extractVersion(ua, 'FBSV/([\\d.]+)') ?? '';
      additional['locale'] ??= _extractVersion(ua, 'FBLC/([^;\\]]+)') ?? '';
    }

    if (appVersion == null && buildId == null && additional.isEmpty) {
      return null;
    }
    additional.removeWhere((key, value) => value.isEmpty);
    return _UaWebViewInfo(
      app: base,
      appVersion: appVersion,
      buildId: buildId,
      additionalInfo: additional,
    );
  }

  static _UaPlatformInfo? _parsePlatform(String ua) {
    final lower = ua.toLowerCase();
    if (lower.contains('macintosh') || lower.contains('mac os x')) {
      final version = _extractVersion(
        ua,
        'Mac OS X ([\\d_\\.]+)',
      )?.replaceAll('_', '.');
      final arch = ua.contains('Intel') ? 'x86_64' : 'arm64';
      return _UaPlatformInfo(
        name: 'macOS',
        version: version,
        architecture: arch,
      );
    }
    if (lower.contains('iphone') ||
        lower.contains('ipad') ||
        lower.contains('ipod')) {
      final version = _extractVersion(
        ua,
        '(?:CPU (?:iPhone )?OS |FBSV/)([\\d_\\.]+)',
      )?.replaceAll('_', '.');
      return _UaPlatformInfo(
        name: 'iOS',
        version: version,
        architecture: 'arm64',
      );
    }
    if (lower.contains('android')) {
      final version = _extractVersion(ua, 'Android ([\\d\\.]+)');
      return _UaPlatformInfo(
        name: 'Android',
        version: version,
        architecture: null,
      );
    }
    if (lower.contains('windows')) {
      String? version;
      if (lower.contains('windows nt 10')) {
        version = '10/11';
      } else if (lower.contains('windows nt 6.3')) {
        version = '8.1';
      } else if (lower.contains('windows nt 6.2')) {
        version = '8';
      } else if (lower.contains('windows nt 6.1')) {
        version = '7';
      }
      final arch = lower.contains('win64') || lower.contains('x64')
          ? 'x86_64'
          : 'x86';
      return _UaPlatformInfo(
        name: 'Windows',
        version: version,
        architecture: arch,
      );
    }
    if (lower.contains('linux') && !lower.contains('android')) {
      final arch = lower.contains('x86_64')
          ? 'x86_64'
          : (lower.contains('aarch64') ? 'arm64' : null);
      return _UaPlatformInfo(name: 'Linux', version: null, architecture: arch);
    }
    if (lower.contains('cros')) {
      return _UaPlatformInfo(
        name: 'Chrome OS',
        version: null,
        architecture: null,
      );
    }
    return null;
  }

  static _UaDeviceInfo? _parseDevice(
    String ua, {
    required bool isBot,
    required bool isWebView,
  }) {
    if (isBot) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.bot,
        model: null,
        vendor: null,
      );
    }
    final lower = ua.toLowerCase();
    if (lower.contains('iphone')) {
      final model = _extractVersion(ua, 'FBDV/([^;\\]]+)') ?? 'iPhone';
      return _UaDeviceInfo(
        type: _UaDeviceType.mobile,
        model: model,
        vendor: 'Apple',
      );
    }
    if (lower.contains('ipad')) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.tablet,
        model: 'iPad',
        vendor: 'Apple',
      );
    }
    if (lower.contains('android')) {
      String? model;
      String? vendor;
      final extracted = _extractVersion(ua, 'Android[^;]*;\\s*([^)]+)');
      if (extracted != null) {
        final cleaned = extracted.split(' Build').first.trim();
        model = cleaned;
        vendor = _detectVendor(cleaned);
      }
      final isTablet =
          lower.contains('tablet') ||
          (lower.contains('android') && !lower.contains('mobile'));
      return _UaDeviceInfo(
        type: isTablet ? _UaDeviceType.tablet : _UaDeviceType.mobile,
        model: model,
        vendor: vendor,
      );
    }
    if (lower.contains('smart-tv') ||
        lower.contains('smarttv') ||
        lower.contains('webos') ||
        lower.contains('tizen')) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.tv,
        model: null,
        vendor: null,
      );
    }
    if (lower.contains('windows') ||
        lower.contains('macintosh') ||
        (lower.contains('linux') && !lower.contains('android'))) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.desktop,
        model: null,
        vendor: null,
      );
    }
    if (isWebView) {
      return const _UaDeviceInfo(
        type: _UaDeviceType.mobile,
        model: null,
        vendor: null,
      );
    }
    return const _UaDeviceInfo(
      type: _UaDeviceType.unknown,
      model: null,
      vendor: null,
    );
  }

  static String? _detectVendor(String model) {
    final lower = model.toLowerCase();
    if (lower.startsWith('sm-') || lower.contains('samsung')) return 'Samsung';
    if (lower.startsWith('pixel')) return 'Google';
    if (lower.contains('oneplus') || lower.startsWith('cph')) return 'OnePlus';
    if (lower.contains('xiaomi') ||
        (lower.startsWith('m') && lower.contains('pro'))) {
      return 'Xiaomi';
    }
    if (lower.contains('huawei') || lower.startsWith('aln-')) return 'Huawei';
    if (lower.contains('oppo')) return 'Oppo';
    if (lower.contains('vivo')) return 'Vivo';
    if (lower.contains('lg')) return 'LG';
    if (lower.contains('sony')) return 'Sony';
    if (lower.contains('nokia')) return 'Nokia';
    if (lower.contains('motorola') || lower.startsWith('moto')) {
      return 'Motorola';
    }
    return null;
  }

  static _UaEngineInfo? _parseEngine(String ua) {
    final lower = ua.toLowerCase();
    if (lower.contains('gecko/') &&
        lower.contains('firefox') &&
        !lower.contains('like gecko')) {
      final version = _extractVersion(ua, 'rv:([\\d\\.]+)');
      return _UaEngineInfo(name: 'Gecko', version: version);
    }
    if (lower.contains('applewebkit/')) {
      final version = _extractVersion(ua, 'AppleWebKit/([\\d\\.]+)');
      return _UaEngineInfo(name: 'WebKit', version: version);
    }
    if (lower.contains('trident/')) {
      final version = _extractVersion(ua, 'Trident/([\\d\\.]+)');
      return _UaEngineInfo(name: 'Trident', version: version);
    }
    if (lower.contains('presto/')) {
      final version = _extractVersion(ua, 'Presto/([\\d\\.]+)');
      return _UaEngineInfo(name: 'Presto', version: version);
    }
    return null;
  }

  static String? _extractVersion(String ua, String pattern) {
    final regex = RegExp(pattern, caseSensitive: false);
    final match = regex.firstMatch(ua);
    if (match == null || match.groupCount < 1) {
      return null;
    }
    return match.group(1);
  }

  static List<_UaValidationIssue> _validateCombinations(
    _UaBrowserInfo? browser,
    _UaPlatformInfo? platform,
    _UaEngineInfo? engine,
    _UaWebViewInfo? webView,
    String ua,
  ) {
    final issues = <_UaValidationIssue>[];
    if (browser == null) {
      return issues;
    }
    if (browser.isWebView) {
      const mobileOnly = [
        'Facebook iOS',
        'Facebook Android',
        'Instagram',
        'Twitter iOS',
        'Twitter Android',
        'TikTok',
        'Snapchat',
        'WhatsApp',
        'WeChat',
        'Line',
        'LinkedIn',
        'Pinterest',
        'Telegram iOS',
        'Telegram Android',
      ];
      if (mobileOnly.contains(browser.name) &&
          platform != null &&
          platform.name != 'iOS' &&
          platform.name != 'Android') {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message: '${browser.name} WebView is only available on iOS/Android',
            field: 'browser-platform',
          ),
        );
      }
      if (browser.name.contains('iOS') &&
          platform != null &&
          platform.name != 'iOS') {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message:
                '${browser.name} indicates iOS but platform is ${platform.name}',
            field: 'browser-platform',
          ),
        );
      }
      if (browser.name.contains('Android') &&
          platform != null &&
          platform.name != 'Android') {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.error,
            message:
                '${browser.name} indicates Android but platform is ${platform.name}',
            field: 'browser-platform',
          ),
        );
      }
      return issues;
    }
    if (platform == null) {
      return issues;
    }
    if (browser.name == 'Safari' &&
        platform.name != 'macOS' &&
        platform.name != 'iOS') {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Safari is only available on macOS and iOS',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Chromium' && platform.name == 'iOS') {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Chromium is not available on iOS',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Edge iOS' && platform.name != 'iOS') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Edge iOS identifier found but platform is ${platform.name}',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Edge Android' && platform.name != 'Android') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message:
              'Edge Android identifier found but platform is ${platform.name}',
          field: 'browser-platform',
        ),
      );
    }
    if (browser.name == 'Firefox' &&
        platform.name != 'iOS' &&
        engine != null &&
        engine.name != 'Gecko') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'Firefox should use Gecko engine',
          field: 'browser-engine',
        ),
      );
    }
    const blinkBrowsers = [
      'Chrome',
      'Edge',
      'Chromium',
      'Brave',
      'Opera',
      'Vivaldi',
    ];
    if (blinkBrowsers.contains(browser.name) &&
        platform.name != 'iOS' &&
        engine != null &&
        engine.name != 'WebKit') {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: '${browser.name} should use WebKit/Blink engine',
          field: 'browser-engine',
        ),
      );
    }
    if (platform.name == 'iOS' && engine != null && engine.name != 'WebKit') {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'All iOS browsers must use WebKit engine',
          field: 'engine',
        ),
      );
    }
    return issues;
  }

  static List<_UaValidationIssue> _checkSuspiciousPatterns(String ua) {
    final issues = <_UaValidationIssue>[];
    if (ua.length < 20) {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'User agent is suspiciously short (${ua.length} characters)',
          field: 'length',
        ),
      );
    }
    if (ua.length > 600 && !_isKnownWebView(ua)) {
      issues.add(
        _UaValidationIssue(
          severity: _UaIssueSeverity.warning,
          message: 'User agent is unusually long (${ua.length} characters)',
          field: 'length',
        ),
      );
    }
    final openParens = ua.split('(').length - 1;
    final closeParens = ua.split(')').length - 1;
    if (openParens != closeParens) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Mismatched parentheses',
          field: 'format',
        ),
      );
    }
    final openBrackets = ua.split('[').length - 1;
    final closeBrackets = ua.split(']').length - 1;
    if (openBrackets != closeBrackets) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Mismatched square brackets',
          field: 'format',
        ),
      );
    }
    if (ua.contains('\u0000') || ua.contains('\n') || ua.contains('\r')) {
      issues.add(
        const _UaValidationIssue(
          severity: _UaIssueSeverity.error,
          message: 'Contains invalid characters (null bytes or newlines)',
          field: 'format',
        ),
      );
    }
    const fakePatterns = [
      'fake',
      'test',
      'example',
      'dummy',
      'xxx',
      'asdf',
      'qwerty',
    ];
    final lower = ua.toLowerCase();
    for (final pattern in fakePatterns) {
      if (lower.contains(pattern)) {
        issues.add(
          _UaValidationIssue(
            severity: _UaIssueSeverity.warning,
            message: "Contains suspicious pattern: '$pattern'",
            field: 'content',
          ),
        );
        break;
      }
    }
    return issues;
  }

  static double _calculateConfidence(
    _UaBrowserInfo? browser,
    _UaPlatformInfo? platform,
    _UaEngineInfo? engine,
    _UaWebViewInfo? webView,
    List<_UaValidationIssue> issues,
    bool isBot,
  ) {
    var confidence = 0.5;
    if (isBot) return 0.7;
    if (browser != null) {
      confidence += 0.15;
      if (browser.majorVersion != null) {
        confidence += 0.1;
      }
      if (browser.isWebView && webView != null) {
        confidence += 0.1;
      }
    }
    if (platform != null) {
      confidence += 0.12;
      if (platform.version != null) {
        confidence += 0.05;
      }
    }
    if (engine != null) {
      confidence += 0.08;
    }
    if (webView != null) {
      if (webView.appVersion != null) confidence += 0.05;
      if (webView.buildId != null) confidence += 0.03;
      if (webView.additionalInfo.isNotEmpty) confidence += 0.02;
    }
    for (final issue in issues) {
      switch (issue.severity) {
        case _UaIssueSeverity.error:
          confidence -= 0.2;
          break;
        case _UaIssueSeverity.warning:
          confidence -= 0.08;
          break;
        case _UaIssueSeverity.info:
          confidence -= 0.02;
          break;
      }
    }
    return confidence.clamp(0.0, 1.0);
  }

  static _UaScore _calculateScore(_UaParsedUserAgent parsed) {
    var score = 50;
    final notes = <String>[];
    if (parsed.isBot) {
      notes.add('Bot: ${parsed.botName ?? "unknown"}');
      return _UaScore(60, notes.join(' | '));
    }
    if (parsed.browser != null) {
      final browser = parsed.browser!;
      score += 15;
      notes.add(
        '${browser.isWebView ? "WebView" : "Browser"}: ${browser.name} ${browser.version}',
      );
      if (browser.majorVersion != null) {
        if (browser.isWebView) {
          final range = validWebViewRanges[browser.name];
          if (range != null) {
            if (range.contains(browser.majorVersion!)) {
              score += 10;
            } else if (browser.majorVersion! < range.min) {
              score -= 10;
              notes.add('Outdated app version');
            }
          }
        } else {
          final range = validVersionRanges[browser.name];
          if (range != null) {
            if (range.contains(browser.majorVersion!)) {
              score += 10;
            } else if (browser.majorVersion! < range.min) {
              score -= 10;
              notes.add('Outdated browser version');
            }
          }
        }
      }
    } else {
      score -= 20;
      notes.add('Unknown browser');
    }
    if (parsed.platform != null) {
      score += 10;
      notes.add(
        'Platform: ${parsed.platform!.name}${parsed.platform!.version != null ? " ${parsed.platform!.version}" : ""}',
      );
    } else {
      score -= 15;
      notes.add('Unknown platform');
    }
    if (parsed.device != null) {
      score += 5;
    }
    if (parsed.engine != null) {
      score += 5;
    }
    if (parsed.webView != null) {
      score += 5;
      if (parsed.webView!.buildId != null) {
        score += 3;
      }
    }
    for (final issue in parsed.issues) {
      switch (issue.severity) {
        case _UaIssueSeverity.error:
          score -= 15;
          break;
        case _UaIssueSeverity.warning:
          score -= 5;
          break;
        case _UaIssueSeverity.info:
          score -= 1;
          break;
      }
    }
    score += (parsed.confidence * 10).round();
    score = score.clamp(0, 100).toInt();
    final summary = notes.isEmpty ? 'Valid user agent' : notes.join(' | ');
    return _UaScore(score, summary);
  }
}

class _UaScore {
  const _UaScore(this.score, this.summary);
  final int score;
  final String summary;
}

class _UaBotPattern {
  const _UaBotPattern(this.pattern, this.name);
  final String pattern;
  final String name;
}

class _UaBrowserPattern {
  const _UaBrowserPattern(
    this.pattern,
    this.name,
    this.versionPattern,
    this.isWebView,
  );
  final String pattern;
  final String name;
  final String versionPattern;
  final bool isWebView;
}

class _UaBotResult {
  const _UaBotResult(this.isBot, this.name);
  final bool isBot;
  final String? name;
}

class _UaWebViewPattern {
  const _UaWebViewPattern(this.app, this.patterns);
  final String app;
  final List<_UaKeyPattern> patterns;
}

class _UaKeyPattern {
  const _UaKeyPattern(this.key, this.regex);
  final String key;
  final String regex;
}

class _OfflineLlmView extends StatefulWidget {
  const _OfflineLlmView();

  @override
  State<_OfflineLlmView> createState() => _OfflineLlmViewState();
}

class _ChatMessage {
  final String role; // 'user' or 'assistant'
  String content;
  _ChatMessage({required this.role, required this.content});
}

class _ChatInputField extends StatefulWidget {
  const _ChatInputField({
    required this.controller,
    required this.onSubmit,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool enabled;

  @override
  State<_ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<_ChatInputField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onSubmit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        maxLines: 4,
        minLines: 1,
        enabled: widget.enabled,
        decoration: InputDecoration(
          hintText: widget.enabled
              ? 'Type a message... (Enter to send)'
              : 'Start a model first...',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
          hintStyle: TextStyle(color: appColors.mutedText),
        ),
        style: TextStyle(
          fontFamily: 'Menlo',
          fontSize: 12,
          color: appColors.editorText,
        ),
      ),
    );
  }
}

class _OfflineLlmViewState extends State<_OfflineLlmView> {
  final LocalLLMService _service = LocalLLMService();
  final TextEditingController _prompt = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ModelInfo> _models = [];
  final List<_ChatMessage> _messages = [];
  bool _loadingModels = false;
  bool _startingServer = false;
  bool _stoppingServer = false;
  bool _generating = false;
  String? _error;

  ModelPreset? _downloadingPreset;
  double _downloadProgress = 0;
  StreamSubscription<String>? _generationSub;

  int _maxTokens = 256;
  double _temperature = 0.7;

  @override
  void initState() {
    super.initState();
    _refreshModels();
  }

  @override
  void dispose() {
    _generationSub?.cancel();
    unawaited(_service.stopServer());
    _prompt.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshModels() async {
    setState(() {
      _loadingModels = true;
      _error = null;
    });
    try {
      final models = await _service.getAvailableModels();
      models.sort((a, b) => a.name.compareTo(b.name));
      setState(() => _models = models);
    } catch (e) {
      setState(() => _error = 'Failed to load models: $e');
    } finally {
      setState(() => _loadingModels = false);
    }
  }

  Future<void> _startServer(ModelInfo model) async {
    if (_startingServer) return;
    final serverBinary = File(_service.serverBinaryPath);
    final serverDir = Directory(_service.serverBundleDir);
    if (!serverBinary.existsSync() || !serverDir.existsSync()) {
      setState(
        () => _error =
            'Missing server bundle. Expected ${_service.serverBundleDir}',
      );
      return;
    }
    final requiredLibs = ['libllama.dylib', 'libggml.dylib'];
    final missingLibs = requiredLibs
        .where(
          (lib) => !File(p.join(_service.serverBundleDir, lib)).existsSync(),
        )
        .toList();
    if (missingLibs.isNotEmpty) {
      setState(
        () => _error =
            'Server bundle is incomplete (missing ${missingLibs.join(", ")}).',
      );
      return;
    }
    setState(() {
      _startingServer = true;
      _error = null;
    });
    try {
      await _service.startServer(model.path);
      setState(() {});
    } catch (e) {
      setState(() => _error = 'Failed to start server: $e');
    } finally {
      setState(() => _startingServer = false);
    }
  }

  Future<void> _stopServer() async {
    if (_stoppingServer) return;
    setState(() => _stoppingServer = true);
    await _service.stopServer();
    setState(() => _stoppingServer = false);
  }

  Future<void> _downloadPreset(ModelPreset preset) async {
    if (_downloadingPreset != null) return;
    if (_isPresetInstalled(preset)) return;
    setState(() {
      _downloadingPreset = preset;
      _downloadProgress = 0;
      _error = null;
    });
    try {
      await _service.downloadModel(preset, (progress) {
        setState(() => _downloadProgress = progress);
      });
      await _refreshModels();
    } catch (e) {
      setState(() => _error = 'Download failed: $e');
    } finally {
      setState(() {
        _downloadingPreset = null;
        _downloadProgress = 0;
      });
    }
  }

  Future<void> _deleteModel(ModelInfo model) async {
    await _service.deleteModel(model.path);
    await _refreshModels();
  }

  Future<void> _run() async {
    if (_generating) return;
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) return;
    if (!_service.isReady) {
      setState(() => _error = 'Start the server before generating.');
      return;
    }

    // Add user message to history and clear input
    final userMessage = _ChatMessage(role: 'user', content: prompt);
    final assistantMessage = _ChatMessage(role: 'assistant', content: '');

    setState(() {
      _messages.add(userMessage);
      _messages.add(assistantMessage);
      _prompt.clear();
      _generating = true;
      _error = null;
    });

    // Build conversation history for context
    final chatHistory = _messages
        .where((m) => m.content.isNotEmpty || m == assistantMessage)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();
    // Remove the empty assistant message from history sent to API
    if (chatHistory.isNotEmpty && chatHistory.last['content']!.isEmpty) {
      chatHistory.removeLast();
    }

    _scrollToBottom();
    _generationSub?.cancel();
    _generationSub = _service
        .generateChat(
          chatHistory,
          maxTokens: _maxTokens,
          temperature: _temperature,
        )
        .listen(
          (chunk) {
            assistantMessage.content += chunk;
            setState(() {});
            _scrollToBottom();
          },
          onError: (err) {
            setState(() {
              _error = 'Generation failed: $err';
              _generating = false;
            });
          },
          onDone: () {
            setState(() => _generating = false);
          },
        );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearHistory() {
    _generationSub?.cancel();
    setState(() {
      _messages.clear();
      _generating = false;
    });
  }

  Future<void> _stopGeneration() async {
    await _generationSub?.cancel();
    _generationSub = null;
    setState(() => _generating = false);
  }

  bool _isPresetInstalled(ModelPreset preset) {
    return _models.any((model) => p.basename(model.path) == preset.filename);
  }

  bool _isModelActive(ModelInfo model) {
    return _service.isReady && _service.currentModel == model.path;
  }

  String _presetSize(ModelPreset preset) {
    final size = preset.sizeBytes;
    if (size > 1e9) return '${(size / 1e9).toStringAsFixed(1)} GB';
    return '${(size / 1e6).toStringAsFixed(0)} MB';
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _toolSurfaceDecoration(context, radius: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: Row(
            children: [
              Expanded(
                child: _buildCard(
                  context,
                  title: 'Installed Models',
                  trailing: _loadingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ToolIconButton(
                          icon: Icons.refresh,
                          tooltip: 'Refresh',
                          onPressed: _refreshModels,
                        ),
                  child: _models.isEmpty
                      ? const Center(child: Text('No models downloaded yet.'))
                      : ListView.separated(
                          itemCount: _models.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 12),
                          itemBuilder: (context, index) {
                            final model = _models[index];
                            final isActive = _isModelActive(model);
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        model.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        model.sizeFormatted,
                                        style: _mutedToolTextStyle(context),
                                      ),
                                      if (isActive)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            'Running',
                                            style: TextStyle(
                                              color: appColors.success,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ToolButton(
                                  label: isActive ? 'Stop' : 'Start',
                                  onPressed: isActive || _startingServer
                                      ? (isActive ? _stopServer : null)
                                      : () => _startServer(model),
                                ),
                                const SizedBox(width: 6),
                                ToolIconButton(
                                  icon: Icons.delete,
                                  tooltip: 'Delete',
                                  onPressed: isActive
                                      ? null
                                      : () => _deleteModel(model),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCard(
                  context,
                  title: 'Download Presets',
                  child: ListView.separated(
                    itemCount: kModelPresets.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final preset = kModelPresets[index];
                      final installed = _isPresetInstalled(preset);
                      final downloading = _downloadingPreset == preset;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      preset.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_presetSize(preset)} · ${preset.description}',
                                      style: _mutedToolTextStyle(context),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ToolButton(
                                label: installed ? 'Installed' : 'Download',
                                onPressed: installed || downloading
                                    ? null
                                    : () => _downloadPreset(preset),
                              ),
                            ],
                          ),
                          if (downloading)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: LinearProgressIndicator(
                                value: _downloadProgress,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Chat history section
        Expanded(
          child: Container(
            decoration: _toolSurfaceDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Conversation',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Tokens', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          SmallDropdown(
                            items: const ['128', '256', '512', '1024', '2048'],
                            initialValue: '$_maxTokens',
                            onChanged: (value) =>
                                setState(() => _maxTokens = int.parse(value)),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Temp', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          SmallDropdown(
                            items: const [
                              '0.2',
                              '0.4',
                              '0.6',
                              '0.7',
                              '0.8',
                              '1.0',
                            ],
                            initialValue: _temperature.toStringAsFixed(1),
                            onChanged: (value) => setState(
                              () => _temperature = double.parse(value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      ToolIconButton(
                        icon: Icons.delete_outline,
                        tooltip: 'Clear history',
                        onPressed: _messages.isEmpty ? null : _clearHistory,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Messages list
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Text(
                            _service.isReady
                                ? 'Start a conversation...'
                                : 'Start a model to begin chatting',
                            style: _mutedToolTextStyle(context),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isUser = msg.role == 'user';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: isUser
                                          ? appColors.success
                                          : const Color(0xFF6B7280),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      isUser ? Icons.person : Icons.smart_toy,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isUser ? 'You' : 'Assistant',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: appColors.mutedText,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          msg.content.isEmpty &&
                                                  !isUser &&
                                                  _generating
                                              ? '...'
                                              : msg.content,
                                          style: const TextStyle(
                                            fontFamily: 'Menlo',
                                            fontSize: 12,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Input section
        Container(
          decoration: _toolSurfaceDecoration(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _ChatInputField(
                  controller: _prompt,
                  onSubmit: _run,
                  enabled: _service.isReady,
                ),
              ),
              if (_generating)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: IconButton(
                    icon: Icon(Icons.stop, color: appColors.error),
                    tooltip: 'Stop',
                    onPressed: _stopGeneration,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: IconButton(
                    icon: Icon(Icons.send, color: appColors.success),
                    tooltip: 'Send',
                    onPressed: _service.isReady ? _run : null,
                  ),
                ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: _errorToolTextStyle(context)),
        ],
      ],
    );
  }
}

class _AntiBotDetectorView extends StatefulWidget {
  const _AntiBotDetectorView();

  @override
  State<_AntiBotDetectorView> createState() => _AntiBotDetectorViewState();
}

class _AntiBotDetectorViewState extends State<_AntiBotDetectorView> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _url.dispose();
    _output.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final rawUrl = _url.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _output.clear();
        _error = null;
      });
      return;
    }
    final normalized = _normalizeUrl(rawUrl);
    if (normalized == null) {
      setState(() => _error = 'Invalid URL');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _output.text = 'Fetching...';
    });
    try {
      final fetched = await _fetchPage(normalized);
      final analysis = _AntiBotDetector.analyze(
        url: fetched.url,
        html: fetched.html,
        headers: fetched.headers,
        cookies: fetched.cookies,
        scripts: fetched.scripts,
        jsVariables: fetched.inlineScripts,
      );
      _output.text = _formatAntiBotResult(analysis, fetched.statusCode);
    } catch (e) {
      _output.clear();
      _error = 'Failed to fetch page: $e';
    } finally {
      setState(() => _loading = false);
    }
  }

  Uri? _normalizeUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    return Uri.tryParse(withScheme);
  }

  Future<_FetchedPage> _fetchPage(Uri uri) async {
    final client = HttpClient();
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml',
    );
    request.headers.set(
      HttpHeaders.userAgentHeader,
      _AntiBotDetector.defaultUserAgent,
    );
    final response = await request.close();
    final statusCode = response.statusCode;
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    final cookies = <String, String>{};
    // Parse cookies from header manually to avoid FormatException with invalid characters
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null) {
      for (final header in setCookieHeaders) {
        try {
          final parts = header.split(';').first.split('=');
          if (parts.length >= 2) {
            cookies[parts[0].trim()] = parts.sublist(1).join('=').trim();
          }
        } catch (_) {
          // Skip malformed cookies
        }
      }
    }
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return _FetchedPage(
      url: uri.toString(),
      statusCode: statusCode,
      headers: headers,
      cookies: cookies,
      html: body,
      scripts: _extractScriptSrc(body),
      inlineScripts: _extractInlineScripts(body),
    );
  }

  List<String> _extractScriptSrc(String html) {
    final matches = RegExp(
      "<script[^>]+src=['\\\"]([^'\\\"]+)['\\\"]",
      caseSensitive: false,
    ).allMatches(html);
    return matches
        .map((match) => match.group(1) ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
  }

  List<String> _extractInlineScripts(String html) {
    final matches = RegExp(
      "<script(?![^>]*\\bsrc=)[^>]*>([\\s\\S]*?)</script>",
      caseSensitive: false,
    ).allMatches(html);
    return matches
        .map((match) => (match.group(1) ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _url.text = text.trim());
  }

  void _setSample() {
    setState(() => _url.text = 'https://example.com');
  }

  void _clear() {
    setState(() {
      _url.clear();
      _output.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // URL input row
        Row(
          children: [
            const Text('URL', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: _toolSurfaceDecoration(context, radius: 6),
                child: TextField(
                  controller: _url,
                  decoration: InputDecoration(
                    hintText: 'https://example.com',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: appColors.mutedText),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  style: TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 12,
                    color: appColors.editorText,
                  ),
                  onSubmitted: (_) => _analyze(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ToolButton(label: 'Go', onPressed: _analyze),
            ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
            ToolButton(label: 'Sample', onPressed: _setSample),
            ToolButton(label: 'Clear', onPressed: _clear),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Report output
        Expanded(
          child: EditorPane(
            label: 'Report',
            actions: [
              ToolButton(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _output.text)),
              ),
            ],
            placeholder: 'Detection results appear here...',
            readOnly: true,
            controller: _output,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: _errorToolTextStyle(context)),
        ],
      ],
    );
  }
}

class _FetchedPage {
  const _FetchedPage({
    required this.url,
    required this.statusCode,
    required this.headers,
    required this.cookies,
    required this.html,
    required this.scripts,
    required this.inlineScripts,
  });

  final String url;
  final int statusCode;
  final Map<String, String> headers;
  final Map<String, String> cookies;
  final String html;
  final List<String> scripts;
  final List<String> inlineScripts;
}

String _formatAntiBotResult(_AntiBotAnalysisResult result, int statusCode) {
  final buffer = StringBuffer();
  buffer.writeln('URL: ${result.url}');
  buffer.writeln('Status: $statusCode');
  buffer.writeln('Risk Level: ${result.riskLevel.label}');
  buffer.writeln();
  buffer.writeln(result.summary);
  buffer.writeln();
  if (result.detections.isEmpty) {
    buffer.writeln('No protection detected.');
    return buffer.toString().trimRight();
  }
  buffer.writeln('Detections:');
  for (final detection in result.detections) {
    final value = detection.matchedValue ?? detection.matchedPattern;
    buffer.writeln(
      '  - ${detection.technology} (${detection.category.label}, ${detection.patternType.label}, ${detection.confidence}%)',
    );
    buffer.writeln('    Match: $value');
  }
  return buffer.toString().trimRight();
}

enum _AntiBotCategory { antiBot, captcha, fingerprinting, waf }

extension _AntiBotCategoryLabel on _AntiBotCategory {
  String get label {
    switch (this) {
      case _AntiBotCategory.antiBot:
        return 'Anti-Bot';
      case _AntiBotCategory.captcha:
        return 'CAPTCHA';
      case _AntiBotCategory.fingerprinting:
        return 'Fingerprinting';
      case _AntiBotCategory.waf:
        return 'WAF/CDN';
    }
  }
}

enum _AntiBotPatternType { cookie, header, script, html, js, url, meta }

extension _AntiBotPatternTypeLabel on _AntiBotPatternType {
  String get label {
    switch (this) {
      case _AntiBotPatternType.cookie:
        return 'cookie';
      case _AntiBotPatternType.header:
        return 'header';
      case _AntiBotPatternType.script:
        return 'script';
      case _AntiBotPatternType.html:
        return 'html';
      case _AntiBotPatternType.js:
        return 'js';
      case _AntiBotPatternType.url:
        return 'url';
      case _AntiBotPatternType.meta:
        return 'meta';
    }
  }
}

class _AntiBotTechnology {
  const _AntiBotTechnology({
    required this.name,
    required this.category,
    required this.website,
    required this.description,
    required this.patterns,
  });

  final String name;
  final _AntiBotCategory category;
  final String website;
  final String description;
  final List<_AntiBotPattern> patterns;
}

class _AntiBotPattern {
  const _AntiBotPattern({
    required this.type,
    required this.key,
    required this.regex,
    required this.confidence,
  });

  final _AntiBotPatternType type;
  final String? key;
  final String regex;
  final int confidence;
}

class _AntiBotDetection {
  const _AntiBotDetection({
    required this.technology,
    required this.category,
    required this.patternType,
    required this.matchedPattern,
    required this.matchedValue,
    required this.confidence,
  });

  final String technology;
  final _AntiBotCategory category;
  final _AntiBotPatternType patternType;
  final String matchedPattern;
  final String? matchedValue;
  final int confidence;
}

class _AntiBotAnalysisResult {
  const _AntiBotAnalysisResult({
    required this.url,
    required this.detections,
    required this.antiBot,
    required this.captcha,
    required this.fingerprinting,
    required this.waf,
    required this.summary,
    required this.riskLevel,
  });

  final String url;
  final List<_AntiBotDetection> detections;
  final List<_AntiBotDetection> antiBot;
  final List<_AntiBotDetection> captcha;
  final List<_AntiBotDetection> fingerprinting;
  final List<_AntiBotDetection> waf;
  final String summary;
  final _AntiBotRiskLevel riskLevel;
}

enum _AntiBotRiskLevel { none, low, medium, high, extreme }

extension _AntiBotRiskLevelLabel on _AntiBotRiskLevel {
  String get label {
    switch (this) {
      case _AntiBotRiskLevel.none:
        return 'None';
      case _AntiBotRiskLevel.low:
        return 'Low';
      case _AntiBotRiskLevel.medium:
        return 'Medium';
      case _AntiBotRiskLevel.high:
        return 'High';
      case _AntiBotRiskLevel.extreme:
        return 'Extreme';
    }
  }
}

class _AntiBotDetector {
  static const String defaultUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.85 Safari/537.36';

  static const List<_AntiBotTechnology> technologies = [
    _AntiBotTechnology(
      name: 'Cloudflare Bot Management',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.cloudflare.com/products/bot-management/',
      description: 'Enterprise bot management solution from Cloudflare',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'cf_clearance',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '__cf_bm',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'cf_ob_info',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_cf_chl',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'cf-ray',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'cf-cache-status',
          regex: '.*',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'server',
          regex: 'cloudflare',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'challenges\\.cloudflare\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: '/cdn-cgi/challenge-platform/',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'Checking your browser',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'cf-browser-verification',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'window._cf_chl_opt',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Akamai Bot Manager',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.akamai.com/products/bot-manager',
      description: 'Advanced bot detection and mitigation from Akamai',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_abck',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'ak_bmsc',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'bm_sz',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'bm_sv',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'bm_mi',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'ak\\.js',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'akamai.*sensor',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'window._cf',
          regex: '.*',
          confidence: 50,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'bmak',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'DataDome',
      category: _AntiBotCategory.antiBot,
      website: 'https://datadome.co/',
      description: 'Real-time bot protection for web, mobile apps and APIs',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'datadome',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'datadome-_zldp',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'datadome-_zldt',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'js\\.datadome\\.co',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'tags\\.datadome\\.co',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-datadome',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-dd-b',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-dd-type',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'window.ddjskey',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'DataDome',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'PerimeterX',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.perimeterx.com/',
      description: 'Bot detection using behavioral analysis',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_px',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_px2',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_px3',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_pxvid',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_pxhd',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_pxde',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'client\\.perimeterx\\.net',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'captcha\\.px-cdn\\.net',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'window._pxAppId',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'PX',
          regex: '.*',
          confidence: 80,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Imperva/Incapsula',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.imperva.com/',
      description: 'Application security and bot management',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'incap_ses_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'visid_incap_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'nlbi_',
          regex: '.*',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'reese84',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-iinfo',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-cdn',
          regex: 'imperva|incapsula',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: '_Incapsula_Resource',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: '/_Incapsula_Resource\\?',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Kasada',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.kasada.io/',
      description: 'Polyform bot defense platform',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'x-kpsdk-ct',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'x-kpsdk-cd',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'x-kpsdk-v',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: '/ips\\.js',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'ct\\.kasada',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-kpsdk-ct',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'KPSDK',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Shape Security',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.f5.com/products/security/shape-security',
      description: 'F5 Shape bot defense (formerly Shape Security)',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_imp_apg_r_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_imp_apg_v_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'shape\\.com',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: '/async/api\\.js',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'shape',
          regex: '.*',
          confidence: 60,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'AWS WAF',
      category: _AntiBotCategory.antiBot,
      website: 'https://aws.amazon.com/waf/',
      description: 'Amazon Web Services Web Application Firewall',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'aws-waf-token',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'awswaf',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-amzn-waf-action',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-amzn-requestid',
          regex: '.*',
          confidence: 50,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'captcha\\.awswaf\\.com',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Distil Networks',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.imperva.com/products/advanced-bot-protection/',
      description: 'Advanced bot protection (now part of Imperva)',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_SID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_IID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_UID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_HID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'D_ZID',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'distil',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'distilIdentificationBlock',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Forter',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.forter.com/',
      description: 'E-commerce fraud prevention',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'forterToken',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'forter\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'ftr__',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Sift',
      category: _AntiBotCategory.antiBot,
      website: 'https://sift.com/',
      description: 'Digital trust and safety platform',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'cdn\\.sift\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'cdn\\.siftscience\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: '_sift',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Netacea',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.netacea.com/',
      description: 'Bot management and attack prevention',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '_netacea_',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'netacea',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Reblaze',
      category: _AntiBotCategory.antiBot,
      website: 'https://www.reblaze.com/',
      description: 'Cloud-native web security platform',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'rbzid',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: 'rbzsessionid',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-reblaze-protection',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'reCAPTCHA v2',
      category: _AntiBotCategory.captcha,
      website: 'https://www.google.com/recaptcha/',
      description: 'Google CAPTCHA (checkbox)',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'google\\.com/recaptcha/api\\.js(?!.*render=)',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'www\\.gstatic\\.com/recaptcha',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'g-recaptcha',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'data-sitekey',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'grecaptcha',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'reCAPTCHA v3',
      category: _AntiBotCategory.captcha,
      website: 'https://www.google.com/recaptcha/',
      description: 'Google CAPTCHA (invisible)',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'google\\.com/recaptcha/api\\.js\\?.*render=',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'recaptcha/enterprise\\.js',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'recaptcha-badge',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'grecaptcha.execute',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'hCaptcha',
      category: _AntiBotCategory.captcha,
      website: 'https://www.hcaptcha.com/',
      description: 'Privacy-focused CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'hcaptcha\\.com/1/api\\.js',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'js\\.hcaptcha\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'h-captcha',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'data-hcaptcha',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'hcaptcha',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Cloudflare Turnstile',
      category: _AntiBotCategory.captcha,
      website: 'https://www.cloudflare.com/products/turnstile/',
      description: 'Cloudflare CAPTCHA alternative',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'challenges\\.cloudflare\\.com/turnstile',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'cf-turnstile',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'turnstile',
          regex: '.*',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'FunCaptcha/Arkose Labs',
      category: _AntiBotCategory.captcha,
      website: 'https://www.arkoselabs.com/',
      description: 'Interactive puzzle CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'arkoselabs\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'funcaptcha\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'funcaptcha',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'ArkoseEnforcement',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'GeeTest',
      category: _AntiBotCategory.captcha,
      website: 'https://www.geetest.com/',
      description: 'Behavioral CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'geetest\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'gt\\.js',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'geetest_',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'initGeetest',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'KeyCAPTCHA',
      category: _AntiBotCategory.captcha,
      website: 'https://www.keycaptcha.com/',
      description: 'Puzzle-based CAPTCHA',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'keycaptcha\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'keycaptcha',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'FingerprintJS',
      category: _AntiBotCategory.fingerprinting,
      website: 'https://fingerprint.com/',
      description: 'Browser fingerprinting library',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'fpjs\\.io',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'fingerprint\\.com',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.script,
          key: null,
          regex: 'fingerprintjs',
          confidence: 90,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'FingerprintJS',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'Fingerprint2',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Canvas Fingerprinting',
      category: _AntiBotCategory.fingerprinting,
      website: '',
      description: 'Browser identification via Canvas API',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'toDataURL',
          regex: '.*',
          confidence: 50,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.html,
          key: null,
          regex: 'canvas.*fingerprint',
          confidence: 70,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'WebGL Fingerprinting',
      category: _AntiBotCategory.fingerprinting,
      website: '',
      description: 'Browser identification via WebGL',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'WEBGL_debug_renderer_info',
          regex: '.*',
          confidence: 70,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'getExtension',
          regex: '.*',
          confidence: 30,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'AudioContext Fingerprinting',
      category: _AntiBotCategory.fingerprinting,
      website: '',
      description: 'Browser identification via Audio API',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'OfflineAudioContext',
          regex: '.*',
          confidence: 60,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.js,
          key: 'createOscillator',
          regex: '.*',
          confidence: 50,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Cloudflare',
      category: _AntiBotCategory.waf,
      website: 'https://www.cloudflare.com/',
      description: 'CDN and DDoS protection',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'server',
          regex: 'cloudflare',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'cf-ray',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.cookie,
          key: '__cflb',
          regex: '.*',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Akamai',
      category: _AntiBotCategory.waf,
      website: 'https://www.akamai.com/',
      description: 'CDN and web application security',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-akamai-transformed',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'akamai-origin-hop',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'server',
          regex: 'akamai',
          confidence: 90,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Fastly',
      category: _AntiBotCategory.waf,
      website: 'https://www.fastly.com/',
      description: 'Edge cloud platform and CDN',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-served-by',
          regex: 'cache-',
          confidence: 80,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-fastly-request-id',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'via',
          regex: 'varnish',
          confidence: 70,
        ),
      ],
    ),
    _AntiBotTechnology(
      name: 'Sucuri',
      category: _AntiBotCategory.waf,
      website: 'https://sucuri.net/',
      description: 'Website security and WAF',
      patterns: [
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-sucuri-id',
          regex: '.*',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'server',
          regex: 'sucuri',
          confidence: 100,
        ),
        _AntiBotPattern(
          type: _AntiBotPatternType.header,
          key: 'x-sucuri-cache',
          regex: '.*',
          confidence: 100,
        ),
      ],
    ),
  ];

  static _AntiBotAnalysisResult analyze({
    required String url,
    String? html,
    Map<String, String> headers = const {},
    Map<String, String> cookies = const {},
    List<String> scripts = const [],
    List<String> jsVariables = const [],
  }) {
    final detections = <_AntiBotDetection>[];
    final headersLower = {
      for (final entry in headers.entries)
        entry.key.toLowerCase(): entry.value.toLowerCase(),
    };
    final cookiesLower = {
      for (final entry in cookies.entries) entry.key.toLowerCase(): entry.value,
    };
    final htmlLower = (html ?? '').toLowerCase();
    final scriptsJoined = scripts.join(' ').toLowerCase();
    final jsJoined = jsVariables.join(' ').toLowerCase();

    for (final tech in technologies) {
      for (final pattern in tech.patterns) {
        var matched = false;
        String? matchedValue;
        final regex = RegExp(pattern.regex, caseSensitive: false);
        switch (pattern.type) {
          case _AntiBotPatternType.cookie:
            if (pattern.key != null) {
              final key = pattern.key!.toLowerCase();
              for (final entry in cookiesLower.entries) {
                if (entry.key == key || entry.key.startsWith(key)) {
                  if (pattern.regex == '.*' || regex.hasMatch(entry.value)) {
                    matched = true;
                    matchedValue = '${entry.key}=${entry.value}';
                    break;
                  }
                }
              }
            }
            break;
          case _AntiBotPatternType.header:
            if (pattern.key != null) {
              final key = pattern.key!.toLowerCase();
              final value = headersLower[key];
              if (value != null &&
                  (pattern.regex == '.*' || regex.hasMatch(value))) {
                matched = true;
                matchedValue = '$key: $value';
              }
            }
            break;
          case _AntiBotPatternType.script:
            if (regex.hasMatch(scriptsJoined)) {
              matched = true;
              matchedValue = pattern.regex;
            }
            break;
          case _AntiBotPatternType.html:
          case _AntiBotPatternType.meta:
            if (regex.hasMatch(htmlLower)) {
              matched = true;
              matchedValue = pattern.regex;
            }
            break;
          case _AntiBotPatternType.js:
            if (pattern.key != null &&
                jsJoined.contains(pattern.key!.toLowerCase())) {
              matched = true;
              matchedValue = pattern.key!.toLowerCase();
            }
            break;
          case _AntiBotPatternType.url:
            if (regex.hasMatch(url.toLowerCase())) {
              matched = true;
              matchedValue = url;
            }
            break;
        }
        if (matched) {
          detections.add(
            _AntiBotDetection(
              technology: tech.name,
              category: tech.category,
              patternType: pattern.type,
              matchedPattern: pattern.regex,
              matchedValue: matchedValue,
              confidence: pattern.confidence,
            ),
          );
        }
      }
    }

    final bestDetections = <String, _AntiBotDetection>{};
    for (final detection in detections) {
      final existing = bestDetections[detection.technology];
      if (existing == null || detection.confidence > existing.confidence) {
        bestDetections[detection.technology] = detection;
      }
    }

    final uniqueDetections = bestDetections.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final antiBot = uniqueDetections
        .where((d) => d.category == _AntiBotCategory.antiBot)
        .toList();
    final captcha = uniqueDetections
        .where((d) => d.category == _AntiBotCategory.captcha)
        .toList();
    final fingerprinting = uniqueDetections
        .where((d) => d.category == _AntiBotCategory.fingerprinting)
        .toList();
    final waf = uniqueDetections
        .where((d) => d.category == _AntiBotCategory.waf)
        .toList();

    final riskLevel = _calculateRiskLevel(antiBot, captcha);
    final summary = _generateSummary(
      antiBot: antiBot,
      captcha: captcha,
      fingerprinting: fingerprinting,
      waf: waf,
      riskLevel: riskLevel,
    );

    return _AntiBotAnalysisResult(
      url: url,
      detections: uniqueDetections,
      antiBot: antiBot,
      captcha: captcha,
      fingerprinting: fingerprinting,
      waf: waf,
      summary: summary,
      riskLevel: riskLevel,
    );
  }

  static _AntiBotRiskLevel _calculateRiskLevel(
    List<_AntiBotDetection> antiBot,
    List<_AntiBotDetection> captcha,
  ) {
    const hardAntiBot = [
      'Akamai Bot Manager',
      'DataDome',
      'PerimeterX',
      'Kasada',
      'Shape Security',
    ];
    const mediumAntiBot = [
      'Cloudflare Bot Management',
      'Imperva/Incapsula',
      'AWS WAF',
    ];
    var score = 0;
    for (final detection in antiBot) {
      if (hardAntiBot.contains(detection.technology)) {
        score += 30;
      } else if (mediumAntiBot.contains(detection.technology)) {
        score += 20;
      } else {
        score += 10;
      }
    }
    for (final detection in captcha) {
      if (detection.technology.contains('reCAPTCHA v3') ||
          detection.technology.contains('Arkose')) {
        score += 15;
      } else {
        score += 10;
      }
    }
    if (score == 0) return _AntiBotRiskLevel.none;
    if (score <= 15) return _AntiBotRiskLevel.low;
    if (score <= 30) return _AntiBotRiskLevel.medium;
    if (score <= 50) return _AntiBotRiskLevel.high;
    return _AntiBotRiskLevel.extreme;
  }

  static String _generateSummary({
    required List<_AntiBotDetection> antiBot,
    required List<_AntiBotDetection> captcha,
    required List<_AntiBotDetection> fingerprinting,
    required List<_AntiBotDetection> waf,
    required _AntiBotRiskLevel riskLevel,
  }) {
    final lines = <String>[];
    if (antiBot.isEmpty && captcha.isEmpty && waf.isEmpty) {
      return 'No anti-bot protection detected.';
    }
    if (antiBot.isNotEmpty) {
      lines.add('Anti-Bot: ${antiBot.map((d) => d.technology).join(', ')}');
    }
    if (captcha.isNotEmpty) {
      lines.add('CAPTCHA: ${captcha.map((d) => d.technology).join(', ')}');
    }
    if (waf.isNotEmpty) {
      lines.add('WAF/CDN: ${waf.map((d) => d.technology).join(', ')}');
    }
    if (fingerprinting.isNotEmpty) {
      lines.add(
        'Fingerprinting: ${fingerprinting.map((d) => d.technology).join(', ')}',
      );
    }
    lines.add('');
    lines.add('Scraping Difficulty: ${riskLevel.label}');
    return lines.join('\n');
  }
}

class _JwtDebuggerView extends StatefulWidget {
  const _JwtDebuggerView();

  @override
  State<_JwtDebuggerView> createState() => _JwtDebuggerViewState();
}

class _JwtDebuggerViewState extends State<_JwtDebuggerView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _header = TextEditingController();
  final TextEditingController _payload = TextEditingController();
  final TextEditingController _secret = TextEditingController();
  String _alg = 'HS256';
  String _status = 'Signature Not Verified';
  Color _statusColor = const Color(0xFFB0B0B0);
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _header.dispose();
    _payload.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _parse() {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _header.clear();
        _payload.clear();
        _status = 'Signature Not Verified';
        _statusColor = const Color(0xFFB0B0B0);
        _error = null;
      });
      return;
    }
    final parts = raw.split('.');
    if (parts.length < 2) {
      setState(() => _error = 'Invalid JWT format.');
      return;
    }
    try {
      final headerJson = utf8.decode(_base64UrlDecode(parts[0]));
      final payloadJson = utf8.decode(_base64UrlDecode(parts[1]));
      _header.text = _prettyJson(headerJson);
      _payload.text = _prettyJson(payloadJson);
      final headerMap = jsonDecode(headerJson);
      if (headerMap is Map && headerMap['alg'] is String) {
        _alg = headerMap['alg'] as String;
      }
      _verifySignature(parts);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _verifySignature(List<String> parts) {
    if (parts.length < 3 || _secret.text.isEmpty) {
      setState(() {
        _status = 'Signature Not Verified';
        _statusColor = const Color(0xFFB0B0B0);
      });
      return;
    }
    final signingInput = '${parts[0]}.${parts[1]}';
    final secret = utf8.encode(_secret.text);
    crypto.Digest digest;
    switch (_alg) {
      case 'HS384':
        digest = crypto.Hmac(
          crypto.sha384,
          secret,
        ).convert(utf8.encode(signingInput));
        break;
      case 'HS512':
        digest = crypto.Hmac(
          crypto.sha512,
          secret,
        ).convert(utf8.encode(signingInput));
        break;
      case 'HS256':
      default:
        digest = crypto.Hmac(
          crypto.sha256,
          secret,
        ).convert(utf8.encode(signingInput));
        break;
    }
    final computed = _base64UrlNoPad(digest.bytes);
    final valid = computed == parts[2];
    setState(() {
      _status = valid ? 'Signature Verified' : 'Signature Mismatch';
      _statusColor = valid ? const Color(0xFF5DBB63) : const Color(0xFFD96B6B);
    });
  }

  String _prettyJson(String input) {
    try {
      final decoded = jsonDecode(input);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return input;
    }
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
    _parse();
  }

  void _setSample() {
    const header = '{"typ":"JWT","alg":"HS256"}';
    const payload = '{"sub":"1234567890","name":"John Doe","iat":1516239022}';
    final encodedHeader = _base64UrlNoPad(utf8.encode(header));
    final encodedPayload = _base64UrlNoPad(utf8.encode(payload));
    setState(() => _input.text = '$encodedHeader.$encodedPayload.');
    _parse();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _header.clear();
      _payload.clear();
      _error = null;
    });
  }

  Future<void> _copyInput() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
  }

  Future<void> _copyHeader() async {
    await Clipboard.setData(ClipboardData(text: _header.text));
  }

  Future<void> _copyPayload() async {
    await Clipboard.setData(ClipboardData(text: _payload.text));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 980;
        final inputPane = EditorPane(
          label: 'Input',
          actions: [
            ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
            ToolButton(label: 'Sample', onPressed: _setSample),
            ToolButton(label: 'Clear', onPressed: _clearInput),
            const ToolIconButton(icon: Icons.settings),
            SmallDropdown(
              items: const ['HS256', 'HS384', 'HS512'],
              initialValue: _alg,
              onChanged: (value) {
                setState(() => _alg = value);
                _parse();
              },
            ),
          ],
          controller: _input,
          onChanged: (_) => _parse(),
          placeholder: 'Paste JWT here...',
          copyAction: _copyInput,
        );
        final detailPane = ListView(
          padding: EdgeInsets.zero,
          children: [
            EditorPane(
              label: 'Header',
              actions: const [],
              controller: _header,
              readOnly: true,
              placeholder: '{ "typ": "JWT", "alg": "HS256" }',
              expand: false,
              fixedHeight: 110,
              copyAction: _copyHeader,
            ),
            const SizedBox(height: 12),
            EditorPane(
              label: 'Payload',
              actions: const [],
              controller: _payload,
              readOnly: true,
              placeholder: '{ "sub": "1234567890" }',
              expand: false,
              fixedHeight: 110,
              copyAction: _copyPayload,
            ),
            const SizedBox(height: 12),
            const Text(
              'Signature',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: _toolSurfaceDecoration(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('HMACSHA256(', style: TextStyle(fontSize: 11)),
                  Text(
                    '  base64UrlEncode(header) + "." +',
                    style: TextStyle(fontSize: 11),
                  ),
                  Text(
                    '  base64UrlEncode(payload) + "." +',
                    style: TextStyle(fontSize: 11),
                  ),
                  Text('  your-secret', style: TextStyle(fontSize: 11)),
                  Text(')', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _InlineTextField(
              hintText: 'your-secret',
              controller: _secret,
              onChanged: (_) => _parse(),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  _status,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: _errorToolTextStyle(context)),
            ],
          ],
        );
        return _ResizableSplit(
          horizontal: horizontal,
          initialRatio: horizontal ? 0.65 : 0.5,
          minSecondExtent: horizontal ? 320 : 260,
          first: inputPane,
          second: detailPane,
        );
      },
    );
  }
}

class _RegExpTesterView extends StatefulWidget {
  const _RegExpTesterView();

  @override
  State<_RegExpTesterView> createState() => _RegExpTesterViewState();
}

class _RegExpTesterViewState extends State<_RegExpTesterView> {
  final TextEditingController _regex = TextEditingController();
  final TextEditingController _text = TextEditingController();
  final TextEditingController _format = TextEditingController(text: r'$0\n');
  final TextEditingController _search = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;
  List<RegExpMatch> _matches = [];

  @override
  void dispose() {
    _regex.dispose();
    _text.dispose();
    _format.dispose();
    _search.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    try {
      final regExp = RegExp(_regex.text);
      _matches = regExp.allMatches(_text.text).toList();
      _output.text = _formatOutput(_matches, _format.text);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _formatOutput(List<RegExpMatch> matches, String format) {
    final formatted = format.replaceAll(r'\n', '\n');
    final buffer = StringBuffer();
    for (final match in matches) {
      var line = formatted;
      for (var i = 0; i <= match.groupCount; i++) {
        line = line.replaceAll('\$$i', match.group(i) ?? '');
      }
      buffer.write(line);
    }
    return buffer.toString();
  }

  Future<void> _pasteRegexClipboard() async {
    final text = await _readClipboardText();
    setState(() => _regex.text = text);
    _run();
  }

  Future<void> _pasteTextClipboard() async {
    final text = await _readClipboardText();
    setState(() => _text.text = text);
    _run();
  }

  void _setSample() {
    setState(() {
      _regex.text = r'([A-Z])\w+';
      _text.text =
          'DevUtils helps you with your tiny daily tasks. It works entirely offline.';
    });
    _run();
  }

  void _clearAll() {
    setState(() {
      _regex.clear();
      _text.clear();
      _output.clear();
      _matches = [];
      _error = null;
    });
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  List<RegExpMatch> _filteredMatches() {
    final query = _search.text.toLowerCase();
    if (query.isEmpty) return _matches;
    return _matches.where((match) {
      final text = match.group(0) ?? '';
      return text.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _filteredMatches();

    return _ResizableSplit(
      horizontal: false,
      initialRatio: 0.66,
      minFirstExtent: 260,
      minSecondExtent: 220,
      first: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'RegExp:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(
                width: 220,
                child: _InlineTextField(
                  hintText: r'([A-Z])\w+',
                  controller: _regex,
                  onChanged: (_) => _run(),
                ),
              ),
              ToolButton(label: 'Clipboard', onPressed: _pasteRegexClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clearAll),
              const ToolIconButton(icon: Icons.settings),
              const SizedBox(width: 8),
              const Text(
                'Text:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              ToolButton(label: 'Clipboard', onPressed: _pasteTextClipboard),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: _toolSurfaceDecoration(context),
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _text,
                maxLines: null,
                onChanged: (_) => _run(),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: TextStyle(color: context.appColors.editorText),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Output:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(
                width: 120,
                child: _InlineTextField(
                  hintText: r'$0\n',
                  controller: _format,
                  onChanged: (_) => _run(),
                ),
              ),
              SizedBox(
                width: 200,
                child: _InlineTextField(
                  hintText: 'Search matches...',
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EditorPane(
              label: '',
              actions: [ToolButton(label: 'Copy', onPressed: _copyOutput)],
              controller: _output,
              readOnly: true,
              placeholder: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: _errorToolTextStyle(context)),
            ),
          ],
        ],
      ),
      second: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              const Icon(Icons.chevron_left, size: 16),
              const SizedBox(width: 8),
              Text('${_matches.length} matches'),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          const ToolButton(label: 'Cheat Sheet'),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: _toolSurfaceDecoration(context),
              padding: const EdgeInsets.all(8),
              child: ListView.separated(
                itemCount: matches.length,
                separatorBuilder: (context, index) => const Divider(height: 8),
                itemBuilder: (context, index) {
                  final match = matches[index];
                  final value = match.group(0) ?? '';
                  return Text('"$value" (${match.start}, ${match.end})');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HtmlEntityView extends StatefulWidget {
  const _HtmlEntityView();

  @override
  State<_HtmlEntityView> createState() => _HtmlEntityViewState();
}

class _HtmlEntityViewState extends State<_HtmlEntityView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  var _encode = true;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    setState(() {
      _output.text = _encode ? _encodeEntities(text) : _decodeEntities(text);
    });
  }

  Future<void> _pasteClipboard() async {
    final text = await _readClipboardText();
    setState(() => _input.text = text);
  }

  void _setSample() {
    setState(() => _input.text = '<h1>Hello</h1>');
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
    return buildVerticalEditors(
      inputActions: [
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
        ToolButton(label: 'Sample', onPressed: _setSample),
        ToolButton(label: 'Clear', onPressed: _clearInput),
        const ToolIconButton(icon: Icons.settings),
        SegmentedToggle(
          options: const ['Encode', 'Decode'],
          initialIndex: _encode ? 0 : 1,
          onChanged: (index) {
            setState(() => _encode = index == 0);
            _run();
          },
        ),
      ],
      outputActions: [
        ToolButton(label: 'Copy', onPressed: _copyOutput),
        const ToolButton(label: 'Use as input'),
      ],
      inputPlaceholder: '<h1>Hello</h1>',
      outputPlaceholder: '&lt;h1&gt;Hello&lt;/h1&gt;',
      inputController: _input,
      outputController: _output,
    );
  }
}

String _encodeEntities(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _decodeEntities(String input) {
  final named = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    '#39': "'",
  };
  return input.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (
    match,
  ) {
    final value = match.group(1) ?? '';
    if (value.startsWith('#x') || value.startsWith('#X')) {
      final hex = value.substring(2);
      final code = int.tryParse(hex, radix: 16);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    if (value.startsWith('#')) {
      final num = int.tryParse(value.substring(1));
      return num == null ? match.group(0)! : String.fromCharCode(num);
    }
    return named[value] ?? match.group(0)!;
  });
}

class _UnixTimeConverterView extends StatefulWidget {
  const _UnixTimeConverterView();

  @override
  State<_UnixTimeConverterView> createState() => _UnixTimeConverterViewState();
}

class _UnixTimeConverterViewState extends State<_UnixTimeConverterView> {
  final TextEditingController _input = TextEditingController();
  String _format = 'Unix time (seconds since epoch)';
  String? _leftTimezone;
  String? _rightTimezone;
  DateTime? _currentUtcDate;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String _localTimezoneLabel() {
    final now = DateTime.now();
    return '${now.timeZoneName} (${_formatUtcOffset(now.timeZoneOffset)})';
  }

  List<String> _timezoneOptions() {
    final zones = <String>[_localTimezoneLabel(), 'UTC'];
    for (var hour = -12; hour <= 14; hour++) {
      if (hour == 0) continue;
      final sign = hour < 0 ? '-' : '+';
      zones.add('UTC$sign${hour.abs().toString().padLeft(2, '0')}:00');
    }
    return zones;
  }

  String _selectedTimezoneLabel(String? timezone, {required String fallback}) {
    final options = _timezoneOptions();
    if (timezone != null && options.contains(timezone)) return timezone;
    if (options.contains(fallback)) return fallback;
    return options.first;
  }

  String _leftTimezoneLabel() {
    return _selectedTimezoneLabel(
      _leftTimezone,
      fallback: _localTimezoneLabel(),
    );
  }

  String _rightTimezoneLabel() {
    return _selectedTimezoneLabel(_rightTimezone, fallback: 'UTC');
  }

  DateTime _timezoneDate(DateTime utcDate, String timezone) {
    if (timezone == _localTimezoneLabel()) return utcDate.toLocal();
    final offset = _parseTimezoneOffset(timezone) ?? Duration.zero;
    return utcDate.add(offset);
  }

  String _timezoneOffsetLabel(DateTime utcDate, String timezone) {
    if (timezone == _localTimezoneLabel()) {
      final localDate = utcDate.toLocal();
      return '${localDate.timeZoneName} (${_formatUtcOffset(localDate.timeZoneOffset)})';
    }
    return timezone == 'UTC' ? 'UTC+00:00' : timezone;
  }

  Duration? _parseTimezoneOffset(String timezone) {
    if (timezone == 'UTC') return Duration.zero;
    final match = RegExp(r'^UTC([+-])(\d{2}):(\d{2})$').firstMatch(timezone);
    if (match == null) return null;
    final sign = match.group(1) == '-' ? -1 : 1;
    final hours = int.parse(match.group(2)!);
    final minutes = int.parse(match.group(3)!);
    return Duration(minutes: sign * (hours * 60 + minutes));
  }

  _TimezoneDetails? _detailsFor(String timezone) {
    final utcDate = _currentUtcDate;
    if (utcDate == null) return null;
    final selectedDate = _timezoneDate(utcDate, timezone);
    final offset = timezone == _localTimezoneLabel()
        ? selectedDate.timeZoneOffset
        : _parseTimezoneOffset(timezone) ?? Duration.zero;
    return _TimezoneDetails(
      dateTime: _formatDisplayDateTime(selectedDate),
      offset: _timezoneOffsetLabel(utcDate, timezone),
      utcIso: utcDate.toIso8601String(),
      relative: _relativeFromNow(utcDate.toLocal()),
      unixTime: (utcDate.millisecondsSinceEpoch ~/ 1000).toString(),
      unixMilliseconds: utcDate.millisecondsSinceEpoch.toString(),
      unixNanoseconds: (utcDate.microsecondsSinceEpoch * 1000).toString(),
      rfc3339: _formatRfc3339(selectedDate, offset),
      rfc1123: _formatRfc1123(selectedDate, offset),
      dayOfYear: _calcDayOfYear(selectedDate).toString(),
      weekOfYear: _calcWeekOfYear(selectedDate).toString(),
      isLeapYear: _isLeap(selectedDate.year) ? 'Yes' : 'No',
    );
  }

  void _changeLeftTimezone(String timezone) {
    setState(() => _leftTimezone = timezone);
  }

  void _changeRightTimezone(String timezone) {
    setState(() => _rightTimezone = timezone);
  }

  void _convert() {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      _clearOutputs();
      setState(() => _error = null);
      return;
    }
    final value = num.tryParse(raw);
    if (value == null) {
      setState(() => _error = 'Invalid number input.');
      return;
    }
    final date = switch (_format) {
      'Unix time (milliseconds since epoch)' =>
        DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true),
      'Unix time (nanoseconds since epoch)' =>
        DateTime.fromMicrosecondsSinceEpoch(value.round() ~/ 1000, isUtc: true),
      _ => DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).round(),
        isUtc: true,
      ),
    };
    setState(() {
      _currentUtcDate = date;
      _error = null;
    });
  }

  void _clearOutputs() {
    _currentUtcDate = null;
  }

  void _setNow() {
    final now = DateTime.now().toUtc();
    setState(() {
      _input.text = switch (_format) {
        'Unix time (milliseconds since epoch)' =>
          now.millisecondsSinceEpoch.toString(),
        'Unix time (nanoseconds since epoch)' =>
          (now.microsecondsSinceEpoch * 1000).toString(),
        _ => (now.millisecondsSinceEpoch ~/ 1000).toString(),
      };
      _currentUtcDate = now;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final timezoneOptions = _timezoneOptions();
    final leftTimezone = _leftTimezoneLabel();
    final rightTimezone = _rightTimezoneLabel();
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Input:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                ToolButton(label: 'Now', onPressed: _setNow),
                SmallDropdown(
                  items: const [
                    'Unix time (seconds since epoch)',
                    'Unix time (milliseconds since epoch)',
                    'Unix time (nanoseconds since epoch)',
                  ],
                  initialValue: _format,
                  onChanged: (value) {
                    setState(() => _format = value);
                    _convert();
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              decoration: _toolSurfaceDecoration(context, radius: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              constraints: const BoxConstraints(minHeight: 34),
              child: TextField(
                key: const ValueKey('unix-time-input'),
                controller: _input,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintStyle: TextStyle(color: appColors.mutedText),
                ),
                style: TextStyle(color: appColors.editorText),
                onChanged: (_) => _convert(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tips: Mathematical operators + - * / are supported',
              style: _mutedToolTextStyle(context, fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: _errorToolTextStyle(context)),
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final leftPanel = _TimezoneDetailsPanel(
                  title: 'Timezone 1',
                  timezoneOptions: timezoneOptions,
                  selectedTimezone: leftTimezone,
                  onTimezoneChanged: _changeLeftTimezone,
                  details: _detailsFor(leftTimezone),
                );
                final rightPanel = _TimezoneDetailsPanel(
                  title: 'Timezone 2',
                  timezoneOptions: timezoneOptions,
                  selectedTimezone: rightTimezone,
                  onTimezoneChanged: _changeRightTimezone,
                  details: _detailsFor(rightTimezone),
                );
                const gap = 10.0;
                const minPanelWidth = 330.0;
                final availableWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : minPanelWidth * 2 + gap;
                final comparisonWidth = max(
                  availableWidth,
                  minPanelWidth * 2 + gap,
                );
                final panelWidth = (comparisonWidth - gap) / 2;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: comparisonWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: panelWidth, child: leftPanel),
                        const SizedBox(width: gap),
                        SizedBox(width: panelWidth, child: rightPanel),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TimezoneDetails {
  const _TimezoneDetails({
    required this.dateTime,
    required this.offset,
    required this.utcIso,
    required this.relative,
    required this.unixTime,
    required this.unixMilliseconds,
    required this.unixNanoseconds,
    required this.rfc3339,
    required this.rfc1123,
    required this.dayOfYear,
    required this.weekOfYear,
    required this.isLeapYear,
  });

  final String dateTime;
  final String offset;
  final String utcIso;
  final String relative;
  final String unixTime;
  final String unixMilliseconds;
  final String unixNanoseconds;
  final String rfc3339;
  final String rfc1123;
  final String dayOfYear;
  final String weekOfYear;
  final String isLeapYear;
}

class _TimezoneDetailsPanel extends StatelessWidget {
  const _TimezoneDetailsPanel({
    required this.title,
    required this.timezoneOptions,
    required this.selectedTimezone,
    required this.onTimezoneChanged,
    required this.details,
  });

  final String title;
  final List<String> timezoneOptions;
  final String selectedTimezone;
  final ValueChanged<String> onTimezoneChanged;
  final _TimezoneDetails? details;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final details = this.details;
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 8),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final dropdownWidth = min(
                190.0,
                max(132.0, constraints.maxWidth - 102.0),
              );
              return Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: appColors.editorText,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SmallDropdown(
                        items: timezoneOptions,
                        initialValue: selectedTimezone,
                        width: dropdownWidth,
                        onChanged: onTimezoneChanged,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (details == null)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 300),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: appColors.editorBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: appColors.border),
              ),
              child: Text(
                'Enter a Unix time or press Now',
                style: _mutedToolTextStyle(context),
              ),
            )
          else ...[
            _UnixDetailRow(label: 'Date/time', value: details.dateTime),
            _UnixDetailRow(label: 'Offset', value: details.offset),
            _UnixDetailRow(label: 'UTC ISO', value: details.utcIso),
            _UnixDetailRow(label: 'Relative', value: details.relative),
            _UnixDetailRow(label: 'Unix sec', value: details.unixTime),
            _UnixDetailRow(label: 'Unix ms', value: details.unixMilliseconds),
            _UnixDetailRow(label: 'Unix ns', value: details.unixNanoseconds),
            _UnixDetailRow(label: 'RFC 3339', value: details.rfc3339),
            _UnixDetailRow(label: 'RFC 1123', value: details.rfc1123),
            Row(
              children: [
                Expanded(
                  child: _UnixDetailRow(
                    label: 'Day',
                    value: details.dayOfYear,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _UnixDetailRow(
                    label: 'Week',
                    value: details.weekOfYear,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _UnixDetailRow(
                    label: 'Leap',
                    value: details.isLeapYear,
                    compact: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UnixDetailRow extends StatelessWidget {
  const _UnixDetailRow({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: appColors.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                _UnixDetailValue(value: value, minHeight: 38),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: appColors.mutedText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _UnixDetailValue(value: value)),
              ],
            ),
    );
  }
}

class _UnixDetailValue extends StatelessWidget {
  const _UnixDetailValue({required this.value, this.minHeight = 36});

  final String value;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: appColors.editorBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: SelectableText(
        value,
        maxLines: 1,
        style: TextStyle(
          color: appColors.editorText,
          fontFamily: 'Menlo',
          fontSize: 12,
        ),
      ),
    );
  }
}

bool _isLeap(int year) {
  if (year % 400 == 0) return true;
  if (year % 100 == 0) return false;
  return year % 4 == 0;
}

String _formatUtcOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final hours = absolute.inHours.toString().padLeft(2, '0');
  final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$minutes';
}

String _formatDisplayDateTime(DateTime date) {
  final buffer = StringBuffer()
    ..write(date.year.toString().padLeft(4, '0'))
    ..write('-')
    ..write(date.month.toString().padLeft(2, '0'))
    ..write('-')
    ..write(date.day.toString().padLeft(2, '0'))
    ..write(' ')
    ..write(date.hour.toString().padLeft(2, '0'))
    ..write(':')
    ..write(date.minute.toString().padLeft(2, '0'))
    ..write(':')
    ..write(date.second.toString().padLeft(2, '0'));
  if (date.millisecond != 0 || date.microsecond != 0) {
    buffer.write('.');
    buffer.write(date.millisecond.toString().padLeft(3, '0'));
    if (date.microsecond != 0) {
      buffer.write(date.microsecond.toString().padLeft(3, '0'));
    }
  }
  return buffer.toString();
}

String _formatRfc3339(DateTime date, Duration offset) {
  final base = _formatDisplayDateTime(date).replaceFirst(' ', 'T');
  return '$base${_formatUtcOffset(offset).replaceFirst('UTC', '')}';
}

String _formatRfc1123(DateTime date, Duration offset) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final offsetText = _formatUtcOffset(offset).replaceFirst('UTC', '');
  return '${weekdays[date.weekday - 1]}, '
      '${date.day.toString().padLeft(2, '0')} '
      '${months[date.month - 1]} '
      '${date.year.toString().padLeft(4, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}:'
      '${date.second.toString().padLeft(2, '0')} '
      '${offsetText.replaceAll(':', '')}';
}

int _calcDayOfYear(DateTime date) {
  final start = DateTime(date.year, 1, 1);
  return date.difference(start).inDays + 1;
}

int _calcWeekOfYear(DateTime date) {
  final dayOfYear = _calcDayOfYear(date);
  return ((dayOfYear - date.weekday + 10) / 7).floor();
}

class _MimeTypesView extends StatefulWidget {
  const _MimeTypesView();

  @override
  State<_MimeTypesView> createState() => _MimeTypesViewState();
}

class _MimeTypesViewState extends State<_MimeTypesView> {
  final TextEditingController _search = TextEditingController();
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MimeTypeEntry> _filteredEntries() {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return List<MimeTypeEntry>.from(mimeTypeEntries);
    }
    return mimeTypeEntries.where((entry) {
      return entry.name.toLowerCase().contains(query) ||
          entry.mimeType.toLowerCase().contains(query) ||
          entry.extension.toLowerCase().contains(query) ||
          entry.details.toLowerCase().contains(query);
    }).toList();
  }

  int _compareEntries(MimeTypeEntry a, MimeTypeEntry b, int column) {
    String left;
    String right;
    switch (column) {
      case 1:
        left = a.mimeType;
        right = b.mimeType;
        break;
      case 2:
        left = a.extension;
        right = b.extension;
        break;
      case 3:
        left = a.details;
        right = b.details;
        break;
      case 0:
      default:
        left = a.name;
        right = b.name;
        break;
    }
    return left.toLowerCase().compareTo(right.toLowerCase());
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final entries = _filteredEntries();
    entries.sort((a, b) {
      final result = _compareEntries(a, b, _sortColumnIndex);
      return _sortAscending ? result : -result;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search name, type, extension, details...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${entries.length} entries',
              style: _mutedToolTextStyle(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: _toolSurfaceDecoration(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    sortAscending: _sortAscending,
                    sortColumnIndex: _sortColumnIndex,
                    headingRowColor: WidgetStateProperty.all(
                      appColors.panelHeader,
                    ),
                    columnSpacing: 24,
                    columns: [
                      DataColumn(label: const Text('Name'), onSort: _onSort),
                      DataColumn(
                        label: const Text('MIME Type / Internet Media Type'),
                        onSort: _onSort,
                      ),
                      DataColumn(
                        label: const Text('File Extension'),
                        onSort: _onSort,
                      ),
                      DataColumn(
                        label: const Text('More Details'),
                        onSort: _onSort,
                      ),
                    ],
                    rows: entries
                        .map(
                          (entry) => DataRow(
                            cells: [
                              DataCell(Text(entry.name)),
                              DataCell(SelectableText(entry.mimeType)),
                              DataCell(Text(entry.extension)),
                              DataCell(Text(entry.details)),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _relativeFromNow(DateTime date) {
  final now = DateTime.now();
  final diff = date.difference(now);
  final seconds = diff.inSeconds.abs();
  final minutes = diff.inMinutes.abs();
  final hours = diff.inHours.abs();
  String value;
  if (seconds < 60) {
    value = '$seconds seconds';
  } else if (minutes < 60) {
    value = '$minutes minutes';
  } else {
    value = '$hours hours';
  }
  return diff.isNegative ? '$value ago' : 'in $value';
}

Widget buildUnixTimeConverter() {
  return const _UnixTimeConverterView();
}

Widget buildJsonFormatValidate({
  JsonToolSession? session,
  JsonPanelCompareDetails? compare,
}) {
  return _JsonFormatValidateView(session: session, compare: compare);
}

Widget buildBase64String() {
  return const _Base64StringView();
}

Widget buildBase64Image() {
  return const _Base64ImageView();
}

Widget buildJwtDebugger() {
  return const _JwtDebuggerView();
}

Widget buildRegExpTester() {
  return const _RegExpTesterView();
}

Widget buildUrlEncodeDecode() {
  return const _UrlEncodeDecodeView();
}

Widget buildUrlParser() {
  return const _UrlParserView();
}

Widget buildSubdomainFinder() {
  return const _SubdomainFinderView();
}

Widget buildSubdomainTakeover() {
  return const _SubdomainTakeoverView();
}

Widget buildPortScanner() {
  return const _PortScannerView();
}

Widget buildNetworkScanner() {
  return const _NetworkScannerView();
}

Widget buildFirewallFingerprint() {
  return const _FirewallFingerprintView();
}

Widget buildHtmlEntityEncodeDecode() {
  return const _HtmlEntityView();
}

Widget buildBackslashEscapeUnescape() {
  return const _BackslashEscapeView();
}

Widget buildUuidUlid() {
  return const _UuidUlidView();
}

Widget buildHtmlPreview() {
  return const _HtmlPreviewView();
}

Widget buildTextDiffChecker() {
  return const _TextDiffView();
}

Widget buildYamlToJson() {
  return const _YamlToJsonView();
}

Widget buildJsonToYaml() {
  return const _JsonToYamlView();
}

Widget buildYamlJsonConverter() {
  return const _YamlJsonConverterView();
}

Widget buildNumberBaseConverter() {
  return const _NumberBaseConverterView();
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
    return const _MarkupBeautifyMinifyView(
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

Widget buildXmlBeautifyMinify() {
  return const _MarkupBeautifyMinifyView(
    language: 'XML',
    beautify: _beautifyXml,
    minify: _minifyXml,
    showComments: true,
  );
}

Widget buildLoremIpsum() {
  return const _LoremIpsumView();
}

Widget buildQrCode() {
  return const _QrCodeView();
}

Widget buildStringInspector() {
  return const _StringInspectorView();
}

Widget buildMimeTypes() {
  return const _MimeTypesView();
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

Widget buildHashGenerator() {
  return const _HashGeneratorView();
}

Widget buildTextEncryption() {
  return const _TextEncryptionView();
}

Widget buildPayloadEmbedder() {
  return const _PayloadEmbedderView();
}

Widget buildUserAgentTool() {
  return const _UserAgentToolView();
}

Widget buildAntiBotDetection() {
  return const _AntiBotDetectorView();
}

Widget buildOfflineLlm() {
  return const _OfflineLlmView();
}

Widget buildHtmlToJsx() {
  return const _HtmlToJsxView();
}

Widget buildJsToTsConverter() {
  return const _JsToTsConverterView();
}

Widget buildMarkdownPreview() {
  return const _MarkdownPreviewView();
}

Widget buildSqlFormatter() {
  return const _SqlFormatterView();
}

Widget buildStringCaseConverter() {
  return const _StringCaseConverterView();
}

Widget buildCronJobParser() {
  return const _CronJobParserView();
}

Widget buildColorConverter() {
  return const _ColorConverterView();
}

Widget buildPhpTool(String title) {
  return _PhpSerializerView(serialize: !title.toLowerCase().contains('unserial'));
}

class _LocalServerView extends StatefulWidget {
  const _LocalServerView();

  @override
  State<_LocalServerView> createState() => _LocalServerViewState();
}

class _LocalServerViewState extends State<_LocalServerView> {
  final LocalServerService _service = LocalServerService();
  final TextEditingController _port = TextEditingController(text: '8080');
  final ScrollController _logScroll = ScrollController();
  final List<ServerLogEntry> _logs = [];
  static const int _maxLogs = 1000;
  String? _folder;
  bool _localOnly = true;
  bool _running = false;
  String? _error;

  @override
  void dispose() {
    _service.stop();
    _port.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final path = await FileDialogService.openDirectory();
    if (path == null || !mounted) return;
    setState(() => _folder = path);
  }

  Future<void> _toggle() async {
    if (_running) {
      await _service.stop();
      if (!mounted) return;
      setState(() => _running = false);
    } else {
      final folder = _folder;
      if (folder == null) {
        setState(() => _error = 'Choose a folder to serve first.');
        return;
      }
      final port = int.tryParse(_port.text.trim());
      if (port == null || port < 1 || port > 65535) {
        setState(() => _error = 'Enter a valid port (1–65535).');
        return;
      }
      try {
        await _service.start(
          root: folder,
          port: port,
          localOnly: _localOnly,
          onLog: _onLog,
        );
        if (!mounted) return;
        setState(() {
          _running = true;
          _error = null;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = _friendlyServerError(error, port));
      }
    }
  }

  void _onLog(ServerLogEntry entry) {
    if (!mounted) return;
    final atBottom = !_logScroll.hasClients ||
        _logScroll.position.pixels >= _logScroll.position.maxScrollExtent - 40;
    setState(() {
      _logs.add(entry);
      if (_logs.length > _maxLogs) {
        _logs.removeRange(0, _logs.length - _maxLogs);
      }
    });
    if (atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) {
          _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        }
      });
    }
  }

  String _friendlyServerError(Object error, int port) {
    if (error is SocketException) {
      final message = error.osError?.message ?? error.message;
      return 'Could not start server on port $port: $message';
    }
    return 'Could not start server: $error';
  }

  String get _url => 'http://localhost:${_port.text.trim()}/';

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: _toolSurfaceDecoration(context),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined, size: 16, color: appColors.mutedText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _folder ?? 'No folder selected',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 12,
                        color: _folder == null
                            ? appColors.mutedText
                            : appColors.editorText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToolButton(
                    label: 'Choose Folder',
                    icon: Icons.folder_open,
                    onPressed: _running ? null : _pickFolder,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Port', style: TextStyle(color: appColors.mutedText)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _port,
                      enabled: !_running,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CompactCheck(
                    label: 'Local only',
                    value: _localOnly,
                    onChanged: _running
                        ? (_) {}
                        : (value) => setState(() => _localOnly = value),
                  ),
                  const Spacer(),
                  ToolButton(
                    label: _running ? 'Stop' : 'Start',
                    icon: _running ? Icons.stop : Icons.play_arrow,
                    onPressed: _toggle,
                  ),
                ],
              ),
              if (_running) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.circle, size: 9, color: appColors.success),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Serving at $_url',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 12,
                          color: appColors.editorText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ToolIconButton(
                      icon: Icons.copy,
                      tooltip: 'Copy URL',
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _url)),
                    ),
                    Text(
                      _localOnly ? 'local only' : 'network accessible',
                      style: TextStyle(
                        fontSize: 11,
                        color: _localOnly ? appColors.mutedText : appColors.warning,
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: _errorToolTextStyle(context, fontSize: 12)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Access log',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: appColors.editorText,
              ),
            ),
            const SizedBox(width: 6),
            Text('(${_logs.length})',
                style: TextStyle(color: appColors.mutedText, fontSize: 12)),
            const Spacer(),
            if (_logs.isNotEmpty)
              ToolButton(
                label: 'Clear log',
                onPressed: () => setState(_logs.clear),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: _toolSurfaceDecoration(context),
            child: _logs.isEmpty
                ? Center(
                    child: Text(
                      _running
                          ? 'Waiting for requests…'
                          : 'Start the server to see access logs here.',
                      style: _mutedToolTextStyle(context),
                    ),
                  )
                : ListView.builder(
                    controller: _logScroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) =>
                        _ServerLogRow(entry: _logs[index]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ServerLogRow extends StatelessWidget {
  const _ServerLogRow({required this.entry});

  final ServerLogEntry entry;

  String _two(int v) => v.toString().padLeft(2, '0');

  String get _time =>
      '${_two(entry.time.hour)}:${_two(entry.time.minute)}:${_two(entry.time.second)}';

  String get _size {
    if (entry.bytes < 1024) return '${entry.bytes} B';
    if (entry.bytes < 1024 * 1024) {
      return '${(entry.bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(entry.bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final Color statusColor;
    if (entry.status < 300) {
      statusColor = appColors.success;
    } else if (entry.status < 400) {
      statusColor = appColors.accent;
    } else if (entry.status < 500) {
      statusColor = appColors.warning;
    } else {
      statusColor = appColors.error;
    }
    final style = TextStyle(fontFamily: 'Menlo', fontSize: 12, color: appColors.editorText);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_time, style: TextStyle(fontFamily: 'Menlo', fontSize: 12, color: appColors.mutedText)),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(entry.status.toString(),
                style: style.copyWith(color: statusColor, fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            width: 48,
            child: Text(entry.method, style: style.copyWith(color: appColors.mutedText)),
          ),
          Expanded(
            child: Text(entry.path, style: style, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 10),
          Text(_size, style: style.copyWith(color: appColors.mutedText)),
          const SizedBox(width: 10),
          Text(entry.client, style: style.copyWith(color: appColors.mutedText)),
        ],
      ),
    );
  }
}

Widget buildPhpToJs() {
  return const _PhpToJsView();
}

Widget buildLocalServer() {
  return const _LocalServerView();
}

Widget buildRandomStringGenerator() {
  return const _RandomStringGeneratorView();
}

Widget buildSvgToCss() {
  return const _SvgToCssView();
}

Widget buildCurlToCode() {
  return const _CurlToCodeView();
}

Widget buildJsonToCode() {
  return const _JsonToCodeView();
}

Widget buildCertificateDecoder() {
  return const _CertificateDecoderView();
}

Widget buildAuthTotp() {
  return const _AuthTotpView();
}

Widget buildHexToAscii() {
  return const _HexToAsciiView();
}

Widget buildAsciiToHex() {
  return const _AsciiToHexView();
}

Widget buildHexAsciiConverter() {
  return const _HexAsciiConverterView();
}

Widget buildLineSortDedupe() {
  return const _LineSortDedupeView();
}

Widget buildPreferences() {
  return const _PreferencesView();
}

Widget buildPreferencesGeneral() {
  return const _PreferencesGeneralView();
}

Widget buildPreferencesAppearance() {
  return const _PreferencesAppearanceView();
}

Widget buildPreferencesScripting() {
  return const _PreferencesScriptingView();
}

class _PrefCheckbox extends StatelessWidget {
  const _PrefCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: onChanged),
          Expanded(child: Text(label, softWrap: true)),
        ],
      ),
    );
  }
}

class _PreferencesView extends StatefulWidget {
  const _PreferencesView();

  @override
  State<_PreferencesView> createState() => _PreferencesViewState();
}

class _PreferencesViewState extends State<_PreferencesView> {
  static const _tabs = ['General', 'Appearance', 'Scripting'];

  String _selectedTab = _tabs.first;
  bool _hideOnLaunch = false;
  bool _confirmQuit = false;
  bool _shareAnalytics = false;
  bool _writeLogs = false;
  bool _showStatusBar = true;
  bool _showDock = true;
  String _theme = 'System';
  String _colorTheme = 'Classic Blue';
  int _scriptSegment = 0;
  String _phpPath = 'No Usable PHP Runtime';
  final TextEditingController _whitelist = TextEditingController(
    text: 'serialize,var_export,json_encode,json_decode,unserialize',
  );
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hideOnLaunch = prefs.getBool('pref_hide_on_launch') ?? false;
      _confirmQuit = prefs.getBool('pref_confirm_quit') ?? false;
      _shareAnalytics = prefs.getBool('pref_share_analytics') ?? false;
      _writeLogs = prefs.getBool('pref_write_logs') ?? false;
      _showStatusBar = prefs.getBool('pref_show_status_bar') ?? true;
      _showDock = prefs.getBool('pref_show_dock') ?? true;
      _theme = prefs.getString('pref_theme') ?? 'System';
      _colorTheme = prefs.getString('colorTheme') ?? 'Classic Blue';
      _scriptSegment = prefs.getInt('pref_script_segment') ?? 0;
      _phpPath = prefs.getString('pref_php_path') ?? 'No Usable PHP Runtime';
      _whitelist.text =
          prefs.getString('pref_php_whitelist') ??
          'serialize,var_export,json_encode,json_decode,unserialize';
      _loaded = true;
    });
  }

  Future<void> _setPref(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  void _applyAppearance() {
    AppAppearanceService.apply(
      showStatusBar: _showStatusBar,
      showDock: _showDock,
    );
  }

  @override
  void dispose() {
    _whitelist.dispose();
    super.dispose();
  }

  Widget _buildGeneral() {
    return _PreferenceSection(
      title: 'General',
      children: [
        _PrefCheckbox(
          label: 'Hide the main window at launch',
          value: _hideOnLaunch,
          onChanged: (value) {
            setState(() => _hideOnLaunch = value ?? false);
            _setPref('pref_hide_on_launch', _hideOnLaunch);
          },
        ),
        _PrefCheckbox(
          label: 'Confirm before quitting with Cmd+Q',
          value: _confirmQuit,
          onChanged: (value) {
            setState(() => _confirmQuit = value ?? false);
            _setPref('pref_confirm_quit', _confirmQuit);
          },
        ),
        _PrefCheckbox(
          label: 'Share anonymous crash reports and analytics',
          value: _shareAnalytics,
          onChanged: (value) {
            setState(() => _shareAnalytics = value ?? false);
            _setPref('pref_share_analytics', _shareAnalytics);
          },
        ),
        _PrefCheckbox(
          label: 'Write debug logs',
          value: _writeLogs,
          onChanged: (value) {
            setState(() => _writeLogs = value ?? false);
            _setPref('pref_write_logs', _writeLogs);
          },
        ),
      ],
    );
  }

  Widget _buildAppearance() {
    final state = ToolStateScope.maybeOf(context);
    Widget colorThemePicker(String selectedTheme) {
      return _ColorThemePicker(
        selectedTheme: selectedTheme,
        onChanged: (value) {
          setState(() => _colorTheme = value);
          state?.colorTheme.value = value;
          _setPref('colorTheme', value);
        },
      );
    }

    return _PreferenceSection(
      title: 'Appearance',
      children: [
        _PrefCheckbox(
          label: 'Show status bar icon',
          value: _showStatusBar,
          // When the Dock icon is hidden the app is menu-bar-only, so the
          // status bar icon must stay on; the box is locked on in that case.
          onChanged: _showDock
              ? (value) {
                  setState(() => _showStatusBar = value ?? true);
                  _setPref('pref_show_status_bar', _showStatusBar);
                  _applyAppearance();
                }
              : null,
        ),
        _PrefCheckbox(
          label: 'Show Dock icon',
          value: _showDock,
          onChanged: (value) {
            final next = value ?? true;
            setState(() {
              _showDock = next;
              if (!next) _showStatusBar = true;
            });
            _setPref('pref_show_dock', _showDock);
            if (!next) _setPref('pref_show_status_bar', true);
            _applyAppearance();
          },
        ),
        const SizedBox(height: 8),
        _PreferenceSelectRow(
          label: 'Mode',
          child: SmallDropdown(
            items: const ['System', 'Light', 'Dark'],
            initialValue: _theme,
            onChanged: (value) {
              setState(() => _theme = value);
              _setPref('pref_theme', _theme);
              if (value == 'Light') state?.darkMode.value = false;
              if (value == 'Dark') state?.darkMode.value = true;
            },
          ),
        ),
        const SizedBox(height: 14),
        if (state == null)
          colorThemePicker(_colorTheme)
        else
          ValueListenableBuilder<String>(
            valueListenable: state.colorTheme,
            builder: (context, selectedTheme, _) {
              return colorThemePicker(selectedTheme);
            },
          ),
      ],
    );
  }

  Widget _buildScripting() {
    return _PreferenceSection(
      title: 'Scripting',
      children: [
        ToggleButtons(
          isSelected: List<bool>.generate(3, (i) => i == _scriptSegment),
          onPressed: (index) {
            setState(() => _scriptSegment = index);
            _setPref('pref_script_segment', _scriptSegment);
          },
          borderRadius: BorderRadius.circular(6),
          constraints: const BoxConstraints(minHeight: 32, minWidth: 86),
          children: const [Text('PHP'), Text('OpenSSL'), Text('Other')],
        ),
        const SizedBox(height: 16),
        _PreferenceReadonlyField(label: 'Runtime', value: _phpPath),
        const SizedBox(height: 14),
        Text(
          'Allowed PHP functions',
          style: TextStyle(
            color: context.appColors.editorText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 116,
          decoration: _toolSurfaceDecoration(context),
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _whitelist,
            maxLines: null,
            expands: true,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'serialize,var_export,json_encode,json_decode',
              hintStyle: TextStyle(color: context.appColors.mutedText),
            ),
            style: TextStyle(color: context.appColors.editorText),
            onChanged: (value) => _setPref('pref_php_whitelist', value),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final body = switch (_selectedTab) {
      'Appearance' => _buildAppearance(),
      'Scripting' => _buildScripting(),
      _ => _buildGeneral(),
    };

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ToggleButtons(
              isSelected: _tabs.map((tab) => tab == _selectedTab).toList(),
              onPressed: (index) => setState(() => _selectedTab = _tabs[index]),
              borderRadius: BorderRadius.circular(6),
              constraints: const BoxConstraints(minHeight: 34, minWidth: 112),
              children: _tabs.map(Text.new).toList(),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.appColors.editorText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _PreferenceSelectRow extends StatelessWidget {
  const _PreferenceSelectRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 36),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ColorThemePicker extends StatelessWidget {
  const _ColorThemePicker({
    required this.selectedTheme,
    required this.onChanged,
  });

  final String selectedTheme;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreferenceSelectRow(
          label: 'Color theme',
          child: SmallDropdown(
            items: AppColors.colorThemeNames,
            initialValue: selectedTheme,
            width: 170,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 146),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final theme in AppColors.colorThemes)
                _ColorThemeSwatchButton(
                  theme: theme,
                  selected: theme.name == selectedTheme,
                  onTap: () => onChanged(theme.name),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 146),
          child: Text(
            'Applies to accents, selection, hover states, and focused controls.',
            style: TextStyle(color: appColors.mutedText, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ColorThemeSwatchButton extends StatelessWidget {
  const _ColorThemeSwatchButton({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AppColorThemeChoice theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Semantics(
      button: true,
      selected: selected,
      label: theme.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 122,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? appColors.selected : appColors.panelElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? appColors.accent : appColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              _ThemeDot(color: theme.darkAccent),
              const SizedBox(width: 4),
              _ThemeDot(color: theme.lightAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  theme.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: appColors.editorText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeDot extends StatelessWidget {
  const _ThemeDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.appColors.border),
      ),
    );
  }
}

class _PreferenceReadonlyField extends StatelessWidget {
  const _PreferenceReadonlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: Container(
            decoration: _toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              value,
              style: TextStyle(
                color: context.appColors.editorText,
                fontFamily: 'Menlo',
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreferencesGeneralView extends StatefulWidget {
  const _PreferencesGeneralView();

  @override
  State<_PreferencesGeneralView> createState() =>
      _PreferencesGeneralViewState();
}

class _PreferencesGeneralViewState extends State<_PreferencesGeneralView> {
  bool _hideOnLaunch = false;
  bool _confirmQuit = false;
  bool _shareAnalytics = false;
  bool _writeLogs = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hideOnLaunch = prefs.getBool('pref_hide_on_launch') ?? false;
        _confirmQuit = prefs.getBool('pref_confirm_quit') ?? false;
        _shareAnalytics = prefs.getBool('pref_share_analytics') ?? false;
        _writeLogs = prefs.getBool('pref_write_logs') ?? false;
        _loaded = true;
      });
    });
  }

  Future<void> _setPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _PreferencesShell(
      selectedLabel: 'General',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PrefCheckbox(
            label: 'Always hide the main window at launch',
            value: _hideOnLaunch,
            onChanged: (value) {
              setState(() => _hideOnLaunch = value ?? false);
              _setPref('pref_hide_on_launch', _hideOnLaunch);
            },
          ),
          _PrefCheckbox(
            label: 'Ask to confirm when quitting with Cmd+Q',
            value: _confirmQuit,
            onChanged: (value) {
              setState(() => _confirmQuit = value ?? false);
              _setPref('pref_confirm_quit', _confirmQuit);
            },
          ),
          _PrefCheckbox(
            label: 'Share anonymous crash reports and analytics',
            value: _shareAnalytics,
            onChanged: (value) {
              setState(() => _shareAnalytics = value ?? false);
              _setPref('pref_share_analytics', _shareAnalytics);
            },
          ),
          Row(
            children: [
              Expanded(
                child: _PrefCheckbox(
                  label: 'Write debug logs',
                  value: _writeLogs,
                  onChanged: (value) {
                    setState(() => _writeLogs = value ?? false);
                    _setPref('pref_write_logs', _writeLogs);
                  },
                ),
              ),
              const ToolButton(label: 'Open logs directory'),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Text('Stored preferences location'),
              SizedBox(width: 8),
              ToolButton(label: 'Open'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreferencesAppearanceView extends StatefulWidget {
  const _PreferencesAppearanceView();

  @override
  State<_PreferencesAppearanceView> createState() =>
      _PreferencesAppearanceViewState();
}

class _PreferencesAppearanceViewState
    extends State<_PreferencesAppearanceView> {
  bool _showStatusBar = true;
  bool _showDock = true;
  String _theme = 'System';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _showStatusBar = prefs.getBool('pref_show_status_bar') ?? true;
        _showDock = prefs.getBool('pref_show_dock') ?? true;
        _theme = prefs.getString('pref_theme') ?? 'System';
        _loaded = true;
      });
    });
  }

  Future<void> _setPref(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _PreferencesShell(
      selectedLabel: 'Appearance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PrefCheckbox(
            label: 'Show Status Bar icon',
            value: _showStatusBar,
            onChanged: (value) {
              setState(() => _showStatusBar = value ?? true);
              _setPref('pref_show_status_bar', _showStatusBar);
            },
          ),
          _PrefCheckbox(
            label: 'Show Dock icon',
            value: _showDock,
            onChanged: (value) {
              setState(() => _showDock = value ?? true);
              _setPref('pref_show_dock', _showDock);
            },
          ),
          Row(
            children: [
              const Text('Theme'),
              const SizedBox(width: 12),
              SmallDropdown(
                items: const ['System', 'Light', 'Dark'],
                initialValue: _theme,
                onChanged: (value) {
                  setState(() => _theme = value);
                  _setPref('pref_theme', _theme);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreferencesScriptingView extends StatefulWidget {
  const _PreferencesScriptingView();

  @override
  State<_PreferencesScriptingView> createState() =>
      _PreferencesScriptingViewState();
}

class _PreferencesScriptingViewState extends State<_PreferencesScriptingView> {
  int _segment = 0;
  String _phpPath = 'No Usable PHP Runtime';
  final TextEditingController _whitelist = TextEditingController(
    text: 'serialize,var_export,json_encode,json_decode,unserialize',
  );
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _segment = prefs.getInt('pref_script_segment') ?? 0;
        _phpPath = prefs.getString('pref_php_path') ?? 'No Usable PHP Runtime';
        _whitelist.text =
            prefs.getString('pref_php_whitelist') ??
            'serialize,var_export,json_encode,json_decode,unserialize';
        _loaded = true;
      });
    });
  }

  Future<void> _setPref(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  void dispose() {
    _whitelist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return _PreferencesShell(
      selectedLabel: 'Scripting',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToggleButtons(
            isSelected: List<bool>.generate(3, (i) => i == _segment),
            onPressed: (index) {
              setState(() => _segment = index);
              _setPref('pref_script_segment', _segment);
            },
            borderRadius: BorderRadius.circular(6),
            constraints: const BoxConstraints(minHeight: 32, minWidth: 80),
            children: const [Text('PHP'), Text('Open SSL'), Text('Others')],
          ),
          const SizedBox(height: 16),
          const Text('Default command path:'),
          const SizedBox(height: 8),
          SmallDropdown(
            items: [_phpPath],
            initialValue: _phpPath,
            onChanged: (value) => setState(() => _phpPath = value),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              ToolButton(label: 'Add New Path...'),
              SizedBox(width: 12),
              ToolButton(label: 'Remove'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'PHP code is run in safe mode with only whitelisted functions below allowed.',
          ),
          const SizedBox(height: 8),
          Container(
            height: 100,
            decoration: _toolSurfaceDecoration(context),
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _whitelist,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText:
                    'serialize,var_export,json_encode,json_decode,unserialize',
              ),
              style: TextStyle(color: context.appColors.editorText),
              onChanged: (value) => _setPref('pref_php_whitelist', value),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferencesShell extends StatelessWidget {
  const _PreferencesShell({required this.child, required this.selectedLabel});

  final Widget child;
  final String selectedLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PrefTab(label: 'General', selected: selectedLabel == 'General'),
            _PrefTab(label: 'Hotkeys', selected: selectedLabel == 'Hotkeys'),
            _PrefTab(
              label: 'Appearance',
              selected: selectedLabel == 'Appearance',
            ),
            _PrefTab(
              label: 'Integrations',
              selected: selectedLabel == 'Integrations',
            ),
            _PrefTab(
              label: 'Scripting',
              selected: selectedLabel == 'Scripting',
            ),
            _PrefTab(label: 'Updates', selected: selectedLabel == 'Updates'),
            _PrefTab(label: 'License', selected: selectedLabel == 'License'),
          ],
        ),
        const Divider(height: 24),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _PrefTab extends StatelessWidget {
  const _PrefTab({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Icon(
            Icons.settings,
            size: 24,
            color: selected ? appColors.accent : appColors.mutedText,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: selected ? appColors.accent : appColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineTextField extends StatelessWidget {
  const _InlineTextField({
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
        decoration: _toolSurfaceDecoration(context, radius: 6),
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

class _HashField extends StatelessWidget {
  const _HashField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.onUse,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text('$label:')),
          Expanded(
            child: Container(
              decoration: _toolSurfaceDecoration(context, radius: 6),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      6,
                      onUse == null ? 46 : 104,
                      6,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        value,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 11.5,
                          color: context.appColors.editorText,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onUse != null)
                          TextButton(
                            onPressed: value.isEmpty ? null : onUse,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              minimumSize: const Size(0, 22),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(fontSize: 10.5),
                            ),
                            child: const Text('Lookup'),
                          ),
                        TextButton(
                          onPressed: value.isEmpty ? null : onCopy,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            minimumSize: const Size(0, 22),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 10.5),
                          ),
                          child: const Text('Copy'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HashLookupTextField extends StatelessWidget {
  const _HashLookupTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.minLines,
    required this.maxLines,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      decoration: _toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          isDense: true,
          hintStyle: TextStyle(color: appColors.mutedText),
        ),
        style: TextStyle(
          color: appColors.editorText,
          fontFamily: 'Menlo',
          fontSize: 12.5,
        ),
      ),
    );
  }
}
