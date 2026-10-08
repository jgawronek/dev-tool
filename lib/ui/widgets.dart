import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../services/file_dialog_service.dart';
import 'app_colors.dart';

class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.label, this.icon, this.onPressed});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Note: EditorPane pulls 'Sample'/'Clear' into its context menu and hides
    // 'Clipboard'/'Copy' from compact headers itself, so those labels render
    // normally when a ToolButton is used outside an editor pane.

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: appColors.success,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: const Text('Go'),
      );
    } else {
      child = Text(label);
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: appColors.border),
        backgroundColor: appColors.panelElevated,
        foregroundColor: appColors.editorText,
        textStyle: const TextStyle(fontSize: 12),
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
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Optional icon tint; defaults to the icon theme color when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (_isClipboardIcon(icon) ||
        icon == Icons.clear ||
        icon == Icons.settings) {
      return const SizedBox.shrink();
    }

    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 16,
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
            style: TextStyle(color: appColors.editorText, fontSize: 12),
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
      constraints: const BoxConstraints(minHeight: 28, minWidth: 56),
      children: widget.options
          .map((label) => Text(label, style: const TextStyle(fontSize: 11.5)))
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
    this.pasteAction,
    this.onSubmit,
    this.scrollController,
    this.markedLines = const <int>{},
    this.showHeader = true,
    this.overlay,
    this.enableFileDrop = true,
    this.softWrap = true,
    this.revealLine,
    this.highlightTheme,
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
  final VoidCallback? pasteAction;
  final VoidCallback? onSubmit;
  final ScrollController? scrollController;
  final Set<int> markedLines;
  final bool showHeader;
  final Widget? overlay;

  /// When set, changing this notifier's value selects and scrolls to that
  /// 0-based line in the editor (used to link a selection to its source).
  final ValueListenable<int?>? revealLine;

  /// Whether dropping a text file onto this editor loads its contents.
  /// Auto-enabled for editable inputs that own a controller; set to `false`
  /// for editors that already wrap themselves in a dedicated drop target so
  /// the same region isn't registered twice.
  final bool enableFileDrop;

  /// When `false`, a read-only editor renders each line without soft-wrapping
  /// and scrolls horizontally instead, so long rows stay on one line.
  final bool softWrap;

  /// Optional syntax-highlight theme for the underlying code editor.
  final CodeHighlightTheme? highlightTheme;

  @override
  Widget build(BuildContext context) {
    final headerActions = <Widget>[];
    VoidCallback? exampleAction;
    VoidCallback? clearAction;
    VoidCallback? promotedCopyAction;
    VoidCallback? promotedPasteAction;
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
        if (action.label == 'Copy') {
          // A Copy ToolButton is how callers ask for the floating copy
          // affordance. Dropping it (as the hidden-label filter used to) left
          // most tools with no way to copy their output at all.
          promotedCopyAction ??= action.onPressed;
          continue;
        }
        if (action.label == 'Clipboard') {
          // Likewise for pasting: the button was filtered out and never
          // rendered, so "paste from clipboard" was unreachable.
          promotedPasteAction ??= action.onPressed;
          continue;
        }
        if (_isHiddenEditorAction(action.label, compact: !showHeader)) {
          continue;
        }
      }
      headerActions.add(action);
    }
    final resolvedCopyAction = copyAction ?? promotedCopyAction;
    final resolvedPasteAction = pasteAction ?? promotedPasteAction;
    final resolvedOverlay = _resolveOverlay(
      overlay,
      headerActions,
      showHeader,
      resolvedCopyAction,
      resolvedPasteAction,
    );
    final pane = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Container(
            // Fixed height with centered content so the label lines up with an
            // adjacent pane's header whether or not action buttons are present.
            height: 38,
            alignment: Alignment.centerLeft,
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
              pasteAction: resolvedPasteAction,
              onSubmit: onSubmit,
              scrollController: scrollController,
              markedLines: markedLines,
              overlay: resolvedOverlay,
              softWrap: softWrap,
              exampleAction: readOnly ? null : exampleAction,
              clearAction: readOnly ? null : clearAction,
              revealLine: revealLine,
              highlightTheme: highlightTheme,
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
              pasteAction: resolvedPasteAction,
              onSubmit: onSubmit,
              scrollController: scrollController,
              markedLines: markedLines,
              overlay: resolvedOverlay,
              softWrap: softWrap,
              exampleAction: readOnly ? null : exampleAction,
              clearAction: readOnly ? null : clearAction,
              revealLine: revealLine,
              highlightTheme: highlightTheme,
            ),
          ),
      ],
    );

    final dropController = controller;
    if (!enableFileDrop || readOnly || dropController == null) return pane;
    return _EditorFileDropRegion(
      controller: dropController,
      onChanged: onChanged,
      child: pane,
    );
  }
}

