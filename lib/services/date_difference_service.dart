/// Difference between two ISO-8601 instants, with explicit timezone offsets.
library;

class DateDifferenceResult {
  const DateDifferenceResult({this.report, this.error});
  final String? report;
  final String? error;
}

DateDifferenceResult dateDifference(String start, String end) {
  if (start.trim().isEmpty || end.trim().isEmpty) {
    return const DateDifferenceResult(
      error: 'Enter both dates in ISO 8601 format.',
    );
  }
  // A timezone is required so results cannot silently depend on the computer's
  // local timezone. DateTime.parse normalizes explicit offsets to UTC.
  final zone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);
  if (!zone.hasMatch(start.trim()) || !zone.hasMatch(end.trim())) {
    return const DateDifferenceResult(
      error: 'Include a timezone (Z or ±HH:MM) on both dates.',
    );
  }
  final first = DateTime.tryParse(start.trim());
  final last = DateTime.tryParse(end.trim());
  if (first == null || last == null) {
    return const DateDifferenceResult(
      error: 'Invalid ISO 8601 date or timezone.',
    );
  }
  final micros = last.microsecondsSinceEpoch - first.microsecondsSinceEpoch;
  final positive = micros.abs();
  final days = positive ~/ Duration.microsecondsPerDay;
  final hours = (positive ~/ Duration.microsecondsPerHour) % 24;
  final minutes = (positive ~/ Duration.microsecondsPerMinute) % 60;
  final seconds = (positive ~/ Duration.microsecondsPerSecond) % 60;
  final milliseconds = (positive ~/ Duration.microsecondsPerMillisecond) % 1000;
  final remainingMicros = positive % 1000;
  return DateDifferenceResult(
    report: [
      'Start (UTC): ${first.toUtc().toIso8601String()}',
      'End (UTC):   ${last.toUtc().toIso8601String()}',
      'Direction: ${micros < 0
          ? 'End is before start'
          : micros == 0
          ? 'Same instant'
          : 'End is after start'}',
      'Elapsed: $days days, $hours hours, $minutes minutes, $seconds seconds, '
          '$milliseconds milliseconds, $remainingMicros microseconds',
      'Total seconds: ${(micros / Duration.microsecondsPerSecond).toStringAsFixed(6)}',
    ].join('\n'),
  );
}
