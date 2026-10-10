/// Unix Time Converter tool view.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

class _UnixTimeConverterView extends StatefulWidget {
  const _UnixTimeConverterView();

  @override
  State<_UnixTimeConverterView> createState() => _UnixTimeConverterViewState();
}

class _UnixTimeConverterViewState extends State<_UnixTimeConverterView> {
  final TextEditingController _input = TextEditingController();
  String _format = 'Unix time (seconds since epoch)';
  String? _leftTimezone;
  String? _rightTimezone;
  DateTime? _currentUtcDate;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String _localTimezoneLabel() {
    final now = DateTime.now();
    return '${now.timeZoneName} (${_formatUtcOffset(now.timeZoneOffset)})';
  }

  List<String> _timezoneOptions() {
    final zones = <String>[_localTimezoneLabel(), 'UTC'];
    for (var hour = -12; hour <= 14; hour++) {
      if (hour == 0) continue;
      final sign = hour < 0 ? '-' : '+';
      zones.add('UTC$sign${hour.abs().toString().padLeft(2, '0')}:00');
    }
    return zones;
  }

  String _selectedTimezoneLabel(String? timezone, {required String fallback}) {
    final options = _timezoneOptions();
    if (timezone != null && options.contains(timezone)) return timezone;
    if (options.contains(fallback)) return fallback;
    return options.first;
  }

  String _leftTimezoneLabel() {
    return _selectedTimezoneLabel(
      _leftTimezone,
      fallback: _localTimezoneLabel(),
    );
  }

  String _rightTimezoneLabel() {
    return _selectedTimezoneLabel(_rightTimezone, fallback: 'UTC');
  }

  DateTime _timezoneDate(DateTime utcDate, String timezone) {
    if (timezone == _localTimezoneLabel()) return utcDate.toLocal();
    final offset = _parseTimezoneOffset(timezone) ?? Duration.zero;
    return utcDate.add(offset);
  }

  String _timezoneOffsetLabel(DateTime utcDate, String timezone) {
    if (timezone == _localTimezoneLabel()) {
      final localDate = utcDate.toLocal();
      return '${localDate.timeZoneName} (${_formatUtcOffset(localDate.timeZoneOffset)})';
    }
    return timezone == 'UTC' ? 'UTC+00:00' : timezone;
  }

  Duration? _parseTimezoneOffset(String timezone) {
    if (timezone == 'UTC') return Duration.zero;
    final match = RegExp(r'^UTC([+-])(\d{2}):(\d{2})$').firstMatch(timezone);
    if (match == null) return null;
    final sign = match.group(1) == '-' ? -1 : 1;
    final hours = int.parse(match.group(2)!);
    final minutes = int.parse(match.group(3)!);
    return Duration(minutes: sign * (hours * 60 + minutes));
  }

  _TimezoneDetails? _detailsFor(String timezone) {
    final utcDate = _currentUtcDate;
    if (utcDate == null) return null;
    final selectedDate = _timezoneDate(utcDate, timezone);
    final offset = timezone == _localTimezoneLabel()
        ? selectedDate.timeZoneOffset
        : _parseTimezoneOffset(timezone) ?? Duration.zero;
    return _TimezoneDetails(
      dateTime: _formatDisplayDateTime(selectedDate),
      offset: _timezoneOffsetLabel(utcDate, timezone),
      utcIso: utcDate.toIso8601String(),
      relative: _relativeFromNow(utcDate.toLocal()),
      unixTime: (utcDate.millisecondsSinceEpoch ~/ 1000).toString(),
      unixMilliseconds: utcDate.millisecondsSinceEpoch.toString(),
      unixNanoseconds: (utcDate.microsecondsSinceEpoch * 1000).toString(),
      rfc3339: _formatRfc3339(selectedDate, offset),
      rfc1123: _formatRfc1123(selectedDate, offset),
      dayOfYear: _calcDayOfYear(selectedDate).toString(),
      weekOfYear: _calcWeekOfYear(selectedDate).toString(),
      isLeapYear: _isLeap(selectedDate.year) ? 'Yes' : 'No',
    );
  }

