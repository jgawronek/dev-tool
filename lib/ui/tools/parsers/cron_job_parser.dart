/// Cron job parser tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

class _CronJobParserView extends StatefulWidget {
  const _CronJobParserView();

  @override
  State<_CronJobParserView> createState() => _CronJobParserViewState();
}

class _CronSchedule {
  const _CronSchedule({
    required this.minutes,
    required this.hours,
    required this.daysOfMonth,
    required this.months,
    required this.daysOfWeek,
  });

  final Set<int> minutes;
  final Set<int> hours;
  final Set<int> daysOfMonth;
  final Set<int> months;
  final Set<int> daysOfWeek;

  bool matches(DateTime time) {
    if (!minutes.contains(time.minute)) return false;
    if (!hours.contains(time.hour)) return false;
    if (!months.contains(time.month)) return false;
    // In cron, a restricted day-of-month OR a restricted day-of-week makes
    // the day match; both restricted means either may fire.
    final domRestricted = daysOfMonth.length != 31;
    final dowRestricted = daysOfWeek.length != 7;
    if (!domRestricted && !dowRestricted) return true;
    final domOk = domRestricted && daysOfMonth.contains(time.day);
    final dowOk = dowRestricted && daysOfWeek.contains(time.weekday % 7);
    return domOk || dowOk;
  }
}

class _CronJobParserViewState extends State<_CronJobParserView> {
  final TextEditingController _input = TextEditingController(
    text: '*/5 * * * *',
  );
  String _summary = 'Every 5 minutes';
  String _minutes = '';
  String _hours = '(All)';
  String _daysOfMonth = '(All)';
  String _months = '(All)';
  String _daysOfWeek = '(All)';
  List<String> _next = [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  void _parse() {
    final parts = _input.text.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      setState(() {
        _summary = 'Invalid cron expression';
        _minutes = '';
        _hours = '';
        _daysOfMonth = '';
        _months = '';
        _daysOfWeek = '';
        _next = [];
      });
      return;
    }
    final minutes = _parseField(parts[0], 0, 59);
    final hours = _parseField(parts[1], 0, 23);
    final daysOfMonth = _parseField(parts[2], 1, 31);
    final months = _parseField(parts[3], 1, 12);
    final daysOfWeek = _parseField(parts[4], 0, 7);
    if (minutes == null ||
        hours == null ||
        daysOfMonth == null ||
        months == null ||
        daysOfWeek == null) {
      setState(() {
        _summary = 'Invalid cron expression';
        _minutes = '';
        _hours = '';
        _daysOfMonth = '';
        _months = '';
        _daysOfWeek = '';
        _next = [];
      });
      return;
    }
    final schedule = _CronSchedule(
      minutes: minutes,
      hours: hours,
      daysOfMonth: daysOfMonth,
      months: months,
      daysOfWeek: daysOfWeek.map((d) => d % 7).toSet(),
    );

    setState(() {
      _summary = _describe(parts, minutes, hours);
      _minutes = _formatField(minutes);
      _hours = _formatField(hours);
      _daysOfMonth = _formatField(daysOfMonth);
      _months = _formatField(months);
      _daysOfWeek = _formatField(daysOfWeek.map((d) => d % 7).toSet());
      _next = _nextExecutions(schedule);
    });
  }

  String _describe(List<String> parts, Set<int> minutes, Set<int> hours) {
    final othersAllStar = parts.skip(1).every((p) => p == '*');
    if (parts.first == '*' && othersAllStar) return 'Every minute';
    if (othersAllStar && parts.first.startsWith('*/')) {
      final step = int.tryParse(parts.first.substring(2));
      if (step != null) return 'Every $step minutes';
    }
    if (hours.length == 24) {
      return 'At minute${minutes.length == 1 ? '' : 's'} ${_formatField(minutes)} past the hour';
    }
    return 'Runs at ${_formatField(minutes)} past hour${hours.length == 1 ? '' : 's'} ${_formatField(hours)}';
  }

