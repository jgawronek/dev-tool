/// Apache common/combined and nginx access-log parsing and aggregation.
///
/// Parsing is line based and tolerant: a line that does not match a known
/// layout is reported rather than silently dropped, which matters when a log
/// has been through logrotate, a proxy, or a multi-line filter.
library;

import 'dart:convert';

/// Which access-log layout a line uses.
enum LogFormat {
  common('Apache common / nginx'),
  combined('Apache combined / nginx'),
  json('JSON lines');

  const LogFormat(this.label);

  final String label;
}

/// One parsed access-log entry.
class LogEntry {
  const LogEntry({
    required this.lineNumber,
    required this.format,
    required this.client,
    required this.ident,
    required this.user,
    required this.timestamp,
    required this.method,
    required this.path,
    required this.protocol,
    required this.status,
    required this.bytes,
    required this.referer,
    required this.userAgent,
    required this.requestTime,
    required this.upstreamTime,
    required this.raw,
    required this.lineage,
  });

  final int lineNumber;
  final LogFormat format;

  /// Remote address, or the leftmost token for a JSON line.
  final String client;

  /// The Apache `ident` field, historically the remote username.
  final String ident;

  /// The authenticated user, or '-' when anonymous.
  final String user;

  /// Request start time parsed to UTC, or null when absent.
  final DateTime? timestamp;

  final String method;
  final String path;
  final String protocol;

  /// HTTP status code.
  final int? status;

  /// Response body size in bytes.
  final int? bytes;

  final String referer;
  final String userAgent;

  /// `$request_time` in seconds, when the log format carries it.
  final double? requestTime;

  /// `$upstream_response_time` in seconds, when present.
  final double? upstreamTime;

  /// The original line.
  final String raw;

  /// Set when the line could not be parsed as a request entry.
  final String? lineage;

  /// Status class such as '2xx', or '-' when unknown.
  String get statusClass => status == null ? '-' : '${status! ~/ 100}xx';

  /// True for a 4xx status.
  bool get isClientError => status != null && status! >= 400 && status! < 500;

  /// True for a 5xx status.
  bool get isServerError => status != null && status! >= 500;

  /// Path without the query string.
  String get pathOnly {
    final query = path.indexOf('?');
    return query == -1 ? path : path.substring(0, query);
  }

  String get query {
    final index = path.indexOf('?');
    return index == -1 ? '' : path.substring(index + 1);
  }
}

/// Aggregate counts for the whole file.
class LogSummary {
  const LogSummary({
    required this.total,
    required this.parsed,
    required this.unparsed,
    required this.statusClasses,
    required this.topClients,
    required this.topPaths,
    required this.topUserAgents,
    required this.topReferers,
    required this.bytesTotal,
    required this.errors,
    required this.slowest,
  });

  final int total;
  final int parsed;
  final int unparsed;
  final Map<String, int> statusClasses;
  final List<MapEntry<String, int>> topClients;
  final List<MapEntry<String, int>> topPaths;
  final List<MapEntry<String, int>> topUserAgents;
  final List<MapEntry<String, int>> topReferers;
  final int bytesTotal;

  /// 4xx and 5xx counts.
  final Map<String, int> errors;

  /// Entries with a `$request_time` at or above 1s, slowest first.
  final List<LogEntry> slowest;
}

/// Result of parsing a whole log.
class LogParseOutcome {
  const LogParseOutcome({
    required this.entries,
    required this.summary,
    required this.blankLines,
  });

  final List<LogEntry> entries;
  final LogSummary summary;

  /// Lines that were empty or whitespace only.
  final int blankLines;
}

/// Parses [input], which may contain multiple lines.
LogParseOutcome parseAccessLog(String input) {
  final lines = const LineSplitter().convert(input);
  final entries = <LogEntry>[];
  var blank = 0;
  var lineNumber = 0;

  for (final raw in lines) {
    lineNumber++;
    final line = raw.trim();
    if (line.isEmpty) {
      blank++;
      continue;
    }
    final entry = parseLogLine(line, lineNumber);
    if (entry != null) {
      entries.add(entry);
    }
  }

  return LogParseOutcome(
    entries: entries,
    summary: _summarize(entries, lines.length),
    blankLines: blank,
  );
}

