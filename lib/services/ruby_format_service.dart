import 'dart:math';

/// Conservative Ruby layout: keep newline separators and literal bodies intact.
class RubyFormatService {
  static String process(
    String source, {
    String? indent,
    bool keepComments = true,
  }) {
    if (source.trim().isEmpty) return '';
    final lexer = _RubyLayoutLexer();
    final output = <String>[];
    var level = 0;
    var data = false;
    var blockComment = false;
    final heredocs = <(String, bool)>[];
    for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
      var line = raw.trim();
      if (data) {
        output.add(raw);
        continue;
      }
      if (line == '__END__') {
        data = true;
        output.add(raw);
        continue;
      }
      if (heredocs.isNotEmpty) {
        output.add(raw);
        final (delimiter, allowIndent) = heredocs.first;
        if ((allowIndent ? raw.trim() : raw) == delimiter) heredocs.removeAt(0);
        continue;
      }
      if (raw.startsWith('=begin')) blockComment = true;
      if (blockComment) {
        if (keepComments) output.add(raw);
        if (raw.startsWith('=end')) blockComment = false;
        continue;
      }
      final protectedLine = lexer.inLiteral;
      final code = lexer.mask(raw);
      final comment = lexer.commentStart;
      final magicComment = RegExp(
        r'^#(?:!|.*(?:coding\s*[:=]|encoding\s*[:=]|frozen_string_literal\s*:|warn_indent\s*:))',
      ).hasMatch(raw);
      if (!keepComments && comment != null && !magicComment) {
        line = raw.substring(0, comment).trim();
      }
      if (protectedLine) {
        output.add(
          !keepComments && comment != null
              ? raw.substring(0, comment).trimRight()
              : raw,
        );
        continue;
      }
      // Heredoc detection uses code outside strings and comments. Quoted
      // delimiter text is taken from the original source at the same offset.
      for (final match in RegExp(r'<<[-~]?').allMatches(code)) {
        final tail = raw.substring(match.end);
        final delimiter = RegExp(
          r'''^\s*(['"`]?)([A-Za-z_]\w*)\1''',
        ).firstMatch(tail);
        if (delimiter != null) {
          heredocs.add((delimiter.group(2)!, match.group(0) != '<<'));
        }
      }
      if (indent == null) {
        if (line.isEmpty) continue;
        output.add(line);
        continue;
      }
      final trimmedCode = code.trim();
      final closes = RegExp(r'^(end\b|[}\])])').hasMatch(trimmedCode);
      final branch = RegExp(
        r'^(else|elsif|when|in|rescue|ensure)\b',
      ).hasMatch(trimmedCode);
      if (closes || branch) level = max(0, level - 1);
      output.add(line.isEmpty ? '' : '${indent * level}$line');
      if (branch) {
        level++;
      } else if (!closes) {
        final opens =
            RegExp(
              r'^(def|class|module|begin|if|unless|while|until|for|case)\b',
            ).hasMatch(trimmedCode) ||
            RegExp(r'\bdo\b(?:\s*\|[^|]*\|)?\s*$').hasMatch(trimmedCode) ||
            RegExp(r'[{\[(]\s*(?:\|[^|]*\|)?\s*$').hasMatch(trimmedCode);
        final inlineEnd = RegExp(r'\bend\b').hasMatch(trimmedCode);
        final endlessDef = RegExp(r'^def\s+[^=]+\s=\s').hasMatch(trimmedCode);
        if (opens && !inlineEnd && !endlessDef) level++;
      }
    }
    // Do not trim the result: a final blank line can belong to a literal/data.
    return output.join('\n');
  }
}

class _RubyLayoutLexer {
  String? _close;
  String? _open;
  var _depth = 0;
  int? commentStart;
  bool get inLiteral => _close != null;

  String mask(String line) {
    commentStart = null;
    final out = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (_close != null) {
        out.write(' ');
        if (char == '\\' && i + 1 < line.length) {
          out.write(' ');
          i++;
          continue;
        }
        if (_open != null && char == _open) _depth++;
        if (char == _close) {
          if (_depth > 0) {
            _depth--;
          } else {
            _close = null;
            _open = null;
          }
        }
        continue;
      }
      if (char == '#') {
        commentStart = i;
        out.write(' ' * (line.length - i));
        break;
      }
      if (char == '"' || char == "'" || char == '`') {
        _close = char;
        out.write(' ');
      } else if (char == '%' && i + 1 < line.length) {
        final match = RegExp(
          r'^%(?:[qQwWiIxrs])?([^\w\s])',
        ).firstMatch(line.substring(i));
        if (match == null) {
          out.write(char);
          continue;
        }
        final delimiter = match.group(1)!;
        _close =
            {'(': ')', '[': ']', '{': '}', '<': '>'}[delimiter] ?? delimiter;
        _open = _close == delimiter ? null : delimiter;
        out.write(' ' * match.end);
        i += match.end - 1;
      } else if (char == '/' &&
          (out.toString().trim().isEmpty ||
              RegExp(
                r'(=|\(|,|\breturn|\bwhen|\bif|\bunless)\s*$',
              ).hasMatch(out.toString()))) {
        _close = '/';
        out.write(' ');
      } else {
        out.write(char);
      }
    }
    return out.toString();
  }
}
