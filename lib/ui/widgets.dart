import 'dart:async';
import 'dart:io';

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
    this.enableFileDrop = true,
    this.softWrap = true,
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

  /// Whether dropping a text file onto this editor loads its contents.
  /// Auto-enabled for editable inputs that own a controller; set to `false`
  /// for editors that already wrap themselves in a dedicated drop target so
  /// the same region isn't registered twice.
  final bool enableFileDrop;

  /// When `false`, a read-only editor renders each line without soft-wrapping
  /// and scrolls horizontally instead, so long rows stay on one line.
  final bool softWrap;

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
    final pane = Column(
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
              softWrap: softWrap,
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
              softWrap: softWrap,
              exampleAction: readOnly ? null : exampleAction,
              clearAction: readOnly ? null : clearAction,
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
    this.softWrap = true,
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
  final bool softWrap;
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

    // Virtualized editor (re_editor) renders only visible lines, so large
    // documents stay responsive. It bridges to the [TextEditingController]
    // that tools already use, so the public API is unchanged.
    Widget textField = _CodeEditorField(
      controller: controller,
      readOnly: readOnly,
      placeholder: placeholder,
      wordWrap: softWrap,
      onChanged: onChanged,
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
                    rightPadding,
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
  });

  final TextEditingController? controller;
  final bool readOnly;
  final String placeholder;
  final bool wordWrap;
  final ValueChanged<String>? onChanged;

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
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onExternalTextChanged);
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
        padding: EdgeInsets.zero,
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
