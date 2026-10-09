/// Chmod calculator tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/chmod_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

class _ChmodCalculatorView extends StatefulWidget {
  const _ChmodCalculatorView();

  @override
  State<_ChmodCalculatorView> createState() => _ChmodCalculatorViewState();
}

class _ChmodCalculatorViewState extends State<_ChmodCalculatorView> {
  final TextEditingController _mode = TextEditingController(text: '755');
  final TextEditingController _report = TextEditingController();

  ChmodInfo? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Parse the seeded default so the panel is populated on first open
    // rather than showing the empty-state prompt next to a filled field.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyMode(_mode.text));
  }

  @override
  void dispose() {
    _mode.dispose();
    _report.dispose();
    super.dispose();
  }

  void _set(ChmodInfo info) {
    setState(() {
      _info = info;
      _error = null;
      _mode.text = info.octal;
      _report.text = info.toReport();
    });
  }

  void _applyMode(String value) {
    if (value.trim().isEmpty) {
      setState(() {
        _error = null;
        _info = null;
        _report.clear();
      });
      return;
    }
    final outcome = parseChmod(value);
    if (outcome == null) {
      setState(() {
        _error = 'Not a mode. Try 755 or rwxr-xr-x.';
        _info = null;
        _report.clear();
      });
      return;
    }
    _set(outcome.info!);
  }

  void _toggleBit(ChmodClass chmodClass, String bit) {
    final info = _info;
    if (info == null) return;
    final current = switch (chmodClass) {
      ChmodClass.user => info.user,
      ChmodClass.group => info.group,
      ChmodClass.other => info.other,
    };
    _set(
      info.withClass(
        chmodClass,
        current.copyWith(
          read: bit == 'r' ? !current.read : null,
          write: bit == 'w' ? !current.write : null,
          execute: bit == 'x' ? !current.execute : null,
        ),
      ),
    );
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _report.text));
  }

  void _copyCommand() {
    final info = _info;
    if (info == null) return;
    Clipboard.setData(ClipboardData(text: 'chmod $info.octal <file>'));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInputRow(context, info),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildModeCard(context, info),
                  const SizedBox(height: 12),
                  _buildPresets(context, info),
                  const SizedBox(height: 12),
                  _buildReport(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context, ChmodInfo? info) {
    // A Wrap rather than a Row: the field plus buttons and a long error
    // message do not always fit a narrow window, and clipping a control is
    // worse than letting it wrap onto the next line.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: TextField(
                controller: _mode,
                onChanged: _applyMode,
                onSubmitted: _applyMode,
                style: TextStyle(
                  color: context.appColors.editorText,
                  fontFamily: 'Menlo',
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  labelText: 'Octal or symbolic',
                  hintText: '755',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: context.appColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: context.appColors.border),
                  ),
                ),
              ),
            ),
            ToolButton(
              label: 'Copy chmod',
              onPressed: info == null ? null : _copyCommand,
            ),
            ToolButton(
              label: 'Copy report',
              onPressed: info == null ? null : _copyReport,
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: errorToolTextStyle(context)),
          ),
      ],
    );
  }

  Widget _buildModeCard(BuildContext context, ChmodInfo? info) {
    if (info == null) {
      return Container(
        decoration: toolSurfaceDecoration(context),
        padding: const EdgeInsets.all(18),
        child: Text(
          'Enter a mode such as 755 or rwxr-xr-x.',
          style: mutedToolTextStyle(context),
        ),
      );
    }
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ModeBadge(label: info.octal),
              const SizedBox(width: 10),
              _ModeBadge(label: info.symbolic),
            ],
          ),
          const SizedBox(height: 14),
          for (final chmodClass in ChmodClass.values) ...[
            _buildClassRow(context, info, chmodClass),
            const SizedBox(height: 4),
          ],
          const Divider(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _SpecialToggle(
                label: 'setuid',
                hint: 'u+s',
                value: info.setuid,
                onChanged: (value) => _set(info.withBits(setuid: value)),
              ),
              _SpecialToggle(
                label: 'setgid',
                hint: 'g+s',
                value: info.setgid,
                onChanged: (value) => _set(info.withBits(setgid: value)),
              ),
              _SpecialToggle(
                label: 'sticky',
                hint: '+t',
                value: info.sticky,
                onChanged: (value) => _set(info.withBits(sticky: value)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClassRow(
    BuildContext context,
    ChmodInfo info,
    ChmodClass chmodClass,
  ) {
    final bits = switch (chmodClass) {
      ChmodClass.user => info.user,
      ChmodClass.group => info.group,
      ChmodClass.other => info.other,
    };
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            '${chmodClass.label} (${chmodClass.letter})',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${bits.octal}',
            style: TextStyle(
              fontFamily: 'Menlo',
              fontSize: 12,
              color: context.appColors.mutedText,
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              _BitToggle(
                label: chmodClass.letter == 'u'
                    ? 'read'
                    : '${chmodClass.letter} read',
                bit: 'r',
                octalBit: 4,
                value: bits.read,
                octalValue: bits.octal,
                onChanged: () => _toggleBit(chmodClass, 'r'),
              ),
              _BitToggle(
                label: 'write',
                bit: 'w',
                octalBit: 2,
                value: bits.write,
                octalValue: bits.octal,
                onChanged: () => _toggleBit(chmodClass, 'w'),
              ),
              _BitToggle(
                label: 'execute',
                bit: 'x',
                octalBit: 1,
                value: bits.execute,
                octalValue: bits.octal,
                onChanged: () => _toggleBit(chmodClass, 'x'),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 74,
          child: TextButton(
            onPressed: () => _set(info.setAll(chmodClass, false)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 22),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 10.5),
            ),
            child: const Text('None'),
          ),
        ),
        SizedBox(
          width: 58,
          child: TextButton(
            onPressed: () => _set(info.setAll(chmodClass, true)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 22),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 10.5),
            ),
            child: const Text('All'),
          ),
        ),
      ],
    );
  }

  Widget _buildPresets(BuildContext context, ChmodInfo? info) {
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Common modes',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              color: context.appColors.editorText,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in commonModes.entries)
                ToolButton(
                  label: entry.key,
                  onPressed: () => _applyMode(entry.key),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            commonModes[info?.octal] ?? '',
            style: mutedToolTextStyle(context, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(BuildContext context) {
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              color: context.appColors.editorText,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _report.text.isEmpty
                ? 'Select permission bits to see the breakdown.'
                : _report.text,
            style: TextStyle(
              fontFamily: 'Menlo',
              fontSize: 11.5,
              height: 1.5,
              color: context.appColors.editorText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: appColors.accent.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.accent),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Menlo',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: appColors.accent,
        ),
      ),
    );
  }
}

class _BitToggle extends StatelessWidget {
  const _BitToggle({
    required this.label,
    required this.bit,
    required this.octalBit,
    required this.value,
    required this.octalValue,
    required this.onChanged,
  });

  final String label;
  final String bit;
  final int octalBit;
  final bool value;
  final int octalValue;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final highlighted = value && octalValue & octalBit != 0;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: highlighted
              ? appColors.accent.withAlpha(34)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onChanged,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: highlighted ? appColors.accent : appColors.border,
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      highlighted
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 14,
                      color: highlighted
                          ? appColors.accent
                          : appColors.mutedText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      bit,
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 12,
                        color: highlighted
                            ? appColors.editorText
                            : appColors.mutedText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: highlighted
                            ? appColors.editorText
                            : appColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecialToggle extends StatelessWidget {
  const _SpecialToggle({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (next) => onChanged(next ?? false),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(label, style: const TextStyle(fontSize: 11.5)),
        const SizedBox(width: 4),
        Text(hint, style: mutedToolTextStyle(context, fontSize: 11)),
      ],
    );
  }
}

Widget buildChmodCalculator() {
  return const _ChmodCalculatorView();
}
