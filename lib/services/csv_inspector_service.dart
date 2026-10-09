/// Quoted CSV parsing and read-only filtering/sorting for pasted tables.
library;

class CsvInspectResult {
  const CsvInspectResult({
    this.output = '',
    this.columns = const [],
    this.rowCount = 0,
    this.matchedCount = 0,
    this.error,
  });

  final String output;
  final List<String> columns;
  final int rowCount;
  final int matchedCount;
  final String? error;
}

CsvInspectResult inspectCsv(
  String input, {
  String filterColumn = '',
  String filterText = '',
  String sortColumn = '',
  bool descending = false,
}) {
  if (input.trim().isEmpty) return const CsvInspectResult();
  final List<List<String>> rows;
  try {
    rows = _parseCsv(input);
  } on FormatException catch (error) {
    return CsvInspectResult(error: error.message);
  }
  if (rows.isEmpty) return const CsvInspectResult();
  final columns = rows.first;
  if (columns.isEmpty || columns.every((column) => column.isEmpty)) {
    return const CsvInspectResult(error: 'Add a header row with column names.');
  }
  if (columns.toSet().length != columns.length) {
    return CsvInspectResult(
      columns: columns,
      error: 'Column names must be unique.',
    );
  }
  for (var i = 1; i < rows.length; i++) {
    if (rows[i].length != columns.length) {
      return CsvInspectResult(
        columns: columns,
        error:
            'Row ${i + 1} has ${rows[i].length} cells; expected ${columns.length}.',
      );
    }
  }
  if (filterText.isNotEmpty &&
      filterColumn.isNotEmpty &&
      !columns.contains(filterColumn)) {
    return CsvInspectResult(
      columns: columns,
      error: 'Unknown filter column: $filterColumn',
    );
  }
  if (sortColumn.isNotEmpty && !columns.contains(sortColumn)) {
    return CsvInspectResult(
      columns: columns,
      error: 'Unknown sort column: $sortColumn',
    );
  }
  final data = rows
      .skip(1)
      .where(
        (row) =>
            filterText.isEmpty ||
            (filterColumn.isEmpty
                ? row.any(
                    (cell) =>
                        cell.toLowerCase().contains(filterText.toLowerCase()),
                  )
                : row[columns.indexOf(filterColumn)].toLowerCase().contains(
                    filterText.toLowerCase(),
                  )),
      )
      .toList();
  if (sortColumn.isNotEmpty) {
    final column = columns.indexOf(sortColumn);
    data.sort((a, b) {
      final left = a[column], right = b[column];
      final numbers = (double.tryParse(left), double.tryParse(right));
      final order = numbers.$1 != null && numbers.$2 != null
          ? numbers.$1!.compareTo(numbers.$2!)
          : left.toLowerCase().compareTo(right.toLowerCase());
      return descending ? -order : order;
    });
  }
  return CsvInspectResult(
    columns: columns,
    rowCount: rows.length - 1,
    matchedCount: data.length,
    output: ([
      columns,
      ...data,
    ].map((row) => row.map(_escapeCell).join(','))).join('\n'),
  );
}

List<List<String>> _parseCsv(String source) {
  final rows = <List<String>>[];
  final row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var finishedQuote = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          finishedQuote = true;
        }
      } else {
        cell.write(char);
      }
    } else if (char == ',' || char == '\n' || char == '\r') {
      row.add(cell.toString());
      cell.clear();
      finishedQuote = false;
      if (char != ',') {
        rows.add(List.of(row));
        row.clear();
        if (char == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
      }
    } else if (char == '"' && cell.isEmpty && !finishedQuote) {
      quoted = true;
    } else if (finishedQuote || char == '"') {
      throw FormatException(
        'Unexpected character in CSV row ${rows.length + 1}.',
      );
    } else {
      cell.write(char);
    }
  }
  if (quoted) throw const FormatException('Unclosed quoted CSV field.');
  if (cell.isNotEmpty || row.isNotEmpty || finishedQuote) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

String _escapeCell(String value) {
  if (!value.contains(RegExp('[,\n\r"]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}
