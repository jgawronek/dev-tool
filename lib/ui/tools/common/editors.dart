/// Shared split-editor layouts used by multi-pane tools.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../../../services/file_dialog_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import 'shared.dart';

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
  final liveInputChanged = onInputChanged ?? goActionChanged(inputActions);
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
    input = FileDropTargetRegion(
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
  return ResizableSplit(horizontal: horizontal, first: input, second: output);
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

class ResizableSplit extends StatefulWidget {
  const ResizableSplit({
    super.key,
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
  State<ResizableSplit> createState() => ResizableSplitState();
}

class ResizableSplitState extends State<ResizableSplit> {
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
              EditorSplitter(horizontal: true, onDrag: handleDrag),
              SizedBox(width: secondExtent, child: widget.second),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(height: firstExtent, child: widget.first),
            EditorSplitter(horizontal: false, onDrag: handleDrag),
            SizedBox(height: secondExtent, child: widget.second),
          ],
        );
      },
    );
  }
}

class EditorSplitter extends StatelessWidget {
  const EditorSplitter({super.key, required this.horizontal, required this.onDrag});

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