/// Parses a single line, returning null only when it cannot be recognised.
LogEntry? parseLogLine(String line, int lineNumber) {
  if (line.startsWith('{')) {
    final entry = _parseJsonLine(line, lineNumber);
    if (entry != null) return entry;
  }
  return _parseCombined(line, lineNumber);
}

final _combinedPattern = RegExp(
  r'^(\S+) (\S+) (\S+) '
  r'\[([^\]]+)\] '
  r'"([A-Za-z]+) ([^"]*?) (\S+)?" '
  r'(\d{3}) (\d+|-)'
  r'(?: "([^"]*)" "([^"]*)"(?: (.*?))?)?$',
);

LogEntry? _parseCombined(String line, int lineNumber) {
  final match = _combinedPattern.firstMatch(line);
  if (match == null) {
    return LogEntry(
      lineNumber: lineNumber,
      format: LogFormat.combined,
      client: '',
      ident: '',
      user: '',
      timestamp: null,
      method: '',
      path: '',
      protocol: '',
      status: null,
      bytes: null,
      referer: '',
      userAgent: '',
      requestTime: null,
      upstreamTime: null,
      raw: line,
      lineage: 'Unrecognised layout',
    );
  }

  final extras = match.group(12);
  // A trailing bare number is `$request_time`; some setups append
  // `rt=0.123 urt=0.100` instead.
  var requestTime = double.tryParse(extras?.trim() ?? '');
  var upstreamTime = double.tryParse(extras?.trim() ?? '');
  if (extras != null) {
    final rt = RegExp(r'\brt=([\d.]+)').firstMatch(extras);
    final urt = RegExp(r'\burt=([\d.]+)').firstMatch(extras);
    if (rt != null) requestTime = double.tryParse(rt.group(1)!);
    if (urt != null) upstreamTime = double.tryParse(urt.group(1)!);
  }

  final hasCombined = match.group(10) != null;
  return LogEntry(
    lineNumber: lineNumber,
    format: hasCombined ? LogFormat.combined : LogFormat.common,
    client: match.group(1)!,
    ident: match.group(2)!,
    user: match.group(3)!,
    timestamp: parseApacheDate(match.group(4)!),
    method: match.group(5)!,
    path: match.group(6) ?? '',
    protocol: match.group(7) ?? '',
    status: int.tryParse(match.group(8)!),
    bytes: match.group(9) == '-' ? 0 : int.tryParse(match.group(9)!),
    referer: match.group(10) ?? '',
    userAgent: match.group(11) ?? '',
    requestTime: requestTime,
    upstreamTime: upstreamTime,
    raw: line,
    lineage: null,
  );
}

const _jsonTimeKeys = [
  'time',
  'time_local',
  'timestamp',
  '@timestamp',
  'start_time',
];

const _jsonStatusKeys = ['status', 'status_code', 'http_status', 'response_code'];
const _jsonPathKeys = ['request_uri', 'uri', 'url', 'path', 'request'];
const _jsonClientKeys = ['remote_addr', 'remote_ip', 'client_ip', 'ip', 'client'];
const _jsonAgentKeys = ['http_user_agent', 'user_agent', 'agent', 'ua'];
const _jsonRefererKeys = ['http_referer', 'referer', 'referrer'];
const _jsonUserKeys = ['remote_user', 'user', 'username', 'auth'];
const _jsonBytesKeys = ['body_bytes_sent', 'bytes_sent', 'size', 'bytes'];
const _jsonMethodKeys = ['request_method', 'method', 'verb'];
const _jsonProtoKeys = ['server_protocol', 'protocol', 'scheme'];
const _jsonRtKeys = ['request_time', 'requestTime', 'duration', 'elapsed'];

