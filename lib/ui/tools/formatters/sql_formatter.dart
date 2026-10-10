/// SQL formatter tool view.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _SqlFormatterView extends StatefulWidget {
  const _SqlFormatterView();

  @override
  State<_SqlFormatterView> createState() => _SqlFormatterViewState();
}

class _SqlFormatterViewState extends State<_SqlFormatterView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _mode = 'Format';
  String _case = 'Uppercase';
  String _indent = '2 spaces';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    if (_mode == 'SQL to English') {
      final explanation = _SqlExplainer().explain(_input.text);
      _output.text = _formatSqlExplanation(explanation);
      setState(() {});
      return;
    }
    _output.text = _formatSql(_input.text, _case, indentFor(_indent));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: () {
        setState(() => _input.text = 'select * from users where id = 1');
        _run();
      },
      child: buildSplitEditors(
        inputActions: [
          ToolButton(label: 'Go', onPressed: _run),

          const SmallDropdown(
            items: ['General SQL'],
            initialValue: 'General SQL',
          ),
        ],
        outputActions: [
          SmallDropdown(
            items: const ['Format', 'SQL to English'],
            initialValue: _mode,
            onChanged: (value) {
              setState(() => _mode = value);
              _run();
            },
          ),
          if (_mode == 'Format')
            SmallDropdown(
              items: const ['Uppercase', 'Lowercase'],
              initialValue: _case,
              onChanged: (value) {
                setState(() => _case = value);
                _run();
              },
            ),
          if (_mode == 'Format')
            SmallDropdown(
              items: const ['2 spaces', '4 spaces', 'Tabs'],
              initialValue: _indent,
              onChanged: (value) {
                setState(() => _indent = value);
                _run();
              },
            ),
          ToolButton(
            label: 'Copy',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _output.text)),
          ),
        ],
        inputController: _input,
        outputController: _output,
      ),
    );
  }
}

String _formatSql(String source, String keywordCase, String indentString) {
  final compact = _compactSqlWhitespace(source);
  if (compact.isEmpty) return '';

  final cased = _caseSqlKeywords(compact, keywordCase);
  final clausePattern = RegExp(
    r'\s+((?:left|right|inner|outer|full|cross)\s+join|join|from|where|having|group\s+by|order\s+by|limit|offset|union(?:\s+all)?|values|set)\b',
    caseSensitive: false,
  );
  var text = cased.replaceAllMapped(clausePattern, (match) {
    return '\n${_caseSqlKeyword(match.group(1)!, keywordCase)}';
  });
  text = _breakSqlCommas(text, indentString);

  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';

  final formatted = <String>[];
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (lower.startsWith(',') ||
        lower.startsWith('and ') ||
        lower.startsWith('or ')) {
      formatted.add('$indentString$line');
    } else {
      formatted.add(line);
    }
  }
  return formatted.join('\n');
}

String _compactSqlWhitespace(String source) {
  final buffer = StringBuffer();
  String? quote;
  var previousWasSpace = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      buffer.write(char);
      if (char == quote && (i == 0 || source[i - 1] != '\\')) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
      previousWasSpace = false;
      continue;
    }
    if (RegExp(r'\s').hasMatch(char)) {
      if (!previousWasSpace && buffer.isNotEmpty) {
        buffer.write(' ');
        previousWasSpace = true;
      }
      continue;
    }
    buffer.write(char);
    previousWasSpace = false;
  }
  return buffer.toString().trim();
}

String _caseSqlKeywords(String source, String keywordCase) {
  const keywords = [
    'select',
    'distinct',
    'from',
    'where',
    'and',
    'or',
    'join',
    'left',
    'right',
    'inner',
    'outer',
    'full',
    'cross',
    'on',
    'group',
    'order',
    'by',
    'having',
    'limit',
    'offset',
    'union',
    'all',
    'insert',
    'into',
    'update',
    'delete',
    'values',
    'set',
    'as',
    'case',
    'when',
    'then',
    'else',
    'end',
    'is',
    'not',
    'null',
    'like',
    'in',
    'exists',
  ];
  var output = source;
  for (final keyword in keywords) {
    output = output.replaceAllMapped(
      RegExp('\\b${RegExp.escape(keyword)}\\b', caseSensitive: false),
      (match) => _caseSqlKeyword(match.group(0)!, keywordCase),
    );
  }
  return output;
}

