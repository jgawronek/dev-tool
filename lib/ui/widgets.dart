import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      );
    } else if (label == 'Clipboard') {
      return IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.content_paste, size: 20),
        tooltip: 'Clipboard',
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        splashRadius: 18,
      );
    } else if (label == 'Sample') {
      return IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.auto_awesome, size: 20),
        tooltip: 'Sample',
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        splashRadius: 18,
      );
    } else if (label == 'Clear') {
      return IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.clear, size: 20),
        tooltip: 'Clear',
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        splashRadius: 18,
      );
    } else if (label == 'Go') {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: const Size(0, 32),
          backgroundColor: const Color(0xFF2FA866),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        child: const Text('Go'),
      );
    } else if (label == 'Copy') {
      return IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.copy_all, size: 20),
        tooltip: 'Copy',
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        splashRadius: 18,
      );
    } else {
      child = Text(label);
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 32),
        side: const BorderSide(color: Color(0xFFD0D0D0)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2B2B2B),
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

class _SmallDropdownState extends State<SmallDropdown> {
  late String _value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    if (!widget.items.contains(_value) && widget.items.isNotEmpty) {
      _value = widget.items.first;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
      ),
      child: DropdownButton<String>(
        value: _value,
        items: widget.items
            .map((item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                ))
            .toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() => _value = value);
            widget.onChanged?.call(value);
          }
        },
        underline: const SizedBox.shrink(),
        isDense: true,
        dropdownColor: Colors.white,
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
      children: widget.options.map((label) => Text(label, style: const TextStyle(fontSize: 12))).toList(),
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

  @override
  Widget build(BuildContext context) {
    ToolButton? copyToolAction;
    final headerActions = <Widget>[];
    for (final action in actions) {
      if (action is ToolButton && action.label == 'Copy') {
        copyToolAction ??= action;
      } else {
        headerActions.add(action);
      }
    }
    final resolvedCopyAction = copyAction ?? copyToolAction?.onPressed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
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
        const SizedBox(height: 8),
        if (expand)
          Expanded(
            child: _EditorField(
              placeholder: placeholder,
              readOnly: readOnly,
              controller: controller,
              onChanged: onChanged,
              copyAction: resolvedCopyAction,
              onSubmit: onSubmit,
            ),
          )
        else
          SizedBox(
            height: fixedHeight,
            child: _EditorField(
              placeholder: placeholder,
              readOnly: readOnly,
              controller: controller,
              onChanged: onChanged,
              copyAction: resolvedCopyAction,
              onSubmit: onSubmit,
            ),
          ),
      ],
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.placeholder,
    required this.readOnly,
    this.controller,
    this.onChanged,
    this.copyAction,
    this.onSubmit,
  });

  final String placeholder;
  final bool readOnly;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? copyAction;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final rightPadding = copyAction != null ? 30.0 : 8.0;

    Widget textField = TextField(
      readOnly: readOnly,
      controller: controller,
      onChanged: onChanged,
      maxLines: null,
      expands: true,
      decoration: InputDecoration(
        hintText: placeholder,
        border: InputBorder.none,
        isDense: true,
      ),
      style: const TextStyle(
        fontFamily: 'Menlo',
        fontSize: 12,
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD5D5D5)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(8, 6, rightPadding, 6),
            child: textField,
          ),
          if (copyAction != null)
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                onPressed: copyAction,
                icon: const Icon(Icons.copy_all, size: 16),
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                splashRadius: 14,
              ),
            ),
        ],
      ),
    );
  }
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFD5D5D5)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                controller: controller,
                readOnly: readOnly,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
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
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0.4,
          color: Color(0xFF6A6A6A),
        ),
      ),
    );
  }
}