LogEntry? _parseJsonLine(String line, int lineNumber) {
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final fields = decoded;

  String? pick(List<String> keys) {
    for (final key in keys) {
      final value = fields[key];
      if (value != null && '$value'.isNotEmpty) return '$value';
    }
    return null;
  }

  DateTime? time;
  final rawTime = pick(_jsonTimeKeys);
  if (rawTime != null) {
    time = DateTime.tryParse(rawTime);
    if (time == null) {
      final epoch = double.tryParse(rawTime);
      if (epoch != null) {
        time = DateTime.fromMillisecondsSinceEpoch(
          (epoch * 1000).round(),
          isUtc: true,
        );
      }
    }
  }

  var method = '';
  var path = '';
  final request = pick(_jsonPathKeys);
  if (request != null) {
    final split = RegExp(r'^(\S+)\s+(\S+)(?:\s+(\S+))?').firstMatch(request);
    if (split != null) {
      method = split.group(1)!;
      path = split.group(2)!;
    } else {
      path = request;
    }
  }
  method = pick(_jsonMethodKeys) ?? method;

  final status = int.tryParse(pick(_jsonStatusKeys) ?? '');
  final bytes = int.tryParse(pick(_jsonBytesKeys) ?? '');
  final rt = double.tryParse(pick(_jsonRtKeys) ?? '');

  return LogEntry(
    lineNumber: lineNumber,
    format: LogFormat.json,
    client: pick(_jsonClientKeys) ?? '-',
    ident: '',
    user: pick(_jsonUserKeys) ?? '-',
    timestamp: time,
    method: method,
    path: path,
    protocol: pick(_jsonProtoKeys) ?? '',
    status: status,
    bytes: bytes,
    referer: pick(_jsonRefererKeys) ?? '',
    userAgent: pick(_jsonAgentKeys) ?? '',
    requestTime: rt,
    upstreamTime: null,
    raw: line,
    lineage: null,
  );
}

final _apacheMonths = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// Parses `10/Oct/2000:13:55:36 -0700` into UTC.
DateTime? parseApacheDate(String value) {
  final match = RegExp(
    r'(\d{2})/([A-Za-z]{3})/(\d{4}):(\d{2}):(\d{2}):(\d{2})\s*([+-]\d{4})?',
  ).firstMatch(value);
  if (match == null) return null;
  final month = _apacheMonths[match.group(2)!];
  if (month == null) return null;
  final offset = match.group(7);
  var utc = DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
  if (offset != null) {
    final sign = offset.startsWith('-') ? -1 : 1;
    final hours = int.parse(offset.substring(1, 3));
    final minutes = int.parse(offset.substring(3, 5));
    utc = utc.subtract(Duration(minutes: sign * (hours * 60 + minutes)));
  }
  return utc;
}

LogSummary _summarize(List<LogEntry> entries, int total) {
  final classes = <String, int>{};
  final clients = <String, int>{};
  final paths = <String, int>{};
  final agents = <String, int>{};
  final referers = <String, int>{};
  final errors = <String, int>{'4xx': 0, '5xx': 0};
  var bytesTotal = 0;

  for (final entry in entries) {
    if (entry.lineage != null) continue;
    classes.update(entry.statusClass, (v) => v + 1, ifAbsent: () => 1);
    clients.update(entry.client, (v) => v + 1, ifAbsent: () => 1);
    paths.update(entry.pathOnly, (v) => v + 1, ifAbsent: () => 1);
    if (entry.userAgent.isNotEmpty) {
      agents.update(entry.userAgent, (v) => v + 1, ifAbsent: () => 1);
    }
    if (entry.referer.isNotEmpty && entry.referer != '-') {
      referers.update(entry.referer, (v) => v + 1, ifAbsent: () => 1);
    }
    if (entry.isClientError) errors['4xx'] = errors['4xx']! + 1;
    if (entry.isServerError) errors['5xx'] = errors['5xx']! + 1;
    bytesTotal += entry.bytes ?? 0;
  }

  final slowest = entries.where((e) => (e.requestTime ?? 0) >= 1).toList()
    ..sort((a, b) => (b.requestTime ?? 0).compareTo(a.requestTime ?? 0));

  return LogSummary(
    total: total,
    parsed: entries.where((e) => e.lineage == null).length,
    unparsed: entries.where((e) => e.lineage != null).length,
    statusClasses: _sorted(classes),
    topClients: _top(clients, 10),
    topPaths: _top(paths, 10),
    topUserAgents: _top(agents, 10),
    topReferers: _top(referers, 10),
    bytesTotal: bytesTotal,
    errors: errors,
    slowest: slowest.take(10).toList(),
  );
}