String _caseSqlKeyword(String keyword, String keywordCase) {
  return keywordCase == 'Uppercase'
      ? keyword.toUpperCase()
      : keyword.toLowerCase();
}

String _breakSqlCommas(String source, String indentString) {
  final buffer = StringBuffer();
  String? quote;
  var depth = 0;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      buffer.write(char);
      if (char == quote && (i == 0 || source[i - 1] != '\\')) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
      continue;
    }
    if (char == '(') depth += 1;
    if (char == ')') depth = max(0, depth - 1);
    if (char == ',' && depth == 0) {
      buffer.write('\n$indentString, ');
      while (i + 1 < source.length && RegExp(r'\s').hasMatch(source[i + 1])) {
        i++;
      }
      continue;
    }
    buffer.write(char);
  }
  return buffer.toString();
}

String _formatSqlExplanation(_SqlExplanation explanation) {
  final buffer = StringBuffer();
  buffer.writeln('SUMMARY:');
  buffer.writeln(explanation.summary);
  buffer.writeln();
  buffer.writeln('BREAKDOWN:');
  for (final component in explanation.breakdown) {
    buffer.writeln('  [${component.clause}] ${component.explanation}');
  }
  if (explanation.tables.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Tables: ${explanation.tables.join(", ")}');
  }
  if (explanation.columns.isNotEmpty) {
    buffer.writeln('Columns: ${explanation.columns.join(", ")}');
  }
  if (explanation.conditions.isNotEmpty) {
    buffer.writeln('Conditions: ${explanation.conditions.join("; ")}');
  }
  return buffer.toString().trimRight();
}

class _SqlExplanation {
  _SqlExplanation({
    required this.summary,
    required this.breakdown,
    required this.tables,
    required this.columns,
    required this.conditions,
    required this.queryType,
  });

  final String summary;
  final List<_SqlComponent> breakdown;
  final List<String> tables;
  final List<String> columns;
  final List<String> conditions;
  final _SqlQueryType queryType;
}

class _SqlComponent {
  _SqlComponent({required this.clause, required this.explanation});

  final String clause;
  final String explanation;
}

enum _SqlQueryType {
  select,
  insert,
  update,
  delete,
  create,
  alter,
  drop,
  unknown,
}

class _SqlExplainer {
  _SqlExplanation explain(String sql) {
    final normalized = _normalizeSql(sql);
    final type = _detectQueryType(normalized);
    switch (type) {
      case _SqlQueryType.select:
        return _explainSelect(normalized);
      case _SqlQueryType.insert:
        return _explainInsert(normalized);
      case _SqlQueryType.update:
        return _explainUpdate(normalized);
      case _SqlQueryType.delete:
        return _explainDelete(normalized);
      case _SqlQueryType.create:
        return _explainCreate(normalized);
      case _SqlQueryType.drop:
        return _explainDrop(normalized);
      case _SqlQueryType.alter:
        return _explainGeneric(normalized, type);
      case _SqlQueryType.unknown:
        return _explainGeneric(normalized, type);
    }
  }

  _SqlExplanation _explainSelect(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];
    final conditions = <String>[];
    final summaryParts = <String>[];

