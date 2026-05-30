import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.label, this.icon, this.onPressed});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (label == 'Clipboard' || label == 'Sample' || label == 'Clear') {
      return const SizedBox.shrink();
    }

    final appColors = context.appColors;
    final Widget child;
    if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)],
      );
    } else if (label == 'Go') {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: const Size(0, 32),
          backgroundColor: appColors.success,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: const Text('Go'),
      );
    } else {
      child = Text(label);
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 32),
        side: BorderSide(color: appColors.border),
        backgroundColor: appColors.panelElevated,
        foregroundColor: appColors.editorText,
        textStyle: const TextStyle(fontSize: 12.5),
      ),
      child: child,
    );
  }
}

class ToolIconButton extends StatelessWidget {
  const ToolIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (_isClipboardIcon(icon) ||
        icon == Icons.clear ||
        icon == Icons.settings) {
      return const SizedBox.shrink();
    }

    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      splashRadius: 18,
    );
  }
}

class SmallDropdown extends StatefulWidget {
  const SmallDropdown({
    super.key,
    required this.items,
    required this.initialValue,
    this.width,
    this.onChanged,
  });

  final List<String> items;
  final String initialValue;
  final double? width;
  final ValueChanged<String>? onChanged;

  @override
  State<SmallDropdown> createState() => _SmallDropdownState();
}

double _smallDropdownWidth(List<String> items) {
  final longest = items.fold<int>(
    0,
    (previous, item) => item.length > previous ? item.length : previous,
  );
  return (longest * 7.5 + 48).clamp(72.0, 280.0).toDouble();
}

class _SmallDropdownState extends State<SmallDropdown> {
  late String _value = widget.initialValue;

  @override
  void didUpdateWidget(covariant SmallDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.items.contains(widget.initialValue)) {
      _value = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    if (!widget.items.contains(_value) && widget.items.isNotEmpty) {
      _value = widget.items.first;
    }
    final width = widget.width ?? _smallDropdownWidth(widget.items);
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: width),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: appColors.panelElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: appColors.border),
        ),
        child: SizedBox(
          child: DropdownButton<String>(
            value: _value,
            items: widget.items
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(
                      item,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => widget.items
                .map(
                  (item) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _value = value);
                widget.onChanged?.call(value);
              }
            },
            underline: const SizedBox.shrink(),
            isDense: true,
            isExpanded: true,
            dropdownColor: appColors.panelElevated,
            style: TextStyle(color: appColors.editorText, fontSize: 13),
            iconEnabledColor: appColors.mutedText,
          ),
        ),
      ),
    );
  }
}

class SegmentedToggle extends StatefulWidget {
  const SegmentedToggle({
    super.key,
    required this.options,
    this.initialIndex = 0,
    this.onChanged,
  });

  final List<String> options;
  final int initialIndex;
  final ValueChanged<int>? onChanged;

  @override
  State<SegmentedToggle> createState() => _SegmentedToggleState();
}

class _SegmentedToggleState extends State<SegmentedToggle> {
  late int _selected = widget.initialIndex;

  @override
  void didUpdateWidget(covariant SegmentedToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex &&
        widget.initialIndex >= 0 &&
        widget.initialIndex < widget.options.length) {
      _selected = widget.initialIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToggleButtons(
      isSelected: List<bool>.generate(
        widget.options.length,
        (index) => index == _selected,
      ),
      onPressed: (index) {
        setState(() => _selected = index);
        widget.onChanged?.call(index);
      },
      borderRadius: BorderRadius.circular(6),
      constraints: const BoxConstraints(minHeight: 30, minWidth: 60),
      children: widget.options
          .map((label) => Text(label, style: const TextStyle(fontSize: 12)))
          .toList(),
    );
  }
}

class EditorPane extends StatelessWidget {
  const EditorPane({
    super.key,
    required this.label,
    required this.actions,
    this.placeholder = '',
    this.readOnly = false,
    this.expand = true,
    this.fixedHeight = 140,
    this.controller,
    this.onChanged,
    this.copyAction,
    this.onSubmit,
    this.scrollController,
    this.markedLines = const <int>{},
    this.showHeader = true,
    this.overlay,
  });

  final String label;
  final List<Widget> actions;
  final String placeholder;
  final bool readOnly;
  final bool expand;
  final double fixedHeight;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? copyAction;
  final VoidCallback? onSubmit;
  final ScrollController? scrollController;
  final Set<int> markedLines;
  final bool showHeader;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final headerActions = <Widget>[];
    VoidCallback? exampleAction;
    VoidCallback? clearAction;
    for (final action in actions) {
      if (action is ToolButton) {
        if (action.label == 'Sample') {
          exampleAction ??= action.onPressed;
          continue;
        }
        if (action.label == 'Clear') {
          clearAction ??= action.onPressed;
          continue;
        }
        if (_isHiddenEditorAction(action.label, compact: !showHeader)) {
          continue;
        }
      }
      headerActions.add(action);
    }
    final resolvedCopyAction = copyAction;
    final resolvedOverlay =
        overlay ??
        (!showHeader && headerActions.isNotEmpty
            ? _EditorOverlayControls(actions: headerActions)
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < headerActions.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              headerActions[i],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (expand)
          Expanded(
            child: _EditorField(
              label: label,
              placeholder: placeholder,
              readOnly: readOnly,
              controller: controller,
              onChanged: onChanged,
              copyAction: resolvedCopyAction,
              onSubmit: onSubmit,
              scrollController: scrollController,
              markedLines: markedLines,
              overlay: resolvedOverlay,
              exampleAction: readOnly ? null : exampleAction,
              clearAction: readOnly ? null : clearAction,
            ),
          )
        else
          SizedBox(
            height: fixedHeight,
            child: _EditorField(
              label: label,
              placeholder: placeholder,
              readOnly: readOnly,
              controller: controller,
              onChanged: onChanged,
              copyAction: resolvedCopyAction,
              onSubmit: onSubmit,
              scrollController: scrollController,
              markedLines: markedLines,
              overlay: resolvedOverlay,
              exampleAction: readOnly ? null : exampleAction,
              clearAction: readOnly ? null : clearAction,
            ),
          ),
      ],
    );
  }
}