  void _changeLeftTimezone(String timezone) {
    setState(() => _leftTimezone = timezone);
  }

  void _changeRightTimezone(String timezone) {
    setState(() => _rightTimezone = timezone);
  }

  void _convert() {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      _clearOutputs();
      setState(() => _error = null);
      return;
    }
    final value = evaluateNumberExpression(raw);
    if (value == null) {
      setState(() => _error = 'Invalid number input.');
      return;
    }
    final date = switch (_format) {
      'Unix time (milliseconds since epoch)' =>
        DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true),
      'Unix time (nanoseconds since epoch)' =>
        DateTime.fromMicrosecondsSinceEpoch(value.round() ~/ 1000, isUtc: true),
      _ => DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).round(),
        isUtc: true,
      ),
    };
    setState(() {
      _currentUtcDate = date;
      _error = null;
    });
  }

  void _clearOutputs() {
    _currentUtcDate = null;
  }

  void _setNow() {
    final now = DateTime.now().toUtc();
    setState(() {
      _input.text = switch (_format) {
        'Unix time (milliseconds since epoch)' =>
          now.millisecondsSinceEpoch.toString(),
        'Unix time (nanoseconds since epoch)' =>
          (now.microsecondsSinceEpoch * 1000).toString(),
        _ => (now.millisecondsSinceEpoch ~/ 1000).toString(),
      };
      _currentUtcDate = now;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final timezoneOptions = _timezoneOptions();
    final leftTimezone = _leftTimezoneLabel();
    final rightTimezone = _rightTimezoneLabel();
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ToolToolbar(
              children: [
                const Text(
                  'Input:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                ToolButton(label: 'Now', onPressed: _setNow),
                SmallDropdown(
                  items: const [
                    'Unix time (seconds since epoch)',
                    'Unix time (milliseconds since epoch)',
                    'Unix time (nanoseconds since epoch)',
                  ],
                  initialValue: _format,
                  onChanged: (value) {
                    setState(() => _format = value);
                    _convert();
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              decoration: toolSurfaceDecoration(context, radius: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              constraints: const BoxConstraints(minHeight: 34),
              child: TextField(
                key: const ValueKey('unix-time-input'),
                controller: _input,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isDense: true,
                  hintStyle: TextStyle(color: appColors.mutedText),
                ),
                style: TextStyle(color: appColors.editorText),
                onChanged: (_) => _convert(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tips: Mathematical operators + - * / are supported',
              style: mutedToolTextStyle(context, fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: errorToolTextStyle(context)),
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final leftPanel = _TimezoneDetailsPanel(
                  title: 'Timezone 1',
                  timezoneOptions: timezoneOptions,
                  selectedTimezone: leftTimezone,
                  onTimezoneChanged: _changeLeftTimezone,
                  details: _detailsFor(leftTimezone),
                );
                final rightPanel = _TimezoneDetailsPanel(
                  title: 'Timezone 2',
                  timezoneOptions: timezoneOptions,
                  selectedTimezone: rightTimezone,
                  onTimezoneChanged: _changeRightTimezone,
                  details: _detailsFor(rightTimezone),
                );
                const gap = 10.0;
                const minPanelWidth = 330.0;
                final availableWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : minPanelWidth * 2 + gap;
                final comparisonWidth = max(
                  availableWidth,
                  minPanelWidth * 2 + gap,
                );
                final panelWidth = (comparisonWidth - gap) / 2;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: comparisonWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: panelWidth, child: leftPanel),
                        const SizedBox(width: gap),
                        SizedBox(width: panelWidth, child: rightPanel),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TimezoneDetails {
  const _TimezoneDetails({
    required this.dateTime,
    required this.offset,
    required this.utcIso,
    required this.relative,
    required this.unixTime,
    required this.unixMilliseconds,
    required this.unixNanoseconds,
    required this.rfc3339,
    required this.rfc1123,
    required this.dayOfYear,
    required this.weekOfYear,
    required this.isLeapYear,
  });

  final String dateTime;
  final String offset;
  final String utcIso;
  final String relative;
  final String unixTime;
  final String unixMilliseconds;
  final String unixNanoseconds;
  final String rfc3339;
  final String rfc1123;
  final String dayOfYear;
  final String weekOfYear;
  final String isLeapYear;
}

class _TimezoneDetailsPanel extends StatelessWidget {
  const _TimezoneDetailsPanel({
    required this.title,
    required this.timezoneOptions,
    required this.selectedTimezone,
    required this.onTimezoneChanged,
    required this.details,
  });

  final String title;
  final List<String> timezoneOptions;
  final String selectedTimezone;
  final ValueChanged<String> onTimezoneChanged;
  final _TimezoneDetails? details;

  @override
  Widget build(BuildContext context) {
    final details = this.details;
    return ToolPanel(
      title: title,
      expand: false,
      actions: [
        SmallDropdown(
          items: timezoneOptions,
          initialValue: selectedTimezone,
          width: 180,
          onChanged: onTimezoneChanged,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            if (details == null)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 300),
                alignment: Alignment.center,

                child: Text(
                  'Enter a Unix time or press Now',
                  style: mutedToolTextStyle(context),
                ),
              )
            else ...[
              _UnixDetailRow(label: 'Date/time', value: details.dateTime),
              _UnixDetailRow(label: 'Offset', value: details.offset),
              _UnixDetailRow(label: 'UTC ISO', value: details.utcIso),
              _UnixDetailRow(label: 'Relative', value: details.relative),
              _UnixDetailRow(label: 'Unix sec', value: details.unixTime),
              _UnixDetailRow(label: 'Unix ms', value: details.unixMilliseconds),
              _UnixDetailRow(label: 'Unix ns', value: details.unixNanoseconds),
              _UnixDetailRow(label: 'RFC 3339', value: details.rfc3339),
              _UnixDetailRow(label: 'RFC 1123', value: details.rfc1123),
              Row(
                children: [
                  Expanded(
                    child: _UnixDetailRow(
                      label: 'Day',
                      value: details.dayOfYear,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _UnixDetailRow(
                      label: 'Week',
                      value: details.weekOfYear,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _UnixDetailRow(
                      label: 'Leap',
                      value: details.isLeapYear,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnixDetailRow extends StatelessWidget {
  const _UnixDetailRow({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: appColors.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                _UnixDetailValue(value: value, minHeight: 38),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: appColors.mutedText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _UnixDetailValue(value: value)),
              ],
            ),
    );
  }
}

class _UnixDetailValue extends StatelessWidget {
  const _UnixDetailValue({required this.value, this.minHeight = 36});

  final String value;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: appColors.editorBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: SelectableText(
        value,
        maxLines: 1,
        style: TextStyle(
          color: appColors.editorText,
          fontFamily: 'Menlo',
          fontSize: 12,
        ),
      ),
    );
  }
}

bool _isLeap(int year) {
  if (year % 400 == 0) return true;
  if (year % 100 == 0) return false;
  return year % 4 == 0;
}

String _formatUtcOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final hours = absolute.inHours.toString().padLeft(2, '0');
  final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$minutes';
}

String _formatDisplayDateTime(DateTime date) {
  final buffer = StringBuffer()
    ..write(date.year.toString().padLeft(4, '0'))
    ..write('-')
    ..write(date.month.toString().padLeft(2, '0'))
    ..write('-')
    ..write(date.day.toString().padLeft(2, '0'))
    ..write(' ')
    ..write(date.hour.toString().padLeft(2, '0'))
    ..write(':')
    ..write(date.minute.toString().padLeft(2, '0'))
    ..write(':')
    ..write(date.second.toString().padLeft(2, '0'));
  if (date.millisecond != 0 || date.microsecond != 0) {
    buffer.write('.');
    buffer.write(date.millisecond.toString().padLeft(3, '0'));
    if (date.microsecond != 0) {
      buffer.write(date.microsecond.toString().padLeft(3, '0'));
    }
  }
  return buffer.toString();
}

String _formatRfc3339(DateTime date, Duration offset) {
  final base = _formatDisplayDateTime(date).replaceFirst(' ', 'T');
  return '$base${_formatUtcOffset(offset).replaceFirst('UTC', '')}';
}

String _formatRfc1123(DateTime date, Duration offset) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final offsetText = _formatUtcOffset(offset).replaceFirst('UTC', '');
  return '${weekdays[date.weekday - 1]}, '
      '${date.day.toString().padLeft(2, '0')} '
      '${months[date.month - 1]} '
      '${date.year.toString().padLeft(4, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}:'
      '${date.second.toString().padLeft(2, '0')} '
      '${offsetText.replaceAll(':', '')}';
}

int _calcDayOfYear(DateTime date) {
  final start = DateTime(date.year, 1, 1);
  return date.difference(start).inDays + 1;
}

int _calcWeekOfYear(DateTime date) {
  final dayOfYear = _calcDayOfYear(date);
  return ((dayOfYear - date.weekday + 10) / 7).floor();
}

String _relativeFromNow(DateTime date) {
  final now = DateTime.now();
  final diff = date.difference(now);
  final seconds = diff.inSeconds.abs();
  final minutes = diff.inMinutes.abs();
  final hours = diff.inHours.abs();
  String value;
  if (seconds < 60) {
    value = '$seconds seconds';
  } else if (minutes < 60) {
    value = '$minutes minutes';
  } else {
    value = '$hours hours';
  }
  return diff.isNegative ? '$value ago' : 'in $value';
}

Widget buildUnixTimeConverter() {
  return const _UnixTimeConverterView();
}

/// Evaluates a simple arithmetic expression over decimal numbers
/// (`+`, `-`, `*`, `/` with standard precedence, unary minus allowed).
/// Returns null when the input is not a valid number expression.
double? evaluateNumberExpression(String input) {
  final scanner = _ExpressionScanner(input.replaceAll(RegExp(r'\s+'), ''));
  final value = _parseExpression(scanner);
  if (scanner.hasNext) return null;
  return value;
}

class _ExpressionScanner {
  _ExpressionScanner(this.source);

  final String source;
  var _pos = 0;

  bool get hasNext => _pos < source.length;

  String? peek() => hasNext ? source[_pos] : null;

  String? advance() => hasNext ? source[_pos++] : null;
}

double? _parseExpression(_ExpressionScanner s) {
  var left = _parseTerm(s);
  if (left == null) return null;
  var result = left;
  while (s.hasNext) {
    final op = s.peek();
    if (op != '+' && op != '-') break;
    s.advance();
    final right = _parseTerm(s);
    if (right == null) return null;
    result = op == '+' ? result + right : result - right;
  }
  return result;
}

double? _parseTerm(_ExpressionScanner s) {
  var left = _parseUnary(s);
  if (left == null) return null;
  var result = left;
  while (s.hasNext) {
    final op = s.peek();
    if (op != '*' && op != '/') break;
    s.advance();
    final right = _parseUnary(s);
    if (right == null) return null;
    if (op == '*') {
      result *= right;
    } else {
      if (right == 0) return null;
      result /= right;
    }
  }
  return result;
}

double? _parseUnary(_ExpressionScanner s) {
  if (s.peek() == '-') {
    s.advance();
    final value = _parseUnary(s);
    return value == null ? null : -value;
  }
  if (s.peek() == '+') {
    s.advance();
    return _parseUnary(s);
  }
  return _parseNumber(s);
}

double? _parseNumber(_ExpressionScanner s) {
  final start = s._pos;
  var seenDot = false;
  while (s.hasNext) {
    final ch = s.peek()!;
    final isDigit = ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
    if (isDigit) {
      s.advance();
    } else if (ch == '.' && !seenDot) {
      seenDot = true;
      s.advance();
    } else {
      break;
    }
  }
  if (s._pos == start) return null;
  return double.tryParse(s.source.substring(start, s._pos));
}
