/// Log-format timestamp recognition and conversion.
///
/// Handles the formats that actually appear in server logs and incident
/// data: ISO 8601, Apache/CLF bracketed dates, syslog, nginx, and bare
/// epoch values in seconds through nanoseconds.
library;

/// The timestamp formats the extractor recognises.
enum TimestampFormat {
  iso8601('ISO 8601'),
  apache('Apache / CLF'),
  nginx('nginx'),
  syslog('Syslog'),
  rfc2822('RFC 2822'),
  epoch('Epoch (s/ms/us/ns)');

  const TimestampFormat(this.label);

  final String label;
}

/// One recognised timestamp and how it was read.
class TimestampHit {
  const TimestampHit({
    required this.raw,
    required this.start,
    required this.end,
    required this.format,
    required this.instant,
    required this.assumeUtc,
  });

  /// The matched text.
  final String raw;

  /// Character offsets in the source, so callers can highlight them.
  final int start;
  final int end;

  final TimestampFormat format;

  /// The parsed moment.
  final DateTime instant;

  /// True when the format carried no timezone and UTC was assumed.
  final bool assumeUtc;

  /// ISO 8601 rendering, always with an explicit offset.
  String get iso => instant.toIso8601String();
}

/// Result of an extraction run.
class TimestampOutcome {
  const TimestampOutcome({
    required this.hits,
    required this.error,
  });

  final List<TimestampHit> hits;
  final String? error;

  bool get isEmpty => hits.isEmpty;
}

/// Scans [text] for timestamps of any recognised [format], or only [format]
/// when one is supplied.
TimestampOutcome extractTimestamps(String text, {TimestampFormat? format}) {
  if (text.trim().isEmpty) {
    return const TimestampOutcome(hits: [], error: 'Paste some text to scan.');
  }
  final patterns = <TimestampFormat, RegExp>{
    TimestampFormat.iso8601: RegExp(
      r'\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d{1,9})?(?:Z|[+-]\d{2}:?\d{2})?',
    ),
    TimestampFormat.apache: RegExp(
      r'\d{1,2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2} [+-]\d{4}',
    ),
    TimestampFormat.nginx: RegExp(
      r'\d{1,2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}',
    ),
    TimestampFormat.syslog: RegExp(
      r'(?:[A-Za-z]{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})'
      r'(?:\s+\d{4})?|(?:\d{4}\s+[A-Za-z]{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})',
    ),
    TimestampFormat.rfc2822: RegExp(
      r'(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),\s+\d{1,2}\s+[A-Za-z]{3}\s+\d{4}\s+'
      r'\d{2}:\d{2}:\d{2}\s+[+-]\d{4}',
    ),
    TimestampFormat.epoch: RegExp(
      r'(?<![\d.])\d{10}(?:\.\d+)?(?![\d.])|(?<![\d.])\d{13}(?![\d.])|(?<![\d.])\d{16}(?![\d.])|(?<![\d.])\d{19}(?![\d.])',
    ),
  };

  final hits = <TimestampHit>[];
  for (final entry in patterns.entries) {
    if (format != null && format != entry.key) continue;
    for (final match in entry.value.allMatches(text)) {
      final parsed = _parse(match.group(0)!, entry.key);
      if (parsed == null) continue;
      hits.add(
        TimestampHit(
          raw: match.group(0)!,
          start: match.start,
          end: match.end,
          format: entry.key,
          instant: parsed,
          assumeUtc: _isUtcAssumed(entry.key, match.group(0)!),
        ),
      );
    }
  }
  // Offsets can overlap when a format nests inside another; keep the first
  // match at each position so the output stays ordered and unambiguous.
  hits.sort((a, b) => a.start.compareTo(b.start));
  final deduped = <TimestampHit>[];
  var lastEnd = -1;
  for (final hit in hits) {
    if (hit.start >= lastEnd) {
      deduped.add(hit);
      lastEnd = hit.end;
    }
  }
  return TimestampOutcome(hits: deduped, error: null);
}

bool _isUtcAssumed(TimestampFormat format, String raw) => switch (format) {
      TimestampFormat.iso8601 || TimestampFormat.rfc2822 =>
        !raw.contains('Z') && !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw),
      TimestampFormat.nginx || TimestampFormat.syslog => true,
      _ => false,
    };