class _EditorOverlayControls extends StatelessWidget {
  const _EditorOverlayControls({required this.actions});

  final List<Widget> actions;

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
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                actions[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.label,
    required this.placeholder,
    required this.readOnly,
    this.controller,
    this.onChanged,
    this.copyAction,
    this.onSubmit,
    this.scrollController,
    this.markedLines = const <int>{},
    this.overlay,
    this.exampleAction,
    this.clearAction,
  });

  final String label;
  final String placeholder;
  final bool readOnly;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? copyAction;
  final VoidCallback? onSubmit;
  final ScrollController? scrollController;
  final Set<int> markedLines;
  final Widget? overlay;
  final VoidCallback? exampleAction;
  final VoidCallback? clearAction;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final rightPadding = copyAction != null ? 50.0 : 8.0;
    final hasContextActions =
        !readOnly && (exampleAction != null || clearAction != null);

    Future<void> showEditorContextMenu(Offset globalPosition) async {
      final selected = await showMenu<_EditorContextAction>(
        context: context,
        color: appColors.panelElevated,
        position: RelativeRect.fromLTRB(
          globalPosition.dx,
          globalPosition.dy,
          globalPosition.dx,
          globalPosition.dy,
        ),
        items: [
          if (exampleAction != null)
            const PopupMenuItem<_EditorContextAction>(
              value: _EditorContextAction.example,
              child: Text('Example'),
            ),
          if (clearAction != null)
            const PopupMenuItem<_EditorContextAction>(
              value: _EditorContextAction.clear,
              child: Text('Clear'),
            ),
        ],
      );
      switch (selected) {
        case _EditorContextAction.example:
          exampleAction?.call();
          break;
        case _EditorContextAction.clear:
          clearAction?.call();
          break;
        case null:
          break;
      }
    }

    Widget textField = TextField(
      readOnly: readOnly,
      controller: controller,
      scrollController: scrollController,
      onChanged: onChanged,
      maxLines: null,
      expands: true,
      decoration: InputDecoration(
        hintText: placeholder,
        border: InputBorder.none,
        isDense: true,
        filled: false,
        hintStyle: TextStyle(color: appColors.mutedText),
      ),
      style: TextStyle(
        fontFamily: 'Menlo',
        fontSize: 12,
        color: appColors.editorText,
      ),
    );

    // Wrap with keyboard handler if onSubmit is provided
    // Enter = submit, Shift+Enter = newline
    if (onSubmit != null && !readOnly) {
      textField = Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed) {
            onSubmit!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: textField,
      );
    }

    return Semantics(
      label: label,
      textField: true,
      child: Listener(
        onPointerDown: hasContextActions
            ? (event) {
                if ((event.buttons & kSecondaryMouseButton) != 0) {
                  showEditorContextMenu(event.position);
                }
              }
            : null,
        child: Container(
          decoration: BoxDecoration(
            color: appColors.editorBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: appColors.border),
          ),
          child: Stack(
            children: [
              if (markedLines.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Tooltip(
                    message: 'Changed lines: ${markedLines.take(8).join(', ')}',
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: appColors.warning,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  markedLines.isEmpty ? 8 : 12,
                  6,
                  rightPadding,
                  6,
                ),
                child: textField,
              ),
              if (overlay != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: overlay!,
                  ),
                )
              else if (copyAction != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: TextButton(
                    onPressed: copyAction,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    child: const Text('Copy'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _EditorContextAction { example, clear }

bool _isClipboardIcon(IconData icon) {
  return icon == Icons.content_paste ||
      icon == Icons.copy ||
      icon == Icons.copy_all;
}

bool _isHiddenEditorAction(String label, {required bool compact}) {
  if (label == 'Clipboard' ||
      label == 'Copy' ||
      label == 'Sample' ||
      label == 'Clear') {
    return true;
  }
  if (!compact) return false;
  return label == 'Go';
}

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    this.trailing,
    this.hintText,
    this.controller,
    this.readOnly = false,
  });

  final String label;
  final Widget? trailing;
  final String? hintText;
  final TextEditingController? controller;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 160, child: Text(label)),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: appColors.panelElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: appColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                controller: controller,
                readOnly: readOnly,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: InputBorder.none,
                  isDense: true,
                  filled: false,
                  hintStyle: TextStyle(color: appColors.mutedText),
                ),
                style: TextStyle(fontSize: 12, color: appColors.editorText),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0.4,
          color: appColors.mutedText,
        ),
      ),
    );
  }
}