    final selectMatch = _firstMatch(
      sql,
      r'SELECT\s+(DISTINCT\s+)?(.+?)\s+FROM',
    );
    if (selectMatch != null) {
      final selectClause = selectMatch.group(0)!;
      final isDistinct = selectClause.toUpperCase().contains('DISTINCT');
      final colString = selectMatch.group(2)!.trim();
      if (colString == '*') {
        columns.add('all columns');
        components.add(
          _SqlComponent(
            clause: 'SELECT *',
            explanation: 'Retrieves all columns',
          ),
        );
      } else {
        columns.addAll(
          colString
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty),
        );
        final colDesc = columns.length > 3
            ? '${columns.length} columns'
            : columns.join(', ');
        components.add(
          _SqlComponent(clause: 'SELECT', explanation: 'Retrieves $colDesc'),
        );
      }
      if (isDistinct) {
        components.add(
          _SqlComponent(
            clause: 'DISTINCT',
            explanation: 'Removes duplicate rows from results',
          ),
        );
      }
    }

    final fromMatch = _firstMatch(
      sql,
      r'FROM\s+([\w\s,\.`"]+?)(?:\s+(?:WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|GROUP|ORDER|LIMIT|HAVING|UNION|$))',
    );
    if (fromMatch != null) {
      final tablesPart = fromMatch
          .group(1)!
          .replaceAll(
            RegExp(
              r'\s+(WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|GROUP|ORDER|LIMIT|HAVING|UNION).*',
            ),
            '',
          )
          .trim();
      final parsedTables = tablesPart
          .split(',')
          .map((item) => item.trim())
          .map((item) => item.split(' ').first)
          .where((item) => item.isNotEmpty)
          .toList();
      tables.addAll(parsedTables);
      if (parsedTables.isNotEmpty) {
        final tableDesc = parsedTables.length == 1
            ? "the '${parsedTables[0]}' table"
            : 'tables: ${parsedTables.join(', ')}';
        components.add(
          _SqlComponent(clause: 'FROM', explanation: 'From $tableDesc'),
        );
        summaryParts.add('from $tableDesc');
      }
    }

    const joinPattern =
        r'(LEFT\s+OUTER\s+|RIGHT\s+OUTER\s+|LEFT\s+|RIGHT\s+|INNER\s+|OUTER\s+|CROSS\s+)?JOIN\s+([\w\.`"]+)(?:\s+(?:AS\s+)?(\w+))?(?:\s+ON\s+(.+?))?(?=\s+(?:LEFT|RIGHT|INNER|OUTER|CROSS|JOIN|WHERE|GROUP|ORDER|LIMIT|HAVING|$))';
    for (final match in _allMatches(sql, joinPattern)) {
      final joinType = (match.group(1) ?? '').trim().toUpperCase();
      final joinTable = match.group(2) ?? '';
      final joinCondition = match.group(4) ?? '';
      if (joinTable.isEmpty) {
        continue;
      }
      tables.add(joinTable);
      final joinDesc = _describeJoin(joinType, joinTable, joinCondition);
      components.add(
        _SqlComponent(clause: '${joinType}JOIN', explanation: joinDesc),
      );
      summaryParts.add(joinDesc.toLowerCase());
    }

    final whereMatch = _firstMatch(
      sql,
      r'WHERE\s+(.+?)(?:\s+(?:GROUP|ORDER|LIMIT|HAVING|UNION|$))',
    );
    if (whereMatch != null) {
      final whereClause = whereMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(GROUP|ORDER|LIMIT|HAVING|UNION).*'), '')
          .trim();
      final explained = _explainConditions(whereClause);
      conditions.addAll(explained.map((item) => item.raw));
      components.add(
        _SqlComponent(
          clause: 'WHERE',
          explanation:
              'Filters results where: ${explained.map((item) => item.explanation).join('; ')}',
        ),
      );
      summaryParts.add(
        'filtered by ${conditions.length} condition${conditions.length == 1 ? '' : 's'}',
      );
    }

    final groupMatch = _firstMatch(
      sql,
      r'GROUP\s+BY\s+(.+?)(?:\s+(?:HAVING|ORDER|LIMIT|UNION|$))',
    );
    if (groupMatch != null) {
      final groupClause = groupMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(HAVING|ORDER|LIMIT|UNION).*'), '')
          .trim();
      final groupCols = groupClause
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (groupCols.isNotEmpty) {
        components.add(
          _SqlComponent(
            clause: 'GROUP BY',
            explanation: 'Groups results by ${groupCols.join(', ')}',
          ),
        );
        summaryParts.add('grouped by ${groupCols.join(', ')}');
      }
    }

    final havingMatch = _firstMatch(
      sql,
      r'HAVING\s+(.+?)(?:\s+(?:ORDER|LIMIT|UNION|$))',
    );
    if (havingMatch != null) {
      final havingClause = havingMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(ORDER|LIMIT|UNION).*'), '')
          .trim();
      if (havingClause.isNotEmpty) {
        components.add(
          _SqlComponent(
            clause: 'HAVING',
            explanation: 'Filters groups where: $havingClause',
          ),
        );
      }
    }

    final orderMatch = _firstMatch(
      sql,
      r'ORDER\s+BY\s+(.+?)(?:\s+(?:LIMIT|OFFSET|UNION|$))',
    );
    if (orderMatch != null) {
      final orderClause = orderMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+(LIMIT|OFFSET|UNION).*'), '')
          .trim();
      if (orderClause.isNotEmpty) {
        final orderExplanation = _explainOrderBy(orderClause);
        components.add(
          _SqlComponent(clause: 'ORDER BY', explanation: orderExplanation),
        );
        summaryParts.add('sorted by $orderClause');
      }
    }

    final limitMatch = _firstMatch(sql, r'LIMIT\s+(\d+)(?:\s+OFFSET\s+(\d+))?');
    if (limitMatch != null) {
      final limitValue = int.tryParse(limitMatch.group(1) ?? '');
      final offsetValue = int.tryParse(limitMatch.group(2) ?? '');
      if (limitValue != null) {
        var limitExplanation =
            'Returns only the first $limitValue result${limitValue == 1 ? '' : 's'}';
        if (offsetValue != null) {
          limitExplanation += ', skipping the first $offsetValue';
        }
        components.add(
          _SqlComponent(clause: 'LIMIT', explanation: limitExplanation),
        );
        summaryParts.add('limited to $limitValue rows');
      }
    }

    final columnSummary = columns.firstOrNull == 'all columns'
        ? 'all columns'
        : '${columns.length} column${columns.length == 1 ? '' : 's'}';
    var summary = 'Retrieves $columnSummary';
    if (summaryParts.isNotEmpty) {
      summary = '$summary ${summaryParts.join(', ')}';
    }

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: conditions,
      queryType: _SqlQueryType.select,
    );
  }

  _SqlExplanation _explainInsert(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'INSERT\s+INTO\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tablePart = tableMatch.group(1)!;
      tables.add(tablePart);
      components.add(
        _SqlComponent(
          clause: 'INSERT INTO',
          explanation: "Adds new row(s) to the '$tablePart' table",
        ),
      );
    }

    final colMatch = _firstMatch(
      sql,
      r'\(([^)]+)\)\s*VALUES',
      caseInsensitive: true,
    );
    if (colMatch != null) {
      final colPart = colMatch.group(1)!;
      columns.addAll(
        colPart
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
      components.add(
        _SqlComponent(
          clause: 'COLUMNS',
          explanation: 'Sets values for: ${columns.join(', ')}',
        ),
      );
    }

    final valuesCount = RegExp(r'\)\s*,\s*\(').allMatches(sql).length + 1;
    components.add(
      _SqlComponent(
        clause: 'VALUES',
        explanation: 'Inserting $valuesCount row${valuesCount == 1 ? '' : 's'}',
      ),
    );

    if (sql.toUpperCase().contains('SELECT')) {
      components.add(
        _SqlComponent(
          clause: 'SELECT',
          explanation: 'Values come from a subquery',
        ),
      );
    }

    final summary =
        "Inserts $valuesCount row${valuesCount == 1 ? '' : 's'} into '${tables.firstOrNull ?? 'table'}' with ${columns.length} column${columns.length == 1 ? '' : 's'}";

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: const [],
      queryType: _SqlQueryType.insert,
    );
  }

  _SqlExplanation _explainUpdate(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];
    final conditions = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'UPDATE\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tablePart = tableMatch.group(1)!;
      tables.add(tablePart);
      components.add(
        _SqlComponent(
          clause: 'UPDATE',
          explanation: "Modifies rows in the '$tablePart' table",
        ),
      );
    }

    final setMatch = _firstMatch(
      sql,
      r'SET\s+(.+?)(?:\s+WHERE|$)',
      caseInsensitive: true,
    );
    if (setMatch != null) {
      final setPart = setMatch
          .group(1)!
          .replaceAll(RegExp(r'\s+WHERE.*', caseSensitive: false), '')
          .trim();
      final assignments = setPart
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      columns.addAll(
        assignments
            .map((assignment) => assignment.split('=').first.trim())
            .where((value) => value.isNotEmpty),
      );

      final setExplanations = <String>[];
      for (final assignment in assignments) {
        final parts = assignment.split('=').map((part) => part.trim()).toList();
        if (parts.length == 2) {
          setExplanations.add("'${parts[0]}' to ${parts[1]}");
        }
      }
      components.add(
        _SqlComponent(
          clause: 'SET',
          explanation: 'Changes: ${setExplanations.join(', ')}',
        ),
      );
    }

    final whereMatch = _firstMatch(
      sql,
      r'WHERE\s+(.+?)$',
      caseInsensitive: true,
    );
    if (whereMatch != null) {
      final whereClause = whereMatch.group(1)!.trim();
      final explained = _explainConditions(whereClause);
      conditions.addAll(explained.map((item) => item.raw));
      components.add(
        _SqlComponent(
          clause: 'WHERE',
          explanation:
              'Only affects rows where: ${explained.map((item) => item.explanation).join('; ')}',
        ),
      );
    } else {
      components.add(
        _SqlComponent(
          clause: 'WARNING',
          explanation: 'No WHERE clause - this will update ALL rows.',
        ),
      );
    }

    final summary =
        "Updates ${columns.length} column${columns.length == 1 ? '' : 's'} in '${tables.firstOrNull ?? 'table'}'"
        '${conditions.isEmpty ? ' (ALL ROWS)' : ' with ${conditions.length} filter condition${conditions.length == 1 ? '' : 's'}'}';

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: conditions,
      queryType: _SqlQueryType.update,
    );
  }

  _SqlExplanation _explainDelete(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final conditions = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'DELETE\s+FROM\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tablePart = tableMatch.group(1)!;
      tables.add(tablePart);
      components.add(
        _SqlComponent(
          clause: 'DELETE FROM',
          explanation: "Removes rows from the '$tablePart' table",
        ),
      );
    }

    final whereMatch = _firstMatch(
      sql,
      r'WHERE\s+(.+?)$',
      caseInsensitive: true,
    );
    if (whereMatch != null) {
      final whereClause = whereMatch.group(1)!.trim();
      final explained = _explainConditions(whereClause);
      conditions.addAll(explained.map((item) => item.raw));
      components.add(
        _SqlComponent(
          clause: 'WHERE',
          explanation:
              'Only deletes rows where: ${explained.map((item) => item.explanation).join('; ')}',
        ),
      );
    } else {
      components.add(
        _SqlComponent(
          clause: 'WARNING',
          explanation: 'No WHERE clause - this will delete ALL rows.',
        ),
      );
    }

    final summary =
        "Deletes rows from '${tables.firstOrNull ?? 'table'}'"
        '${conditions.isEmpty ? ' (ALL ROWS)' : ' where ${conditions.length} condition${conditions.length == 1 ? '' : 's'} match'}';

    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: const [],
      conditions: conditions,
      queryType: _SqlQueryType.delete,
    );
  }

  _SqlExplanation _explainCreate(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];
    final columns = <String>[];

    final tableMatch = _firstMatch(
      sql,
      r'CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (tableMatch != null) {
      final tableName = tableMatch.group(2)!;
      tables.add(tableName);
      final ifNotExists = tableMatch.group(1) != null;
      var explanation = "Creates a new table called '$tableName'";
      if (ifNotExists) {
        explanation += ' (only if it does not already exist)';
      }
      components.add(
        _SqlComponent(clause: 'CREATE TABLE', explanation: explanation),
      );

      final colSection = _firstMatch(sql, r'\((.+)\)', caseInsensitive: true);
      if (colSection != null) {
        final colPart = colSection.group(1) ?? '';
        final colDefs = _splitColumnDefinitions(colPart);
        for (final def in colDefs) {
          final explained = _explainColumnDefinition(def);
          columns.add(explained.name);
          components.add(
            _SqlComponent(clause: 'COLUMN', explanation: explained.explanation),
          );
        }
      }
    }

    final indexMatch = _firstMatch(
      sql,
      r'CREATE\s+(UNIQUE\s+)?INDEX\s+([\w\.`"]+)\s+ON\s+([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (indexMatch != null) {
      final isUnique = indexMatch.group(1) != null;
      components.add(
        _SqlComponent(
          clause: 'CREATE INDEX',
          explanation:
              'Creates a${isUnique ? ' unique' : 'n'} index for faster lookups',
        ),
      );
    }

    final summary =
        "Creates table '${tables.firstOrNull ?? ''}' with ${columns.length} column${columns.length == 1 ? '' : 's'}";
    return _SqlExplanation(
      summary: summary,
      breakdown: components,
      tables: tables,
      columns: columns,
      conditions: const [],
      queryType: _SqlQueryType.create,
    );
  }

  _SqlExplanation _explainDrop(String sql) {
    final components = <_SqlComponent>[];
    final tables = <String>[];

    final dropMatch = _firstMatch(
      sql,
      r'DROP\s+(TABLE|INDEX|DATABASE)\s+(IF\s+EXISTS\s+)?([\w\.`"]+)',
      caseInsensitive: true,
    );
    if (dropMatch != null) {
      final objectType = dropMatch.group(1)!.toUpperCase();
      final objectName = dropMatch.group(3)!;
      final ifExists = dropMatch.group(2) != null;
      tables.add(objectName);
      var explanation =
          'Permanently deletes the ${objectType.toLowerCase()} \'$objectName\'';
      if (ifExists) {
        explanation += ' (only if it exists)';
      }
      components.add(_SqlComponent(clause: 'DROP', explanation: explanation));
    }

    return _SqlExplanation(
      summary:
          "Drops (deletes) '${tables.firstOrNull ?? 'object'}' permanently",
      breakdown: components,
      tables: tables,
      columns: const [],
      conditions: const [],
      queryType: _SqlQueryType.drop,
    );
  }

  _SqlExplanation _explainGeneric(String sql, _SqlQueryType type) {
    return _SqlExplanation(
      summary: 'Executes a ${type.name.toUpperCase()} statement',
      breakdown: [
        _SqlComponent(
          clause: type.name.toUpperCase(),
          explanation: 'Unable to parse detailed structure',
        ),
      ],
      tables: const [],
      columns: const [],
      conditions: const [],
      queryType: type,
    );
  }

  String _normalizeSql(String sql) {
    var result = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    result = result.replaceAll(RegExp(r'--.*?(?=\n|$)'), '');
    result = result.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    return result;
  }

  _SqlQueryType _detectQueryType(String sql) {
    final upper = sql.trim().toUpperCase();
    if (upper.startsWith('SELECT')) return _SqlQueryType.select;
    if (upper.startsWith('INSERT')) return _SqlQueryType.insert;
    if (upper.startsWith('UPDATE')) return _SqlQueryType.update;
    if (upper.startsWith('DELETE')) return _SqlQueryType.delete;
    if (upper.startsWith('CREATE')) return _SqlQueryType.create;
    if (upper.startsWith('ALTER')) return _SqlQueryType.alter;
    if (upper.startsWith('DROP')) return _SqlQueryType.drop;
    return _SqlQueryType.unknown;
  }

  String _describeJoin(String type, String table, String condition) {
    String desc;
    switch (type.trim()) {
      case 'LEFT':
      case 'LEFT OUTER':
        desc =
            "Includes all rows from the left table, plus matching rows from '$table'";
        break;
      case 'RIGHT':
      case 'RIGHT OUTER':
        desc =
            "Includes all rows from '$table', plus matching rows from the left table";
        break;
      case 'OUTER':
      case 'FULL OUTER':
        desc = 'Includes all rows from both tables, matching where possible';
        break;
      case 'CROSS':
        desc =
            "Combines every row with every row from '$table' (cartesian product)";
        break;
      default:
        desc = "Combines with '$table' where matches exist";
    }
    if (condition.isNotEmpty) {
      desc += ' on $condition';
    }
    return desc;
  }

  List<_SqlCondition> _explainConditions(String whereClause) {
    final parts = whereClause
        .replaceAll(RegExp(r'\s+AND\s+', caseSensitive: false), '§AND§')
        .replaceAll(RegExp(r'\s+OR\s+', caseSensitive: false), '§OR§')
        .split('§')
        .where((item) => item.isNotEmpty)
        .toList();
    final explained = <_SqlCondition>[];
    for (final part in parts) {
      if (part == 'AND' || part == 'OR') {
        continue;
      }
      explained.add(
        _SqlCondition(
          raw: part.trim(),
          explanation: _explainSingleCondition(part),
        ),
      );
    }
    return explained;
  }

  String _explainSingleCondition(String condition) {
    final cond = condition.trim();
    final upper = cond.toUpperCase();
    if (upper.contains(' IS NULL')) {
      final col = cond.replaceAll(
        RegExp(r'\s+IS\s+NULL', caseSensitive: false),
        '',
      );
      return "'$col' has no value";
    }
    if (upper.contains(' IS NOT NULL')) {
      final col = cond.replaceAll(
        RegExp(r'\s+IS\s+NOT\s+NULL', caseSensitive: false),
        '',
      );
      return "'$col' has a value";
    }
    if (upper.contains(' IN ')) {
      final match = _firstMatch(
        cond,
        r'(.+?)\s+IN\s*\((.+?)\)',
        caseInsensitive: true,
      );
      if (match != null) {
        final parts = match
            .group(0)!
            .split(RegExp(r'\s+IN\s+', caseSensitive: false));
        if (parts.length == 2) {
          return "'${parts[0]}' is one of ${parts[1]}";
        }
      }
    }
    if (upper.contains(' LIKE ')) {
      final parts = cond
          .split(RegExp(r'\s+LIKE\s+', caseSensitive: false))
          .map((item) => item.trim())
          .toList();
      if (parts.length == 2) {
        final pattern = parts[1].replaceAll("'", '');
        if (pattern.startsWith('%') && pattern.endsWith('%')) {
          final text = pattern.replaceAll('%', '');
          return "'${parts[0]}' contains '$text'";
        }
        if (pattern.startsWith('%')) {
          final text = pattern.replaceAll('%', '');
          return "'${parts[0]}' ends with '$text'";
        }
        if (pattern.endsWith('%')) {
          final text = pattern.replaceAll('%', '');
          return "'${parts[0]}' starts with '$text'";
        }
        return "'${parts[0]}' matches pattern '$pattern'";
      }
    }
    if (upper.contains(' BETWEEN ')) {
      final match = _firstMatch(
        cond,
        r'(.+?)\s+BETWEEN\s+(.+?)\s+AND\s+(.+)',
        caseInsensitive: true,
      );
      if (match != null) {
        final col = match.group(1)!.trim();
        final low = match.group(2)!.trim();
        final high = match.group(3)!.trim();
        return "'$col' is between $low and $high";
      }
    }
    const operators = [
      ['>=', 'is greater than or equal to'],
      ['<=', 'is less than or equal to'],
      ['<>', 'is not equal to'],
      ['!=', 'is not equal to'],
      ['=', 'equals'],
      ['>', 'is greater than'],
      ['<', 'is less than'],
    ];
    for (final entry in operators) {
      final op = entry[0];
      final desc = entry[1];
      if (cond.contains(op)) {
        final parts = cond.split(op).map((item) => item.trim()).toList();
        if (parts.length == 2) {
          return "'${parts[0]}' $desc ${parts[1]}";
        }
      }
    }
    return cond;
  }

  String _explainOrderBy(String clause) {
    final parts = clause
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final explanations = <String>[];
    for (final part in parts) {
      final upper = part.toUpperCase();
      final col = part
          .replaceAll(RegExp(r'\s+(ASC|DESC)$', caseSensitive: false), '')
          .trim();
      if (upper.endsWith('DESC')) {
        explanations.add("'$col' descending (Z->A, 9->0)");
      } else {
        explanations.add("'$col' ascending (A->Z, 0->9)");
      }
    }
    return 'Sorts by ${explanations.join(', then by ')}';
  }

  List<String> _splitColumnDefinitions(String section) {
    final definitions = <String>[];
    var current = StringBuffer();
    var parenDepth = 0;
    for (final char in section.split('')) {
      if (char == '(') {
        parenDepth += 1;
      } else if (char == ')') {
        parenDepth = parenDepth > 0 ? parenDepth - 1 : 0;
      }
      if (char == ',' && parenDepth == 0) {
        final value = current.toString().trim();
        if (value.isNotEmpty) {
          definitions.add(value);
        }
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    final tail = current.toString().trim();
    if (tail.isNotEmpty) {
      definitions.add(tail);
    }
    return definitions;
  }

  _SqlColumnExplanation _explainColumnDefinition(String definition) {
    final parts = definition
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return _SqlColumnExplanation(name: '', explanation: definition);
    }
    final upperDef = definition.toUpperCase();
    if (upperDef.startsWith('PRIMARY KEY') ||
        upperDef.startsWith('FOREIGN KEY') ||
        upperDef.startsWith('UNIQUE') ||
        upperDef.startsWith('CHECK') ||
        upperDef.startsWith('CONSTRAINT')) {
      return _SqlColumnExplanation(
        name: 'constraint',
        explanation: _explainConstraint(definition),
      );
    }
    final name = parts[0];
    final type = parts.length > 1 ? parts[1] : 'unknown';
    final attributes = <String>[];
    if (upperDef.contains('PRIMARY KEY')) attributes.add('primary key');
    if (upperDef.contains('NOT NULL')) attributes.add('required');
    if (upperDef.contains('UNIQUE')) attributes.add('unique');
    if (upperDef.contains('AUTO_INCREMENT') ||
        upperDef.contains('AUTOINCREMENT')) {
      attributes.add('auto-generated');
    }
    if (upperDef.contains('DEFAULT')) attributes.add('has default value');
    if (upperDef.contains('REFERENCES')) attributes.add('foreign key');
    var explanation = "'$name' (${_describeDataType(type)}";
    if (attributes.isNotEmpty) {
      explanation += ', ${attributes.join(', ')}';
    }
    explanation += ')';
    return _SqlColumnExplanation(name: name, explanation: explanation);
  }

  String _describeDataType(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('INT')) return 'whole number';
    if (upper.contains('VARCHAR') || upper.contains('CHAR')) return 'text';
    if (upper.contains('TEXT')) return 'long text';
    if (upper.contains('DECIMAL') ||
        upper.contains('NUMERIC') ||
        upper.contains('FLOAT') ||
        upper.contains('DOUBLE')) {
      return 'decimal number';
    }
    if (upper.contains('BOOL')) return 'true/false';
    if (upper.contains('DATE') && upper.contains('TIME')) {
      return 'date and time';
    }
    if (upper.contains('DATE')) return 'date';
    if (upper.contains('TIME')) return 'time';
    if (upper.contains('BLOB') || upper.contains('BINARY')) {
      return 'binary data';
    }
    if (upper.contains('JSON')) return 'JSON data';
    if (upper.contains('UUID')) return 'unique identifier';
    return type.toLowerCase();
  }

  String _explainConstraint(String definition) {
    final upper = definition.toUpperCase();
    if (upper.contains('PRIMARY KEY')) {
      return 'Primary key constraint - uniquely identifies each row';
    }
    if (upper.contains('FOREIGN KEY')) {
      final refMatch = _firstMatch(
        definition,
        r'REFERENCES\s+([\w\.]+)',
        caseInsensitive: true,
      );
      if (refMatch != null) {
        final refTable = refMatch.group(1) ?? '';
        return "Foreign key - links to '$refTable'";
      }
      return 'Foreign key constraint - links to another table';
    }
    if (upper.contains('UNIQUE')) {
      return 'Unique constraint - no duplicate values allowed';
    }
    if (upper.contains('CHECK')) {
      return 'Check constraint - validates data before insert/update';
    }
    return definition;
  }

  RegExpMatch? _firstMatch(
    String input,
    String pattern, {
    bool caseInsensitive = true,
  }) {
    return RegExp(
      pattern,
      caseSensitive: !caseInsensitive,
      dotAll: true,
    ).firstMatch(input);
  }

  Iterable<RegExpMatch> _allMatches(String input, String pattern) {
    return RegExp(
      pattern,
      caseSensitive: false,
      dotAll: true,
    ).allMatches(input);
  }
}

class _SqlCondition {
  _SqlCondition({required this.raw, required this.explanation});

  final String raw;
  final String explanation;
}

class _SqlColumnExplanation {
  _SqlColumnExplanation({required this.name, required this.explanation});

  final String name;
  final String explanation;
}

Widget buildSqlFormatter() {
  return const _SqlFormatterView();
}
