/// JSON format/validate tool view.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../services/json_operations_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

class JsonPanelCompareDetails {
  const JsonPanelCompareDetails({
    required this.summary,
    required this.changedLines,
  });

  final JsonCompareSummary summary;
  final Set<int> changedLines;
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

  void _setOperation(JsonOperation value) {
    setState(() => _session.operation = value);
    _session.format();
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
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Text('Operation', style: TextStyle(fontSize: 12)),
              SmallDropdown(
                items: JsonOperation.values.map((item) => item.label).toList(),
                initialValue: _session.operation.label,
                onChanged: (label) => _setOperation(
                  JsonOperation.values.firstWhere(
                    (item) => item.label == label,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: JsonSplitEditors(
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
          decoration: toolSurfaceDecoration(context),
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

class _JsonCompareStrip extends StatelessWidget {
  const _JsonCompareStrip({required this.compare});

  final JsonPanelCompareDetails compare;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
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
          const Text('Compare', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text(compare.summary.label),
        ],
      ),
    );
  }
}

Widget buildJsonFormatValidate({
  JsonToolSession? session,
  JsonPanelCompareDetails? compare,
}) {
  return _JsonFormatValidateView(session: session, compare: compare);
}