/// Wraps an editable [EditorPane] so dropping a text file replaces the
/// editor's contents. Registers a coordinate-addressed target with
/// [FileDropService]; binary or oversized files are ignored silently.
class _EditorFileDropRegion extends StatefulWidget {
  const _EditorFileDropRegion({
    required this.controller,
    required this.onChanged,
    required this.child,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final Widget child;

  @override
  State<_EditorFileDropRegion> createState() => _EditorFileDropRegionState();
}

class _EditorFileDropRegionState extends State<_EditorFileDropRegion> {
  static const _maxFileBytes = 20 * 1024 * 1024;
  final GlobalKey _dropKey = GlobalKey();
  late final String _targetId =
      'editor-drop-${identityHashCode(this).toRadixString(16)}';

  @override
  void initState() {
    super.initState();
    FileDropService.registerTarget(
      _targetId,
      key: _dropKey,
      handler: _onDropped,
    );
  }

  @override
  void dispose() {
    FileDropService.unregisterTarget(_targetId);
    super.dispose();
  }

  Future<void> _onDropped(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      final file = File(paths.first);
      if (!await file.exists()) return;
      if (await file.length() > _maxFileBytes) return;
      final text = await file.readAsString();
      if (!mounted) return;
      widget.controller.text = text;
      widget.onChanged?.call(text);
    } catch (_) {
      // Non-text/binary file or read failure: leave the editor untouched.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => FileDropService.setActiveTarget(_targetId),
      onExit: (_) => FileDropService.setActiveTarget(null),
      child: KeyedSubtree(key: _dropKey, child: widget.child),
    );
  }
}

/// Picks the floating control strip for a pane.
///
/// Actions are *merged* with a caller-supplied [overlay] rather than replaced
/// by it. Overriding them was a silent trap: any tool that passed both lost
/// every action, which is how several tools ended up with no Copy button.
Widget? _resolveOverlay(
  Widget? overlay,
  List<Widget> headerActions,
  bool showHeader,
  VoidCallback? copyAction,
  VoidCallback? pasteAction,
) {
  final Widget? base;
  if (overlay != null) {
    base = headerActions.isEmpty
        ? overlay
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [overlay, const SizedBox(width: 6), ...headerActions],
          );
  } else {
    base = !showHeader && headerActions.isNotEmpty
        ? _EditorOverlayControls(actions: headerActions)
        : null;
  }
  if (base == null && copyAction == null && pasteAction == null) return null;

  // With no caller-supplied overlay, an empty strip leaves room for the
  // standalone copy/paste buttons that _EditorField positions for us.
  if (base == null) return null;

  final extras = <Widget>[
    if (copyAction != null) _FloatingCopyButton(onPressed: copyAction),
    if (pasteAction != null) _FloatingPasteButton(onPressed: pasteAction),
  ];
  if (extras.isEmpty) return base;
  // When a strip is present the copy/paste buttons join it; _EditorField only
  // positions standalone buttons when there is no strip at all.
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      base,
      for (final extra in extras) ...[const SizedBox(width: 6), extra],
    ],
  );
}