  String _formatField(Set<int> values) {
    if (values.length > 20) return '(many values)';
    final sorted = values.toList()..sort();
    return sorted.join(', ');
  }

  /// Expands a cron field (`*`, `*/step`, `a`, `a-b`, `a-b/step`, lists)
  /// into its set of values, or null when malformed.
  Set<int>? _parseField(String field, int min, int max) {
    final values = <int>{};
    for (final part in field.split(',')) {
      if (part.isEmpty) return null;
      var rangePart = part;
      var step = 1;
      if (rangePart.contains('/')) {
        final bits = rangePart.split('/');
        if (bits.length != 2) return null;
        rangePart = bits[0];
        step = int.tryParse(bits[1]) ?? 0;
        if (step <= 0) return null;
      }
      int? start;
      int? end;
      if (rangePart == '*') {
        start = min;
        end = max;
      } else if (rangePart.contains('-')) {
        final bits = rangePart.split('-');
        if (bits.length != 2) return null;
        start = int.tryParse(bits[0]);
        end = int.tryParse(bits[1]);
      } else {
        final value = int.tryParse(rangePart);
        if (value == null) return null;
        start = value;
        end = rangePart.contains('/') ? max : value;
      }
      if (start == null ||
          end == null ||
          start < min ||
          end > max ||
          start > end) {
        return null;
      }
      for (var v = start; v <= end; v += step) {
        values.add(v);
      }
    }
    return values.isEmpty ? null : values;
  }

  /// Walks forward minute by minute collecting the next runs that satisfy
  /// the whole schedule (bounded to ~400 days of searching).
  List<String> _nextExecutions(_CronSchedule schedule) {
    var current = DateTime.now().add(const Duration(minutes: 1));
    current = DateTime(
      current.year,
      current.month,
      current.day,
      current.hour,
      current.minute,
    );
    final list = <String>[];
    final limit = current.add(const Duration(days: 400));
    while (current.isBefore(limit) && list.length < 5) {
      if (schedule.matches(current)) {
        list.add(
          '${current.year.toString().padLeft(4, '0')}-'
          '${current.month.toString().padLeft(2, '0')}-'
          '${current.day.toString().padLeft(2, '0')} '
          '${current.hour.toString().padLeft(2, '0')}:'
          '${current.minute.toString().padLeft(2, '0')}',
        );
      }
      current = current.add(const Duration(minutes: 1));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        ToolButton(
                          label: 'Clipboard',
                          onPressed: () async {
                            final text = await readClipboardText();
                            setState(() => _input.text = text);
                            _parse();
                          },
                        ),
                        const SizedBox(width: 8),
                        ToolButton(
                          label: 'Sample',
                          onPressed: () {
                            setState(() => _input.text = '*/5 * * * *');
                            _parse();
                          },
                        ),
                        const SizedBox(width: 8),
                        ToolButton(
                          label: 'Clear',
                          onPressed: () {
                            setState(() => _input.clear());
                            _parse();
                          },
                        ),
                        const SizedBox(width: 8),
                        ToolButton(
                          label: 'Copy',
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: _input.text)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const SmallDropdown(
                  items: ['Pick an example...'],
                  initialValue: 'Pick an example...',
                ),
              ],
            ),
            const SizedBox(height: 8),
            InlineTextField(
              hintText: '*/5 * * * *',
              controller: _input,
              onChanged: (_) => _parse(),
            ),
            const SizedBox(height: 12),
            Text(_summary),
            const SizedBox(height: 12),
            Text('Minutes: $_minutes'),
            Text('Hours: $_hours'),
            Text('Day of Month: $_daysOfMonth'),
            Text('Months: $_months'),
            Text('Day of Week: $_daysOfWeek'),
            const SizedBox(height: 12),
            const Text('Next executions:'),
            for (final item in _next) Text(item),
          ],
        ),
      ),
    );
  }
}

Widget buildCronJobParser() {
  return const _CronJobParserView();
}
