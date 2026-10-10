/// String inspector tool view.
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';
import '../../tool_sample_action.dart';

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

    return ToolSampleAction(
      onPressed: _setSample,
      child: buildAdaptiveSplit(
        initialRatio: 0.30,
        minFirstExtent: 140,
        minSecondExtent: 300,
        first: EditorPane(
          label: 'Input',
          actions: [],
          controller: _input,
          placeholder: 'Type or paste text to inspect...',
          showHeader: true,
        ),
        second: ToolPanel(
          title: 'Text analysis',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 920 ? 7 : 4;
                    const gap = 8.0;
                    final width =
                        (constraints.maxWidth - ((columns - 1) * gap)) /
                        columns;
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
                    decoration: toolSurfaceDecoration(context),
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
                              onChanged: (value) => setState(
                                () => _caseSensitive = value ?? true,
                              ),
                            ),
                            Text(
                              'Case sensitive',
                              style: TextStyle(
                                color: context.appColors.editorText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: sortedCounts.isEmpty
                              ? Center(
                                  child: Text(
                                    'No words yet',
                                    style: mutedToolTextStyle(context),
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
          ),
        ),
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
        decoration: toolSurfaceDecoration(context, radius: 6),
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

Widget buildStringInspector() {
  return const _StringInspectorView();
}