/// The compact icon button used to paste into a pane.
class _FloatingPasteButton extends StatelessWidget {
  const _FloatingPasteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Tooltip(
      message: 'Paste from clipboard',
      child: Material(
        color: appColors.panelElevated.withAlpha(210),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: appColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(Icons.content_paste, size: 15, color: appColors.mutedText),
          ),
        ),
      ),
    );
  }
}

/// The compact icon button used to copy a pane's contents.
class _FloatingCopyButton extends StatelessWidget {
  const _FloatingCopyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Tooltip(
      message: 'Copy',
      child: Material(
        color: appColors.panelElevated.withAlpha(210),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: appColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(Icons.copy, size: 15, color: appColors.mutedText),
          ),
        ),
      ),
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
    this.pasteAction,
    this.onSubmit,
    this.scrollController,
    this.markedLines = const <int>{},
    this.overlay,
    this.softWrap = true,
    this.exampleAction,
    this.clearAction,
    this.revealLine,
    this.highlightTheme,
  });

  final String label;
  final String placeholder;
  final bool readOnly;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? copyAction;
  final VoidCallback? pasteAction;
  final VoidCallback? onSubmit;
  final ScrollController? scrollController;
  final Set<int> markedLines;
  final Widget? overlay;
  final bool softWrap;
  final VoidCallback? exampleAction;
  final VoidCallback? clearAction;
  final ValueListenable<int?>? revealLine;
  final CodeHighlightTheme? highlightTheme;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    // Keep the editor (and its right-edge scrollbar) flush with the container;
    // reserve room for the floating copy button as *content* padding instead,
    // so the scrollbar isn't pushed inward by the button.
    final reserveForCopy = overlay == null && copyAction != null;
    final contentRightPad = reserveForCopy ? 30.0 : 0.0;
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

    // Virtualized editor (re_editor) renders only visible lines, so large
    // documents stay responsive. It bridges to the [TextEditingController]
    // that tools already use, so the public API is unchanged.
    Widget textField = _CodeEditorField(
      controller: controller,
      readOnly: readOnly,
      placeholder: placeholder,
      wordWrap: softWrap,
      onChanged: onChanged,
      revealLine: revealLine,
      contentRightPad: contentRightPad,
      highlightTheme: highlightTheme,
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
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    markedLines.isEmpty ? 8 : 12,
                    6,
                    8,
                    6,
                  ),
                  child: textField,
                ),
              ),
              if (overlay != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: overlay!,
                    ),
                  ),
                )
              else if (copyAction != null || pasteAction != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (copyAction != null)
                        _FloatingCopyButton(onPressed: copyAction!),
                      if (copyAction != null && pasteAction != null)
                        const SizedBox(width: 6),
                      if (pasteAction != null)
                        _FloatingPasteButton(onPressed: pasteAction!),
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

/// A virtualized text editor (re_editor) that bridges to a Flutter
/// [TextEditingController] so existing tools keep their `controller.text` API.
/// Only visible lines are laid out, so large documents stay responsive.
class _CodeEditorField extends StatefulWidget {
  const _CodeEditorField({
    required this.controller,
    required this.readOnly,
    required this.placeholder,
    required this.wordWrap,
    required this.onChanged,
    this.revealLine,
    this.contentRightPad = 0,
    this.highlightTheme,
  });

  final TextEditingController? controller;
  final bool readOnly;
  final String placeholder;
  final bool wordWrap;
  final ValueChanged<String>? onChanged;
  final ValueListenable<int?>? revealLine;

  /// Right padding applied to the code content (not the scrollbar) so text
  /// clears a floating copy button while the scrollbar stays flush right.
  final double contentRightPad;

  /// Optional syntax-highlight theme (language grammar + colors). When null the
  /// editor renders plain monospace text.
  final CodeHighlightTheme? highlightTheme;

  @override
  State<_CodeEditorField> createState() => _CodeEditorFieldState();
}

class _CodeEditorFieldState extends State<_CodeEditorField> {
  late final CodeLineEditingController _code;
  String _lastText = '';
  bool _syncingToText = false;
  bool _applyingExternal = false;

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller?.text ?? '';
    _code = CodeLineEditingController.fromText(_lastText);
    _code.addListener(_onCodeChanged);
    widget.controller?.addListener(_onExternalTextChanged);
    widget.revealLine?.addListener(_onRevealLine);
  }

  @override
  void didUpdateWidget(covariant _CodeEditorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_onExternalTextChanged);
      widget.controller?.addListener(_onExternalTextChanged);
      final next = widget.controller?.text ?? '';
      if (_code.text != next) {
        _applyingExternal = true;
        _code.text = next;
        _applyingExternal = false;
      }
      _lastText = next;
    }
    if (!identical(oldWidget.revealLine, widget.revealLine)) {
      oldWidget.revealLine?.removeListener(_onRevealLine);
      widget.revealLine?.addListener(_onRevealLine);
    }
  }

  // A linked view (e.g. a diagram canvas) asked to reveal a source line:
  // select it and scroll it into view.
  void _onRevealLine() {
    final line = widget.revealLine?.value;
    if (line == null || line < 0) return;
    try {
      if (line >= _code.codeLines.length) return;
      _code.selectLine(line);
      _code.makePositionCenterIfInvisible(
        CodeLinePosition(index: line, offset: 0),
      );
    } catch (_) {
      // Editor not laid out yet / transient index race — never let a reveal
      // throw and tear down the linked canvas.
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onExternalTextChanged);
    widget.revealLine?.removeListener(_onRevealLine);
    _code.removeListener(_onCodeChanged);
    _code.dispose();
    super.dispose();
  }

  // Tool wrote to the TextEditingController (Sample/Clear/conversion output).
  void _onExternalTextChanged() {
    final controller = widget.controller;
    if (controller == null || _syncingToText) return;
    if (_code.text != controller.text) {
      _applyingExternal = true;
      _code.text = controller.text;
      _applyingExternal = false;
      _lastText = controller.text;
    }
  }

  // User edited inside the editor.
  void _onCodeChanged() {
    if (_applyingExternal) return;
    final text = _code.text;
    if (text == _lastText) return; // selection-only change
    _lastText = text;
    final controller = widget.controller;
    if (controller != null && controller.text != text) {
      _syncingToText = true;
      controller.text = text;
      _syncingToText = false;
    }
    widget.onChanged?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(true),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStatePropertyAll(appColors.mutedText.withAlpha(140)),
      ),
      child: CodeEditor(
        controller: _code,
        readOnly: widget.readOnly,
        wordWrap: widget.wordWrap,
        hint: widget.placeholder,
        autocompleteSymbols: false,
        padding: EdgeInsets.only(right: widget.contentRightPad),
        // Enables the built-in find (⌘F); the panel renders zero-height when
        // closed so it doesn't reserve editor space.
        findBuilder: (context, controller, readOnly) =>
            _EditorFindPanel(controller: controller),
        // We don't show fold indicators, so skip the default code-folding
        // analysis — it's wasted work on large documents.
        chunkAnalyzer: const NonCodeChunkAnalyzer(),
        // Cap per-line render length so a huge single line (e.g. minified
        // JSON) doesn't freeze the Skia text engine. Full text is preserved.
        maxLengthSingleLineRendering: 2000,
        scrollbarBuilder: (context, child, details) => Scrollbar(
          controller: details.controller,
          thumbVisibility: true,
          child: child,
        ),
        style: CodeEditorStyle(
          fontSize: 12,
          fontFamily: 'Menlo',
          textColor: appColors.editorText,
          hintTextColor: appColors.mutedText,
          backgroundColor: Colors.transparent,
          cursorColor: appColors.accent,
          selectionColor: appColors.accentSoft,
          codeTheme: widget.highlightTheme,
        ),
      ),
    );
  }
}

