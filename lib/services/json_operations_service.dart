/// JSON transformations shared by the formatter's live preview.
library;

import 'dart:convert';

enum JsonOperation {
  prettify('Prettify'),
  minify('Minify'),
  stringify('Stringify'),
  xml('JSON → XML'),
  escape('Escape'),
  sortKeys('Sort keys'),
  sortArrays('Sort arrays');

  const JsonOperation(this.label);
  final String label;
}

/// Transforms a successfully decoded JSON value. Validation and its precise
/// error positions remain the responsibility of the existing JSON session.
String transformJson(Object? value, JsonOperation operation, String indent) {
  switch (operation) {
    case JsonOperation.prettify:
      return JsonEncoder.withIndent(indent).convert(value);
    case JsonOperation.minify:
      return jsonEncode(value);
    case JsonOperation.stringify:
      return jsonEncode(jsonEncode(value));
    case JsonOperation.xml:
      return _xmlDocument(value);
    case JsonOperation.escape:
      final quoted = jsonEncode(jsonEncode(value));
      return quoted.substring(1, quoted.length - 1);
    case JsonOperation.sortKeys:
      return JsonEncoder.withIndent(indent).convert(_sortKeys(value));
    case JsonOperation.sortArrays:
      return JsonEncoder.withIndent(indent).convert(_sortArrays(value));
  }
}

Object? _sortKeys(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sortKeys(value[key])};
  }
  if (value is List) return value.map(_sortKeys).toList();
  return value;
}

Object? _sortArrays(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key: _sortArrays(entry.value),
    };
  }
  if (value is! List) return value;
  final items = value.map(_sortArrays).toList();
  if (items.length < 2) return items;
  final first = items.first;
  final sameType = items.every(
    (item) =>
        (first is num && item is num) ||
        (first is String && item is String) ||
        (first is bool && item is bool) ||
        (first == null && item == null),
  );
  if (!sameType || first is Map || first is List) {
    throw const FormatException(
      'Array sorting needs values of one primitive type (numbers, strings, booleans, or null).',
    );
  }
  if (first is num) {
    items.sort((a, b) => (a as num).compareTo(b as num));
  } else if (first is String) {
    items.sort((a, b) => (a as String).compareTo(b as String));
  } else if (first is bool) {
    items.sort(
      (a, b) => (a == b)
          ? 0
          : a == false
          ? -1
          : 1,
    );
  }
  return items;
}

String _xmlDocument(Object? value) {
  final buffer = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');
  _xmlElement(buffer, 'root', value, 0);
  return buffer.toString().trimRight();
}

void _xmlElement(StringBuffer buffer, String name, Object? value, int depth) {
  final pad = '  ' * depth;
  if (value == null) {
    buffer.writeln('$pad<$name/>');
    return;
  }
  if (value is Map || value is List) {
    buffer.writeln('$pad<$name>');
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key as String;
        final validName =
            RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(key) &&
            !key.toLowerCase().startsWith('xml');
        if (validName) {
          _xmlElement(buffer, key, entry.value, depth + 1);
        } else {
          // Keep the original key in data rather than generating invalid XML.
          buffer.writeln(
            '${'  ' * (depth + 1)}<entry key="${_xmlEscape(key)}">',
          );
          _xmlElement(buffer, 'value', entry.value, depth + 2);
          buffer.writeln('${'  ' * (depth + 1)}</entry>');
        }
      }
    } else {
      for (final item in value as List) {
        _xmlElement(buffer, 'item', item, depth + 1);
      }
    }
    buffer.writeln('$pad</$name>');
    return;
  }
  buffer.writeln('$pad<$name>${_xmlEscape(value.toString())}</$name>');
}

String _xmlEscape(String value) => value
    .replaceAllMapped(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]'),
      (_) => '\uFFFD',
    )
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
