/// Query-string editing that preserves order, duplicate keys and fragments.
library;

class QueryField {
  const QueryField(this.key, this.value);
  final String key;
  final String value;
}

class QueryEditorResult {
  const QueryEditorResult({this.output, this.fields = const [], this.error});
  final String? output;
  final List<QueryField> fields;
  final String? error;
}

enum QueryEdit { inspect, add, replace, remove, sort }

QueryEditorResult editQuery(
  String source, {
  QueryEdit edit = QueryEdit.inspect,
  String key = '',
  String value = '',
}) {
  if (source.trim().isEmpty) {
    return const QueryEditorResult(error: 'Enter a URL or query string.');
  }
  final raw = source.trim();
  final queryOnly =
      !raw.contains('://') &&
      !raw.startsWith('/') &&
      (raw.startsWith('?') || !raw.contains('?'));
  final hasQuery = raw.contains('?');
  final rawQuery = !queryOnly
      ? (hasQuery ? raw.split('?').skip(1).join('?').split('#').first : '')
      : raw.split('#').first;
  if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(rawQuery)) {
    return const QueryEditorResult(
      error: 'Invalid percent escape in query string.',
    );
  }
  final uriText = queryOnly ? (raw.startsWith('?') ? raw : '?$raw') : raw;
  final uri = Uri.tryParse(uriText);
  if (uri == null) {
    return const QueryEditorResult(error: 'Invalid URL or query string.');
  }
  final fields = <QueryField>[];
  try {
    for (final segment in uri.query.split('&')) {
      if (segment.isEmpty) continue;
      if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(segment)) {
        return const QueryEditorResult(
          error: 'Invalid percent escape in query string.',
        );
      }
      final index = segment.indexOf('=');
      fields.add(
        QueryField(
          Uri.decodeQueryComponent(
            index < 0 ? segment : segment.substring(0, index),
          ),
          index < 0
              ? ''
              : Uri.decodeQueryComponent(segment.substring(index + 1)),
        ),
      );
    }
  } on FormatException {
    return const QueryEditorResult(
      error: 'Invalid percent escape in query string.',
    );
  }
  if (edit == QueryEdit.add ||
      edit == QueryEdit.replace ||
      edit == QueryEdit.remove) {
    if (key.isEmpty) {
      return const QueryEditorResult(error: 'Enter a parameter name.');
    }
    if (edit != QueryEdit.add) fields.removeWhere((field) => field.key == key);
    if (edit != QueryEdit.remove) fields.add(QueryField(key, value));
  }
  if (edit == QueryEdit.sort) {
    fields.sort((a, b) {
      final order = a.key.compareTo(b.key);
      return order == 0 ? a.value.compareTo(b.value) : order;
    });
  }
  final query = fields
      .map(
        (field) =>
            '${Uri.encodeQueryComponent(field.key)}=${Uri.encodeQueryComponent(field.value)}',
      )
      .join('&');
  final base = queryOnly ? '' : raw.split('#').first.split('?').first;
  final fragment = uri.hasFragment
      ? '#${raw.split('#').skip(1).join('#')}'
      : '';
  final output = !queryOnly
      ? '$base${query.isNotEmpty || hasQuery ? '?$query' : ''}$fragment'
      : '${raw.startsWith('?') ? '?' : ''}$query$fragment';
  return QueryEditorResult(output: output, fields: fields);
}