/// Compact find bar shown over the top-right of a [CodeEditor] when find mode
/// (⌘F) is active. Reports a zero-height [preferredSize] when closed so re_editor
/// reserves no top inset; renders the bar (find field, match count, case/regex
/// toggles, prev/next, close) when open.
class _EditorFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const _EditorFindPanel({required this.controller});

  final CodeFindController controller;

  bool get _active => controller.value != null;

  @override
  Size get preferredSize => _active ? const Size.fromHeight(42) : Size.zero;

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    final appColors = context.appColors;
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, right: 6),
        child: Material(
          elevation: 4,
          color: appColors.panelElevated,
          shadowColor: appColors.shadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: appColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final value = controller.value;
                final result = value?.result;
                final total = result?.matches.length ?? 0;
                final pos = (result == null || result.matches.isEmpty)
                    ? 0
                    : result.index + 1;
                final pattern = value?.option.pattern ?? '';
                final label = value?.searching == true
                    ? '…'
                    : pattern.isEmpty
                        ? ''
                        : total == 0
                            ? 'No results'
                            : '$pos/$total';
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 170,
                      height: 30,
                      child: TextField(
                        controller: controller.findInputController,
                        focusNode: controller.findInputFocusNode,
                        autofocus: true,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: appColors.editorText,
                        ),
                        textAlignVertical: TextAlignVertical.center,
                        onSubmitted: (_) => controller.nextMatch(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Find',
                          hintStyle: TextStyle(
                            color: appColors.mutedText,
                            fontSize: 12.5,
                          ),
                          filled: true,
                          fillColor: appColors.editorBackground,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: appColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: appColors.accent),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 58,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: appColors.mutedText,
                        ),
                      ),
                    ),
                    _findToggle(appColors, 'Aa', value?.option.caseSensitive ?? false,
                        controller.toggleCaseSensitive, 'Match case'),
                    _findToggle(appColors, '.*', value?.option.regex ?? false,
                        controller.toggleRegex, 'Regular expression'),
                    _findIcon(appColors, Icons.keyboard_arrow_up,
                        controller.previousMatch, 'Previous match'),
                    _findIcon(appColors, Icons.keyboard_arrow_down,
                        controller.nextMatch, 'Next match'),
                    _findIcon(appColors, Icons.close, controller.close, 'Close'),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _findToggle(
    AppColors c,
    String label,
    bool active,
    VoidCallback onTap,
    String tooltip,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: 28,
          height: 26,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: active ? c.accent : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? c.accent : c.mutedText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _findIcon(
    AppColors c,
    IconData icon,
    VoidCallback onTap,
    String tooltip,
  ) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onTap,
      tooltip: tooltip,
      color: c.mutedText,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 16,
    );
  }
}

enum _EditorContextAction { example, clear }

bool _isClipboardIcon(IconData icon) {
  return icon == Icons.content_paste ||
      icon == Icons.copy ||
      icon == Icons.copy_all;
}

/// Whether [label] should be hidden from the action strip.
///
/// Only the Go button is dropped, and only when the pane has no header to
/// carry it. The other conventionally-labelled buttons used to be listed here
/// and silently discarded; they are now handled explicitly above, where Copy
/// and Clipboard become affordances and Sample/Clear become context-menu
/// entries. Keeping this list to a single case means a new label cannot be
/// dropped by accident.
bool _isHiddenEditorAction(String label, {required bool compact}) {
  return compact && label == 'Go';
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 12))),
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
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 10.5,
          letterSpacing: 0.4,
          color: appColors.mutedText,
        ),
      ),
    );
  }
}