Map<String, int> _sorted(Map<String, int> source) {
  final keys = source.keys.toList()..sort();
  return {for (final key in keys) key: source[key]!};
}

List<MapEntry<String, int>> _top(Map<String, int> source, int limit) {
  final entries = source.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return entries.take(limit).toList();
}

/// Renders a per-entry table.
String renderLogTable(LogParseOutcome outcome) {
  if (outcome.entries.isEmpty) return 'No log lines found.';
  final buffer = StringBuffer()
    ..writeln('LINE  TIME (UTC)             CLIENT        '
        'METHOD  STATUS  BYTES  RT      PATH');
  for (final entry in outcome.entries) {
    if (entry.lineage != null) {
      buffer.writeln(
        '${entry.lineNumber.toString().padRight(5)} '
        '!! ${entry.lineage}: ${_clip(entry.raw, 72)}',
      );
      continue;
    }
    final time = entry.timestamp == null
        ? '-'
        : entry.timestamp!.toIso8601String().replaceFirst('T', ' ');
    final rt = entry.requestTime == null
        ? '-'
        : '${entry.requestTime!.toStringAsFixed(3)}s';
    buffer.writeln(
      '${entry.lineNumber.toString().padRight(5)} '
      '${time.padRight(22)} '
      '${entry.client.padRight(14)} '
      '${entry.method.padRight(6)} '
      '${(entry.status?.toString() ?? '-').padLeft(6)}  '
      '${(entry.bytes?.toString() ?? '-').padLeft(5)}  '
      '${rt.padRight(7)} '
      '${_clip(entry.path, 60)}',
    );
  }
  return buffer.toString().trimRight();
}

/// Renders the aggregate section.
String renderLogSummary(LogParseOutcome outcome) {
  final s = outcome.summary;
  final buffer = StringBuffer()
    ..writeln('Lines read     ${s.total}')
    ..writeln('Parsed         ${s.parsed}')
    ..writeln('Unrecognised   ${s.unparsed}');
  if (outcome.blankLines > 0) {
    buffer.writeln('Blank          ${outcome.blankLines}');
  }
  buffer
    ..writeln('Response bytes $s.bytesTotal')
    ..writeln('Client errors  ${s.errors['4xx']}')
    ..writeln('Server errors  ${s.errors['5xx']}');

  void section(String title, Map<String, int> values) {
    if (values.isEmpty) return;
    buffer..writeln()..writeln(title);
    for (final entry in values.entries) {
      buffer.writeln('  ${entry.key.padRight(60)} ${entry.value}');
    }
  }

  section('Status classes', s.statusClasses);
  section('Top clients', Map.fromEntries(s.topClients));
  section('Top paths', Map.fromEntries(s.topPaths));
  section('Top user agents', Map.fromEntries(s.topUserAgents));
  section('Top referers', Map.fromEntries(s.topReferers));

  if (s.slowest.isNotEmpty) {
    buffer..writeln()..writeln('Slowest requests (>= 1s)');
    for (final entry in s.slowest) {
      buffer.writeln(
        '  ${entry.requestTime!.toStringAsFixed(3)}s  '
        '${entry.status}  ${_clip(entry.path, 60)}',
      );
    }
  }
  return buffer.toString().trimRight();
}

String _clip(String value, int limit) =>
    value.length <= limit ? value : '${value.substring(0, limit - 1)}…';
