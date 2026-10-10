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
  bool outputFirst = false,
  String inputPlaceholder = 'Enter text...',
  String outputPlaceholder = 'Output...',
  TextEditingController? inputController,
  TextEditingController? outputController,
  ValueChanged<String>? onInputChanged,
  bool? horizontal,
  VoidCallback? onInputSubmit,
  ScrollController? inputScrollController,
  ScrollController? outputScrollController,
  Set<int> inputMarkedLines = const <int>{},
  Set<int> outputMarkedLines = const <int>{},
  bool showInputHeader = true,
  bool showOutputHeader = true,
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
  return LayoutBuilder(
    builder: (context, constraints) => ResizableSplit(
      horizontal: horizontal ?? constraints.maxWidth >= 800,
      first: outputFirst ? output : input,
      second: outputFirst ? input : output,
    ),
  );
}

/// A [ResizableSplit] that goes side-by-side (vertical divider) once the
/// content area is wide enough, and stacks vertically below that.
Widget buildAdaptiveSplit({
  double breakpoint = 800,
  required Widget first,
  required Widget second,
  double initialRatio = 0.5,
  double minFirstExtent = 120,
  double minSecondExtent = 120,
}) {
  return LayoutBuilder(
    builder: (context, constraints) => ResizableSplit(
      horizontal: constraints.maxWidth >= breakpoint,
      first: first,
      second: second,
      initialRatio: initialRatio,
      minFirstExtent: constraints.maxWidth >= breakpoint
          ? minFirstExtent
          : min(minFirstExtent, 160),
      minSecondExtent: constraints.maxWidth >= breakpoint
          ? minSecondExtent
          : min(minSecondExtent, 160),
    ),
  );
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
  bool showInputHeader = true,
  bool showOutputHeader = true,
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
        const splitterExtent = 14.0;
        final maxExtent = widget.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final available = max(0.0, maxExtent - splitterExtent);
        final minTotal = widget.minFirstExtent + widget.minSecondExtent;

        // A split must never hand an editor a zero or sub-minimum extent:
        // re_editor asserts when its field has no bounded height, and squeezed
        // panes overflow their fixed-width content. When the panel is too small
        // to honour both minimums, scroll the split with each pane at its
        // declared minimum instead of letting the ratio math collapse one.
        if (available < minTotal) {
          final scrollDirection = widget.horizontal
              ? Axis.horizontal
              : Axis.vertical;
          return SingleChildScrollView(
            scrollDirection: scrollDirection,
            child: SizedBox(
              width: widget.horizontal ? minTotal + splitterExtent : null,
              height: widget.horizontal ? null : minTotal + splitterExtent,
              child: widget.horizontal
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: widget.minFirstExtent,
                          child: widget.first,
                        ),
                        EditorSplitter(horizontal: true, onDrag: (_) {}),
                        SizedBox(
                          width: widget.minSecondExtent,
                          child: widget.second,
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: widget.minFirstExtent,
                          child: widget.first,
                        ),
                        EditorSplitter(horizontal: false, onDrag: (_) {}),
                        SizedBox(
                          height: widget.minSecondExtent,
                          child: widget.second,
                        ),
                      ],
                    ),
            ),
          );
        }

        final requestedFirst = min(widget.minFirstExtent, available);
        final requestedSecond = min(widget.minSecondExtent, available);
        final minFirstExtent = requestedFirst;
        final minSecondExtent = requestedSecond;
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
  const EditorSplitter({
    super.key,
    required this.horizontal,
    required this.onDrag,
  });

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
          width: horizontal ? 14 : double.infinity,
          height: horizontal ? double.infinity : 14,
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
