/// Semantic version calculator tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/semver_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

/// Versions offered for range resolution, mirroring a typical release history.
final _knownVersions = <String>[
  '0.9.0',
  '0.9.9',
  '1.0.0-alpha',
  '1.0.0',
  '1.0.1',
  '1.1.0',
  '1.2.0',
  '1.2.3',
  '1.2.4',
  '1.5.0',
  '1.9.9',
  '2.0.0-rc.1',
  '2.0.0',
  '3.0.0',
].map(parseSemVer).whereType<SemVer>().toList();

class _SemVerCalculatorView extends StatefulWidget {
  const _SemVerCalculatorView();

  @override
  State<_SemVerCalculatorView> createState() => _SemVerCalculatorViewState();
}

class _SemVerCalculatorViewState extends State<_SemVerCalculatorView> {
  final TextEditingController _left = TextEditingController(text: '1.2.3');
  final TextEditingController _right = TextEditingController(text: '2.0.0');
  final TextEditingController _range = TextEditingController(text: '^1.2.0');
  final TextEditingController _output = TextEditingController();

  String _status = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _range.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final left = parseSemVer(_left.text);
    final right = parseSemVer(_right.text);
    final resolved = resolveRange(_range.text, _knownVersions);

    final buffer = StringBuffer();
    if (left != null && right != null) {
      buffer
        ..writeln(compareReport(left, right))
        ..writeln()
        ..writeln('Next major   ${bumpSemVer(left, 'major')}')
        ..writeln('Next minor   ${bumpSemVer(left, 'minor')}')
        ..writeln('Next patch   ${bumpSemVer(left, 'patch')}');
    }

    if (_range.text.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Range "${_range.text.trim()}"');
      if (resolved.matched.isEmpty) {
        buffer.writeln('  matches none of the known versions');
      } else {
        for (final version in resolved.matched) {
          buffer.writeln('  $version');
        }
        buffer.writeln('  highest satisfying: ${resolved.highest}');
      }
    }

    final invalid =
        (left == null && _left.text.trim().isNotEmpty) ||
        (right == null && _right.text.trim().isNotEmpty);
    setState(() {
      _output.text = buffer.toString().trimRight();
      _status = _summarise(left, right, resolved);
      _error = invalid
          ? 'Not a valid semantic version. Expected MAJOR.MINOR.PATCH.'
          : null;
    });
  }

  String _summarise(
    SemVer? left,
    SemVer? right,
    ({String highest, List<SemVer> matched, List<SemVer> candidates}) resolved,
  ) {
    final parts = <String>[];
    if (left != null && right != null) {
      final result = compareSemVer(left, right);
      parts.add(
        result == 0
            ? 'A and B are equal'
            : result < 0
            ? 'A is older'
            : 'A is newer',
      );
      parts.add(diffSemVer(left, right).summary);
    }
    if (resolved.matched.isNotEmpty) {
      parts.add('range -> ${resolved.highest}');
    }
    return parts.join('  ·  ');
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  void _swap() {
    setState(() {
      final temp = _left.text;
      _left.text = _right.text;
      _right.text = temp;
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInputs(context),
          const SizedBox(height: 12),
          Expanded(child: _buildOutput(context)),
          if (_error != null || _status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _error ?? _status,
              style: _error != null
                  ? errorToolTextStyle(context)
                  : mutedToolTextStyle(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputs(BuildContext context) {
    return ToolPanel(
      title: 'Versions and range',
      expand: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 132,
                  child: _Field(
                    label: 'A',
                    controller: _left,
                    onChanged: (_) => _run(),
                  ),
                ),
                SizedBox(
                  width: 132,
                  child: _Field(
                    label: 'B',
                    controller: _right,
                    onChanged: (_) => _run(),
                  ),
                ),
                ToolButton(label: 'Swap', onPressed: _swap),
                SizedBox(
                  width: 132,
                  child: _Field(
                    label: 'Range',
                    controller: _range,
                    onChanged: (_) => _run(),
                  ),
                ),
                ToolButton(label: 'Copy', onPressed: _copyOutput),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Range supports ^ ~ >= > < <= =, x wildcards, "1.2.3 - 1.2.9", '
              'and "||" alternatives.',
              style: mutedToolTextStyle(context, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutput(BuildContext context) {
    return ToolPanel(
      title: 'Comparison',
      expand: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: SingleChildScrollView(
          child: SelectableText(
            _output.text.isEmpty
                ? 'Enter two versions to compare.'
                : _output.text,
            style: TextStyle(
              fontFamily: 'Menlo',
              fontSize: 12,
              height: 1.55,
              color: context.appColors.editorText,
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(
        fontFamily: 'Menlo',
        fontSize: 12,
        color: appColors.editorText,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 11, color: appColors.mutedText),
        hintText: '1.2.3',
        hintStyle: TextStyle(fontSize: 12, color: appColors.mutedText),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: appColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: appColors.border),
        ),
      ),
    );
  }
}

Widget buildSemVerCalculator() {
  return const _SemVerCalculatorView();
}