DateTime? _parse(String raw, TimestampFormat format) {
  switch (format) {
    case TimestampFormat.iso8601:
      // DateTime.parse accepts a space separator and a comma fraction.
      final normalized = raw.replaceFirst(' ', 'T').replaceFirst(',', '.');
      return DateTime.tryParse(normalized.endsWith('Z')
          ? normalized
          : (RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(normalized)
              ? normalized
              : '${normalized}Z'));
    case TimestampFormat.apache:
      return _parseApache(raw, hasOffset: true);
    case TimestampFormat.nginx:
      return _parseApache(raw, hasOffset: false);
    case TimestampFormat.rfc2822:
      return DateTime.tryParse(raw);
    case TimestampFormat.syslog:
      return _parseSyslog(raw);
    case TimestampFormat.epoch:
      return _parseEpoch(raw);
  }
}

const _months = <String, int>{
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

DateTime? _parseApache(String raw, {required bool hasOffset}) {
  final match = RegExp(
    r'(\d{1,2})/([A-Za-z]{3})/(\d{4}):(\d{2}):(\d{2}):(\d{2})(?:\s+([+-]\d{4}))?',
  ).firstMatch(raw);
  if (match == null) return null;
  final month = _months[match.group(2)!.toLowerCase()];
  if (month == null) return null;
  // A `+0700` stamp means local time runs ahead of UTC, so the UTC instant is
  // the wall-clock reading minus that offset.
  var offsetMinutes = 0;
  final zone = match.group(7);
  if (hasOffset && zone != null) {
    final sign = zone.startsWith('-') ? -1 : 1;
    offsetMinutes =
        sign * (int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(3, 5)));
  }
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  ).subtract(Duration(minutes: offsetMinutes));
}

/// Syslog omits the year, so the current one is assumed, as `journalctl` and
/// `logread` do when rendering.
DateTime? _parseSyslog(String raw) {
  final withoutYear = RegExp(
    r'^([A-Za-z]{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})$',
  ).firstMatch(raw);
  if (withoutYear != null) {
    final month = _months[withoutYear.group(1)!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      DateTime.now().year,
      month,
      int.parse(withoutYear.group(2)!),
      int.parse(withoutYear.group(3)!),
      int.parse(withoutYear.group(4)!),
      int.parse(withoutYear.group(5)!),
    );
  }
  final withYear = RegExp(
    r'^(\d{4})\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})$',
  ).firstMatch(raw);
  if (withYear == null) return null;
  final month = _months[withYear.group(2)!.toLowerCase()];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(withYear.group(1)!),
    month,
    int.parse(withYear.group(3)!),
    int.parse(withYear.group(4)!),
    int.parse(withYear.group(5)!),
    int.parse(withYear.group(6)!),
  );
}

/// Distinguishes seconds, milliseconds, microseconds and nanoseconds by digit
/// count, which is the only signal a bare epoch number carries.
DateTime? _parseEpoch(String raw) {
  final value = double.tryParse(raw);
  if (value == null) return null;
  final digits = raw.contains('.')
      ? raw.split('.').first.length
      : raw.length;
  final divisor = switch (digits) {
    10 => 1.0,
    13 => 1000.0,
    16 => 1000000.0,
    19 => 1000000000.0,
    _ => null,
  };
  if (divisor == null) return null;
  final micros = (value / divisor) * 1000000;
  return DateTime.fromMicrosecondsSinceEpoch(micros.round(), isUtc: true);
}

/// Renders the hits as a table for the output pane.
String renderTimestampReport(List<TimestampHit> hits) {
  if (hits.isEmpty) return 'No timestamps found.';
  final buffer = StringBuffer()
    ..writeln('${hits.length} timestamp${hits.length == 1 ? '' : 's'} found')
    ..writeln();
  for (final hit in hits) {
    buffer
      ..writeln(hit.raw)
      ..writeln('  format   ${hit.format.label}')
      ..writeln('  instant  ${hit.iso}')
      ..writeln('  offset   ${hit.instant.timeZoneName}'
          '${hit.assumeUtc ? ' (assumed)' : ''}')
      ..writeln('  at       chars ${hit.start}-${hit.end}')
      ..writeln();
  }
  return buffer.toString().trimRight();
}
