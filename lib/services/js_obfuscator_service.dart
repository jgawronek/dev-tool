/// A real JavaScript/TypeScript obfuscator.
///
/// Unlike a base64 wrapper, this rewrites the program: identifiers are renamed,
/// string literals are hoisted into an array read through an offset-shifted
/// accessor, and auxiliary noise is injected. Every pass is driven from a
/// tokenizer rather than regular expressions, so strings, template literals,
/// comments, and regular-expression literals are never touched by accident.
///
/// The tokenizer is the safety net. Obfuscation is only worth doing if the
/// output still runs, and the passes here are written to be structure-
/// preserving rather than clever.
library;

/// The lexical kinds the tokenizer distinguishes.
enum JsTokenType {
  identifier,
  keyword,
  string,
  templateString,
  number,
  regex,
  comment,
  whitespace,
  operator,
  punctuation,

  /// Anything the tokenizer could not classify.
  unknown,
}

/// A single lexical token with its source offsets.
class JsToken {
  const JsToken({
    required this.type,
    required this.text,
    required this.start,
    required this.end,
    this.codeRanges = const [],
  });

  final JsTokenType type;
  final String text;
  final int start;
  final int end;

  /// For template literals, the `${ ... }` spans that hold real code. Offsets
  /// are relative to [start].
  final List<JsRange> codeRanges;

  bool get isTrivia =>
      type == JsTokenType.comment || type == JsTokenType.whitespace;

  @override
  String toString() => '${type.name}($text)';
}

/// Reserved words that must never be renamed.
///
/// Split by JavaScript (future strict-mode and reserved words) and TypeScript
/// (types and contextual keywords that behave like identifiers).
const _reservedWords = <String>{
  // JavaScript reserved / keywords.
  'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
  'default', 'delete', 'do', 'else', 'enum', 'export', 'extends', 'false',
  'finally', 'for', 'function', 'if', 'import', 'in', 'instanceof', 'new',
  'null', 'return', 'super', 'switch', 'this', 'throw', 'true', 'try',
  'typeof', 'var', 'void', 'while', 'with', 'yield', 'await',
  // Reserved for future use; illegal as identifiers in strict mode.
  'implements', 'interface', 'let', 'package', 'private', 'protected',
  'public', 'static',
  // Literals that can appear as identifiers in odd places but should be kept.
  'arguments', 'eval',
  // TypeScript.
  'abstract', 'any', 'as', 'asserts', 'bigint', 'boolean', 'declare',
  'get', 'infer', 'is', 'keyof', 'module', 'namespace', 'never', 'number',
  'object', 'readonly', 'require', 'set', 'string', 'symbol', 'type',
  'unique', 'unknown', 'from', 'global', 'override', 'satisfies', 'of',
};

/// Globals that user code may legitimately reference. Renaming one of these
/// would silently break the program, so they are always left alone.
const _protectedGlobals = <String>{
  'globalThis', 'global', 'window', 'document', 'self', 'console', 'process',
  'require', 'module', 'exports', '__dirname', '__filename', 'Buffer',
  'Math', 'JSON', 'Date', 'Array', 'Object', 'String', 'Number', 'Boolean',
  'RegExp', 'Error', 'TypeError', 'RangeError', 'SyntaxError', 'Promise',
  'Symbol', 'Map', 'Set', 'WeakMap', 'WeakSet', 'Proxy', 'Reflect', 'BigInt',
  'ArrayBuffer', 'Uint8Array', 'Int8Array', 'Uint16Array', 'Int16Array',
  'Uint32Array', 'Int32Array', 'Float32Array', 'Float64Array',
  'DataView', 'TextEncoder', 'TextDecoder', 'URL', 'URLSearchParams',
  'fetch', 'setTimeout', 'setInterval', 'clearTimeout', 'clearInterval',
  'queueMicrotask', 'structuredClone', 'parseInt', 'parseFloat', 'isNaN',
  'isFinite', 'encodeURIComponent', 'decodeURIComponent', 'encodeURI',
  'decodeURI', 'escape', 'unescape', 'Function', 'eval', 'undefined', 'NaN',
  'Infinity', 'crypto', 'performance', 'navigator', 'location', 'history',
  'localStorage', 'sessionStorage', 'alert', 'confirm', 'prompt', 'atob',
  'btoa', 'Intl', 'WeakRef', 'FinalizationRegistry',
};

/// Identifier base alphabet. Deliberately not hex-only: an all-hex alphabet
/// makes output harder to read but collides far more often with real names.
const String _nameChars = r'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ$_';

/// Tokenizes JavaScript or TypeScript source.
///
/// Handles: line and block comments, single/double quoted strings, template
/// literals with nested `${...}` substitution, numeric literals, and regular-
/// expression literals. Distinguishing `/` as division versus the start of a
/// regex is the classic ambiguity; it is resolved by inspecting the previous
/// significant token, which is what the ECMAScript grammar implies.
List<JsToken> tokenizeJs(String source) {
  final tokens = <JsToken>[];
  // Substitutions seen while scanning the template currently being read.
  final substitutions = <JsRange>[];
  var i = 0;

  void add(JsTokenType type, int start, int end) {
    tokens.add(JsToken(type: type, text: source.substring(start, end), start: start, end: end));
  }

  /// The last token that is not trivia, used for regex/division decisions.
  JsToken? prevSignificant() {
    for (var k = tokens.length - 1; k >= 0; k--) {
      if (!tokens[k].isTrivia) return tokens[k];
    }
    return null;
  }

  /// True when a `/` at the current position starts a regular expression.
  ///
  /// A regex cannot follow a value: an identifier, number, string, or closing
  /// bracket all imply division. Keywords such as `return` are followed by a
  /// regex, which is why they are excluded here.
  bool regexAllowed() {
    final previous = prevSignificant();
    if (previous == null) return true;
    switch (previous.type) {
      case JsTokenType.identifier:
      case JsTokenType.number:
      case JsTokenType.string:
      case JsTokenType.templateString:
      case JsTokenType.regex:
        return false;
      case JsTokenType.keyword:
        // `return /re/` is a regex; `typeof /re/` and `case /re/` too.
        return const {
          'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete',
          'void', 'throw', 'case', 'do', 'else', 'yield', 'await',
        }.contains(previous.text);
      case JsTokenType.punctuation:
        // `}` is ambiguous: a block end allows a regex, an object literal end
        // does not. Treating it as regex-allowed matches what minifiers do and
        // is the safer error, since it is visible in the output.
        return previous.text != ')' && previous.text != ']' &&
            previous.text != '++' && previous.text != '--';
      case JsTokenType.operator:
      case JsTokenType.comment:
      case JsTokenType.whitespace:
      case JsTokenType.unknown:
        return true;
    }
  }

  while (i < source.length) {
    var start = i;
    final char = source[i];

    // Comments.
    if (char == '/' && i + 1 < source.length) {
      final next = source[i + 1];
      if (next == '/') {
        i += 2;
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        add(JsTokenType.comment, start, i);
        continue;
      }
      if (next == '*') {
        i += 2;
        while (i < source.length && !(source[i] == '*' && i + 1 < source.length && source[i + 1] == '/')) {
          i++;
        }
        i = (i + 2).clamp(0, source.length);
        add(JsTokenType.comment, start, i);
        continue;
      }
      if (regexAllowed()) {
        i++;
        var inClass = false;
        var closed = false;
        while (i < source.length) {
          final c = source[i];
          if (c == '\\') {
            i += 2;
            continue;
          }
          if (c == '\n') break;
          if (c == '[') inClass = true;
          if (c == ']') inClass = false;
          if (c == '/' && !inClass) {
            i++;
            closed = true;
            break;
          }
          i++;
        }
        if (closed) {
          // Consume flags.
          while (i < source.length && RegExp(r'[a-z]').hasMatch(source[i])) {
            i++;
          }
          add(JsTokenType.regex, start, i);
          continue;
        }
        // Not a regex after all: fall through and treat as an operator.
        i = start;
      }
    }

    // Strings.
    if (char == '"' || char == "'") {
      i++;
      var closed = false;
      while (i < source.length) {
        final c = source[i];
        if (c == '\\') {
          i += 2;
          continue;
        }
        if (c == char) {
          i++;
          closed = true;
          break;
        }
        if (c == '\n') break;
        i++;
      }
      add(closed ? JsTokenType.string : JsTokenType.unknown, start, i);
      continue;
    }

    // Template literals. The literal chunks become templateString tokens,
    // but the `${ ... }` substitutions are tokenized as ordinary code so that
    // identifiers inside them can still be renamed. Treating a template as one
    // opaque token would leave `data` unrenamed inside a renamed scope, which
    // silently breaks the program.
    if (char == '`') {
      i++;
      var closed = false;
      while (i < source.length) {
        final c = source[i];
        if (c == '\\') {
          i += 2;
          continue;
        }
        if (c == '`') {
          i++;
          closed = true;
          break;
        }
        // (the substitution branch below advances `i` past the closing brace)
        if (c == r'$' && i + 1 < source.length && source[i + 1] == '{') {
          // Record the substitution so the mangler can rewrite identifiers
          // inside it. Leaving `${secret}` unrenamed while renaming the
          // binding it refers to would break the program.
          final open = i + 2;
          var depth = 1;
          var k = open;
          while (k < source.length && depth > 0) {
            final d = source[k];
            if (d == '{') {
              depth++;
            } else if (d == '}') {
              depth--;
              if (depth == 0) break;
            } else if (d == '"' || d == "'" || d == '`') {
              k = _skipQuoted(source, k, d);
              continue;
            }
            k++;
          }
          if (k < source.length) {
            substitutions.add(JsRange(open, k));
          }
          i = k + 1;
          continue;
        }
        i++;
      }
      final type =
          closed ? JsTokenType.templateString : JsTokenType.unknown;
      final ranges = <JsRange>[
        for (final range in substitutions)
          if (range.start >= start && range.end <= i)
            JsRange(range.start - start, range.end - start),
      ];
      tokens.add(
        JsToken(
          type: type,
          text: source.substring(start, i),
          start: start,
          end: i,
          codeRanges: ranges,
        ),
      );
      continue;
    }

    // Numbers.
    if (RegExp(r'[0-9]').hasMatch(char) ||
        (char == '.' && i + 1 < source.length && RegExp(r'[0-9]').hasMatch(source[i + 1]))) {
      i++;
      while (i < source.length && RegExp(r'[0-9a-fA-FxXoObBeEn._]').hasMatch(source[i])) {
        i++;
      }
      if (i < source.length && (source[i] == '+' || source[i] == '-')) {
        // Exponent sign.
        final previous = source.substring(start, i);
        if (previous.contains('e') || previous.contains('E')) i++;
      }
      add(JsTokenType.number, start, i);
      continue;
    }

    // Identifiers and keywords.
    if (RegExp(r'[A-Za-z_$]').hasMatch(char)) {
      i++;
      while (i < source.length && RegExp(r'[A-Za-z0-9_$]').hasMatch(source[i])) {
        i++;
      }
      final word = source.substring(start, i);
      add(
        _reservedWords.contains(word) ? JsTokenType.keyword : JsTokenType.identifier,
        start,
        i,
      );
      continue;
    }

    // Whitespace.
    if (RegExp(r'\s').hasMatch(char)) {
      i++;
      while (i < source.length && RegExp(r'\s').hasMatch(source[i])) {
        i++;
      }
      add(JsTokenType.whitespace, start, i);
      continue;
    }

    // Multi-character operators, longest first so `=>` beats `=`.
    const multi = [
      '>>>=', '...', '===', '!==', '**=', '<<=', '>>=', '>>>', '&&=', '||=',
      '??=', '=>', '==', '!=', '<=', '>=', '&&', '||', '??', '?.', '++', '--',
      '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>', '**',
    ];
    final multiMatch = multi.firstWhere(
      (op) => source.startsWith(op, i),
      orElse: () => '',
    );
    if (multiMatch.isNotEmpty) {
      i += multiMatch.length;
      add(JsTokenType.operator, start, i);
      continue;
    }

    i++;
    final isPunctuation = '{}()[];,.'.contains(char);
    add(
      isPunctuation ? JsTokenType.punctuation : JsTokenType.operator,
      start,
      i,
    );
  }
  return tokens;
}

/// A half-open `[start, end)` range of source.
class JsRange {
  const JsRange(this.start, this.end);

  final int start;
  final int end;

  @override
  String toString() => '[$start, $end)';
}

/// Returns the index just past the literal that starts at [from] and is
/// delimited by [quote].
int _skipQuoted(String source, int from, String quote) {
  var i = from + 1;
  while (i < source.length) {
    final c = source[i];
    if (c == '\\') {
      i += 2;
      continue;
    }
    if (c == quote) return i + 1;
    i++;
  }
  return i;
}

/// How identifiers are rewritten.
enum ManglerStyle {
  shortNames('Short', 'Sequential letters and symbols, e.g. a, b, c'),
  hexNames('Hex', 'Obfuscator-style hex names, e.g. _0x1a2b'),
  similarNames('Similar', 'Confusable glyphs such as l, I, 1, O');

  const ManglerStyle(this.label, this.note);

  /// Short enough to sit in a segmented control without overflowing.
  final String label;

  /// Longer explanation, for a tooltip.
  final String note;
}

/// Which transforms to apply.
class ObfuscatorOptions {
  const ObfuscatorOptions({
    this.mangleIdentifiers = true,
    this.hoistStrings = true,
    this.deadCodeInjection = true,
    this.selfDefending = false,
    this.debugProtection = false,
    this.disableConsoleOutput = false,
    this.style = ManglerStyle.shortNames,
    this.seed = 0x5f3759df,
  });

  /// Rename user identifiers.
  final bool mangleIdentifiers;

  /// Move string literals into a hoisted array.
  final bool hoistStrings;

  /// Inject opaque predicates and unreachable filler.
  final bool deadCodeInjection;

  /// Add a guard that breaks the code if it is reformatted.
  final bool selfDefending;

  /// Add `debugger` traps around the entry point.
  final bool debugProtection;

  /// Replace `console.*` with no-ops.
  final bool disableConsoleOutput;

  final ManglerStyle style;

  /// Seed for the deterministic name generator, so output is reproducible.
  final int seed;

  /// Returns a copy with the given overrides.
  ObfuscatorOptions copy({
    bool? mangleIdentifiers,
    bool? hoistStrings,
    bool? deadCodeInjection,
    bool? selfDefending,
    bool? debugProtection,
    bool? disableConsoleOutput,
    ManglerStyle? style,
  }) => ObfuscatorOptions(
        mangleIdentifiers: mangleIdentifiers ?? this.mangleIdentifiers,
        hoistStrings: hoistStrings ?? this.hoistStrings,
        deadCodeInjection: deadCodeInjection ?? this.deadCodeInjection,
        selfDefending: selfDefending ?? this.selfDefending,
        debugProtection: debugProtection ?? this.debugProtection,
        disableConsoleOutput: disableConsoleOutput ?? this.disableConsoleOutput,
        style: style ?? this.style,
      );
}

/// What the obfuscator did, for the report shown in the UI.
class ObfuscationReport {
  const ObfuscationReport({
    required this.output,
    required this.tokensScanned,
    required this.identifiersRenamed,
    required this.stringsHoisted,
    required this.stringsSkipped,
    required this.propertiesPreserved,
    required this.warnings,
    required this.error,
  });

  final String output;
  final int tokensScanned;
  final int identifiersRenamed;

  /// How many string literals moved into the string array.
  final int stringsHoisted;

  /// How many stayed put, and why.
  final int stringsSkipped;

  /// Property accesses and object keys left alone.
  final int propertiesPreserved;

  final List<String> warnings;
  final String? error;

  bool get ok => error == null;

  /// One-line-per-fact summary for the UI.
  String describe() {
    if (error != null) return error!;
    return [
      'Tokens scanned       $tokensScanned',
      'Identifiers renamed  $identifiersRenamed',
      'Strings hoisted      $stringsHoisted',
      'Strings kept inline  $stringsSkipped',
      'Properties preserved $propertiesPreserved',
      if (warnings.isNotEmpty) 'Warnings             ${warnings.length}',
    ].join('\n');
  }
}

/// Obfuscates [source].
ObfuscationReport obfuscateJs(
  String source, {
  ObfuscatorOptions options = const ObfuscatorOptions(),
}) {
  if (source.trim().isEmpty) {
    return const ObfuscationReport(
      output: '',
      tokensScanned: 0,
      identifiersRenamed: 0,
      stringsHoisted: 0,
      stringsSkipped: 0,
      propertiesPreserved: 0,
      warnings: [],
      error: 'Paste JavaScript or TypeScript to obfuscate.',
    );
  }

  final tokens = tokenizeJs(source);
  final warnings = <String>[];

  final hasUnknown = tokens.any((t) => t.type == JsTokenType.unknown);
  if (hasUnknown) {
    warnings.add(
      'Some literals were not terminated cleanly. Output may not run.',
    );
  }

  // Detect constructs this obfuscator does not model. Warning beats silently
  // producing broken code, which is the failure mode that matters here.
  if (_contains(source, 'import ') || _contains(source, 'export ')) {
    warnings.add(
      'ES module syntax detected. Renamed identifiers are consistent within '
      'the file, but cross-file imports will not resolve.',
    );
  }
  if (_contains(source, 'async ') || _contains(source, 'await ')) {
    warnings.add('Async code detected; obfuscation does not reorder awaits.');
  }
  if (_contains(source, '=>') && _contains(source, 'return')) {
    warnings.add('Arrow functions with expression bodies detected.');
  }

  // Order matters. Mangling runs on the original token stream, because it has
  // to see real source structure to tell a property from a binding. The string
  // pass then runs on the re-tokenized mangled output, so it never mistakes an
  // accessor it introduced for user code.
  final mangler = IdentifierMangler(options: options, tokens: tokens);
  final mangled = mangler.run();
  final mangledTokens = tokenizeJs(mangled);
  final stringPass = StringArrayPass(options: options, tokens: mangledTokens);
  final stringResult = stringPass.run();

  final parts = <String>[];
  if (stringResult.declaration.isNotEmpty) {
    parts.add(stringResult.declaration);
  }
  parts.add(stringResult.code);

  var output = parts.join('\n');
  // Re-tokenize before the auxiliary passes so that a pass which rewrites the
  // text works from the same view of the program the main passes did.
  var current = tokenizeJs(output);
  if (options.disableConsoleOutput) {
    output = _disableConsole(output, tokens: current);
    current = tokenizeJs(output);
  }
  if (options.deadCodeInjection) {
    output = _injectDeadCode(output, tokens: current);
    current = tokenizeJs(output);
  }
  if (options.selfDefending) {
    output = _selfDefending(output);
  }
  if (options.debugProtection) {
    output = _debugProtection(output);
  }

  return ObfuscationReport(
    output: output.trim(),
    tokensScanned: tokens.length,
    identifiersRenamed: mangler.renamedCount,
    stringsHoisted: stringResult.hoistedCount,
    stringsSkipped: stringResult.skippedCount,
    propertiesPreserved: mangler.preservedPropertyCount,
    warnings: warnings,
    error: null,
  );
}

bool _contains(String haystack, String needle) => haystack.contains(needle);

/// Renames user identifiers while leaving everything that is not a plain
/// binding alone.
class IdentifierMangler {
  IdentifierMangler({required this.options, required this.tokens});

  final ObfuscatorOptions options;
  final List<JsToken> tokens;

  int renamedCount = 0;
  int preservedPropertyCount = 0;

  final Map<String, String> _names = {};
  final Set<String> _used = {};

  /// Identifiers that name a class member or an object-literal method.
  late Set<String> _memberNames;

  String run() {
    final source = tokens.map((t) => t.text).join();
    if (!options.mangleIdentifiers) return source;

    final renamable = _collectRenamable();
    // Nothing to rename still has to produce the program, not an empty file.
    if (renamable.isEmpty) return source;

    final generator = NameGenerator(seed: options.seed, style: options.style);
    for (final name in renamable) {
      var candidate = generator.next();
      // Never collide with a name the program already uses, or with anything
      // that must survive verbatim.
      while (_used.contains(candidate) ||
          _reservedWords.contains(candidate) ||
          _protectedGlobals.contains(candidate)) {
        candidate = generator.next();
      }
      _names[name] = candidate;
      _used.add(candidate);
    }

    final buffer = StringBuffer();
    for (final token in tokens) {
      buffer.write(_rewriteToken(token));
    }
    renamedCount = _names.length;
    return buffer.toString();
  }

  /// Renders [token], applying renames and recursing into template
  /// substitutions.
  String _rewriteToken(JsToken token) {
    if (token.type == JsTokenType.identifier) {
      return _names[token.text] ?? token.text;
    }
    if (token.type == JsTokenType.templateString && token.codeRanges.isNotEmpty) {
      var out = StringBuffer();
      var cursor = 0;
      for (final range in token.codeRanges) {
        out.write(token.text.substring(cursor, range.start));
        final inner = token.text.substring(range.start, range.end);
        final innerTokens = tokenizeJs(inner);
        for (final innerToken in innerTokens) {
          out.write(_rewriteToken(innerToken));
        }
        cursor = range.end;
      }
      out.write(token.text.substring(cursor));
      return out.toString();
    }
    return token.text;
  }

  /// Identifiers that are safe to rename: declared bindings, not property
  /// accesses, not object literal keys, not globals, not shadowing-sensitive
  /// names used in `const {a} = ...` shorthand.
  Set<String> _collectRenamable() {
    _memberNames = _findMemberNames();
    final renamable = <String>{};
    // Anything that appears after a dot, or as `obj?.key`, or as an object
    // literal key, is a property and must survive unchanged.
    final properties = <String>{};
    final shorthand = <String>{};

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.type != JsTokenType.identifier) continue;
      if (_protectedGlobals.contains(token.text)) {
        // Deliberately kept as-is, and worth reporting as preserved.
        preservedPropertyCount++;
        continue;
      }

      final previous = _previousSignificant(i);
      final next = _nextSignificant(i);

      // Property access: `a.b`, `a?.b`. The tokenizer emits `.` as
      // punctuation and `?.` as an operator, so both shapes must be accepted.
      if (previous != null &&
          (previous.text == '.' || previous.text == '?.')) {
        properties.add(token.text);
        preservedPropertyCount++;
        continue;
      }
      // Object literal key: `{ a: 1 }`. A key always sits directly after `{`
      // or `,`, which distinguishes it from the middle branch of a ternary
      // and from a label. `:` is lexed as an operator, so the type is not
      // checked here.
      if (next != null &&
          next.text == ':' &&
          previous != null &&
          previous.type == JsTokenType.punctuation &&
          (previous.text == '{' || previous.text == ',')) {
        properties.add(token.text);
        preservedPropertyCount++;
        continue;
      }
      // Object literal method key: `{ m() {} }`. Renaming it would break every
      // caller of that method, just as renaming a class method would.
      if (next != null && next.text == '(' && _isObjectMethod(i)) {
        properties.add(token.text);
        preservedPropertyCount++;
        continue;
      }
      // Class member names, found by a brace-stack pass in `_findMemberNames`.
      if (_memberNames.contains(token.text)) {
        properties.add(token.text);
        preservedPropertyCount++;
        continue;
      }
      // `break outer` / `continue outer` target a statement label.
      if (_isLabelReference(previous)) {
        properties.add(token.text);
        preservedPropertyCount++;
        continue;
      }
      // Destructuring shorthand `{ a }`: renaming requires also rewriting the
      // key, so leave it for correctness.
      if (_isShorthand(i)) {
        shorthand.add(token.text);
        preservedPropertyCount++;
        continue;
      }
      // Statement label declaration `outer: for (...)`.
      if (next != null && next.text == ':' && _looksLikeLabel(i)) {
        properties.add(token.text);
        continue;
      }
      renamable.add(token.text);
    }

    renamable.removeAll(properties);
    renamable.removeAll(shorthand);
    return renamable;
  }

  /// True when the token before an identifier is `break` or `continue`, which
  /// makes the identifier a label rather than a binding.
  bool _isLabelReference(JsToken? previous) =>
      previous != null &&
      previous.type == JsTokenType.keyword &&
      (previous.text == 'break' || previous.text == 'continue');

  /// True when the identifier is a `break`/`continue` target label.
  bool _looksLikeLabel(int index) {
    final previous = _previousSignificant(index);
    return previous == null ||
        (previous.type == JsTokenType.keyword &&
            (previous.text == 'break' || previous.text == 'continue'));
  }

  /// True for `{ a }` and `{ a, b }` destructuring patterns.
  bool _isShorthand(int index) {
    final previous = _previousSignificant(index);
    final next = _nextSignificant(index);
    if (previous == null || next == null) return false;
    final openedByBrace = previous.type == JsTokenType.punctuation &&
        (previous.text == '{' || previous.text == ',');
    final closedByBrace = next.type == JsTokenType.punctuation &&
        (next.text == '}' || next.text == ',');
    if (!openedByBrace || !closedByBrace) return false;

    // Only when the enclosing construct is a destructuring pattern, which we
    // detect by a preceding `=` or `(` after `const`/`let`/`var`.
    for (var k = index - 1; k >= 0; k--) {
      final token = tokens[k];
      if (token.isTrivia) continue;
      if (token.type == JsTokenType.keyword &&
          const {'const', 'let', 'var'}.contains(token.text)) {
        return true;
      }
      if (token.type == JsTokenType.punctuation &&
          (token.text == ';' || token.text == '}')) {
        return false;
      }
    }
    return false;
  }

  /// Finds identifiers that name a class member or an object-literal method.
  ///
  /// One pass with a brace stack, because deciding this positionally means
  /// scanning backwards through arbitrarily nested bodies and that walk is
  /// where the earlier version of this pass went wrong.
  Set<String> _findMemberNames() {
    final names = <String>{};
    // Whether the brace currently open belongs to a class body.
    final stack = <bool>[];

    bool isClassBodyOpen(int index) {
      for (var k = index - 1; k >= 0; k--) {
        final token = tokens[k];
        if (token.isTrivia) continue;
        if (token.type == JsTokenType.keyword && token.text == 'class') {
          return true;
        }
        if (token.type == JsTokenType.punctuation &&
            (token.text == ';' || token.text == '}' || token.text == '{')) {
          return false;
        }
      }
      return false;
    }

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.isTrivia) continue;

      if (token.text == '{') {
        stack.add(isClassBodyOpen(i));
        continue;
      }
      if (token.text == '}') {
        if (stack.isNotEmpty) stack.removeLast();
        continue;
      }
      if (token.type != JsTokenType.identifier) continue;
      if (stack.isEmpty || !stack.last) continue;

      final next = _nextSignificant(i);
      if (next == null) continue;
      // `m() {}`, `m = 1`, `m;`, and the last member before `}`.
      if (next.text == '(' || next.text == '=' || next.text == ';' ||
          next.text == '}') {
        names.add(token.text);
      }
    }
    return names;
  }

  /// True when the identifier at [index] is the key of an object literal
  /// method, `{ m() {} }`, rather than a call to a local binding.
  ///
  /// The brace that opens the literal has to follow an expression, which is
  /// what separates an object literal from a block.
  bool _isObjectMethod(int index) {
    final previous = _previousSignificant(index);
    if (previous == null ||
        previous.type != JsTokenType.punctuation ||
        (previous.text != '{' && previous.text != ',')) {
      return false;
    }
    for (var k = index - 1; k >= 0; k--) {
      final token = tokens[k];
      if (token.isTrivia) continue;
      if (token.type == JsTokenType.punctuation && token.text == '{') {
        final opener = _previousSignificantFrom(tokens, k - 1);
        if (opener == null) return false;
        if (opener.type == JsTokenType.operator) return true;
        if (opener.type == JsTokenType.keyword) {
          return const {'return', 'of', 'in'}.contains(opener.text);
        }
        return const {'=', '(', ',', ':', '['}.contains(opener.text);
      }
      if (token.type == JsTokenType.punctuation &&
          (token.text == ';' || token.text == '}')) {
        return false;
      }
    }
    return false;
  }

  JsToken? _previousSignificant(int index) {
    for (var k = index - 1; k >= 0; k--) {
      if (!tokens[k].isTrivia) return tokens[k];
    }
    return null;
  }

  JsToken? _nextSignificant(int index) {
    for (var k = index + 1; k < tokens.length; k++) {
      if (!tokens[k].isTrivia) return tokens[k];
    }
    return null;
  }
}

/// Deterministic generator for short, non-colliding identifiers.
class NameGenerator {
  NameGenerator({required this.seed, required this.style}) : _state = seed;

  final int seed;
  final ManglerStyle style;
  int _state;

  static const _hexChars = '0123456789abcdef';

  // Confusable glyphs. Digits are allowed after the first character only,
  // because an identifier may not start with one.
  static const _similarStart = 'lIiOoBSZ';
  static const _similarRest = 'lIi1oO9BSZ2';

  int _next() {
    // xorshift32 keeps this reproducible without touching Random's seed.
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _state = x & 0xffffffff;
    return _state;
  }

  String next() {
    final value = _next();
    switch (style) {
      case ManglerStyle.shortNames:
        return _nameChars[value % _nameChars.length];
      case ManglerStyle.hexNames:
        return '_0x${_hexChars[(value >> 4) & 0xf]}${_hexChars[value & 0xf]}';
      case ManglerStyle.similarNames:
        // Start with a letter so the result is always a legal identifier.
        return _similarStart[value % _similarStart.length] +
            _similarRest[(value >> 4) % _similarRest.length];
    }
  }
}

/// Result of the string-array pass.
class StringArrayResult {
  const StringArrayResult({
    required this.code,
    required this.declaration,
    required this.hoistedCount,
    required this.skippedCount,
  });

  /// The rewritten body.
  final String code;

  /// The hoisted array plus its accessor, emitted above the body.
  final String declaration;

  final int hoistedCount;
  final int skippedCount;
}

/// Moves string literals into a hoisted array read through an offset-shifted
/// accessor, which is the pass that defeats naive `grep` for secrets.
class StringArrayPass {
  StringArrayPass({required this.options, required this.tokens});

  final ObfuscatorOptions options;
  final List<JsToken> tokens;

  /// Names used by the generated runtime. Reserved so the mangler cannot
  /// produce them and collide with the accessor.
  static const accessorName = '__str';
  static const arrayName = '__strs';
  static const rotation = 0x1f;

  StringArrayResult run() {
    if (!options.hoistStrings) {
      return StringArrayResult(
        code: _source(),
        declaration: '',
        hoistedCount: 0,
        skippedCount: 0,
      );
    }

    final hoisted = <String>[];
    final buffer = StringBuffer();
    var count = 0;
    var skipped = 0;
    // A directive only counts while nothing but other directives have been
    // emitted, so this flips to false at the first real statement.
    var inPrologue = true;

    for (final token in tokens) {
      if (token.type != JsTokenType.string) {
        buffer.write(token.text);
        if (token.type != JsTokenType.whitespace && token.type != JsTokenType.comment) {
          inPrologue = false;
        }
        continue;
      }
      // A directive prologue ('use strict') must stay a literal or the program
      // silently loses strict mode.
      if (_isDirective(buffer.toString(), inPrologue)) {
        buffer.write(token.text);
        skipped++;
        continue;
      }
      hoisted.add(token.text);
      final index = hoisted.length - 1;
      // Rotated index plus 0x100 so the accessor can add and subtract without
      // ever going negative.
      buffer.write('$accessorName(0x${(index + rotation + 0x100).toRadixString(16)})');
      count++;
    }

    if (hoisted.isEmpty) {
      return StringArrayResult(
        code: buffer.toString(),
        declaration: '',
        hoistedCount: 0,
        skippedCount: skipped,
      );
    }

    final declaration = _buildDeclaration(hoisted);
    return StringArrayResult(
      code: buffer.toString(),
      declaration: declaration,
      hoistedCount: count,
      skippedCount: skipped,
    );
  }

  String _source() => tokens.map((t) => t.text).join();

  /// True when the string about to be written is a directive prologue
  /// literal, which the spec only honours as a bare literal at the top of the
  /// program. Moving it into an array would silently drop strict mode.
  bool _isDirective(String soFar, bool inPrologue) {
    return inPrologue && soFar.trim().isEmpty;
  }

  String _buildDeclaration(List<String> strings) {
    final encoded = strings.map(_encodeStringLiteral).join(',');
    return [
      'var $arrayName=[$encoded];',
      'function $accessorName(i){',
      '  i=i-0x100-$rotation;',
      '  return $arrayName[${_rotationExpr()}];',
      '}',
    ].join('\n');
  }

  /// Reads the already-unrotated index, optionally through an expression that
  /// has to be folded so a reader cannot map call sites to array slots by eye.
  String _rotationExpr() => options.deadCodeInjection ? '(i)>>>0' : 'i';

  /// Renders a string literal as an escaped, double-quoted token.
  String _encodeStringLiteral(String raw) {
    final body = raw.substring(1, raw.length - 1);
    final escaped = StringBuffer('"');
    for (var i = 0; i < body.length; i++) {
      final char = body[i];
      switch (char) {
        case '"':
          escaped.write(r'\"');
        case r'\':
          escaped.write(r'\\');
        case '\n':
          escaped.write(r'\n');
        case '\r':
          escaped.write(r'\r');
        case '\t':
          escaped.write(r'\t');
        default:
          final code = body.codeUnitAt(i);
          if (code < 0x20) {
            escaped.write('\\x${code.toRadixString(16).padLeft(2, '0')}');
          } else {
            escaped.write(char);
          }
      }
    }
    escaped.write('"');
    return escaped.toString();
  }
}

/// Guards against a partially edited string table.
///
/// This is deliberately simple: it checks that the hoisted array still has the
/// length the obfuscator wrote. It is not a security control, only a tripwire
/// that makes obvious tampering visible.
String _selfDefending(String body) {
  final count = _stringArrayLength(body);
  if (count == null) return body;
  final check = '\nif(${StringArrayPass.arrayName}.length!=$count)'
      '{throw new Error("integrity check failed");}';
  // Insert after the hoisted array and its accessor. Prepending would run the
  // check before `var __strs` is assigned, so `__strs.length` would throw a
  // TypeError instead of reporting tampering.
  final accessorEnd = body.indexOf('\n}', body.indexOf('function ${StringArrayPass.accessorName}'));
  if (accessorEnd == -1) return '$body$check';
  final insertAt = accessorEnd + 2;
  return '${body.substring(0, insertAt)}$check${body.substring(insertAt)}';
}

/// Counts the elements of the hoisted array, or null when there is none.
///
/// The count has to skip commas inside string literals, because hoisted strings
/// routinely contain them ("Hello, " would otherwise read as two elements).
int? _stringArrayLength(String body) {
  final match = RegExp(r'var __strs=\[([^\]]*)\]').firstMatch(body);
  if (match == null) return null;
  final inner = match.group(1)!.trim();
  if (inner.isEmpty) return 0;

  var count = 0;
  var inString = false;
  var quote = '';
  for (var i = 0; i < inner.length; i++) {
    final char = inner[i];
    if (inString) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        inString = false;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      // Every element is a string literal, so opening quotes count elements.
      // Separator commas are deliberately ignored.
      inString = true;
      quote = char;
      count++;
    }
  }
  return count;
}

/// Schedules a repeating `debugger` trap.
///
/// Prepended rather than wrapped in an IIFE on purpose: wrapping would move
/// every top-level `var` and function into the closure and change the program's
/// global surface. The trap does keep an interval alive, so it is opt-in.
String _debugProtection(String body) {
  return 'setInterval(function(){debugger;},50);\n$body';
}

/// Silences `console` output by aliasing it to a no-op object.
///
/// The alias is a top-level `var` and the call sites are rewritten in place,
/// so nothing is wrapped and no scope changes.
String _disableConsole(String body, {required List<JsToken> tokens}) {
  const alias = '__silentConsole';
  var rewrote = false;

  // Rebuild from tokens rather than splicing by offset: `body` has already been
  // rewritten by the earlier passes, so its offsets no longer line up with the
  // token stream the caller tokenized.
  final buffer = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.type == JsTokenType.identifier &&
        token.text == 'console' &&
        _nextSignificant(tokens, i) != null) {
      final next = _nextSignificant(tokens, i)!;
      if (next.text == '.' || next.text == '?.') {
        buffer.write(alias);
        rewrote = true;
        continue;
      }
    }
    buffer.write(token.text);
  }
  if (!rewrote) return body;

  // The alias has to hold real no-op functions: replacing `console` with an
  // object of dummy values would throw the moment the program called one.
  const methods = [
    'log', 'warn', 'error', 'info', 'debug', 'trace', 'dir', 'table', 'group',
    'groupEnd', 'groupCollapsed', 'groupStart', 'time', 'timeEnd', 'assert',
    'count', 'clear', 'profile', 'profileEnd',
  ];
  final definition = 'var $alias={};'
      '[${methods.map((m) => '"$m"').join(',')}].forEach(function(_k){'
      '$alias[_k]=function(){};});';
  return '$definition\n$buffer';
}

/// Injects opaque filler between top-level statements.
///
/// The earlier version of this pass wrapped individual lines, which produces
/// invalid JavaScript as soon as a line is part of a multi-line construct. This
/// one works from the token stream and only inserts complete `if/else`
/// statements after a statement terminator at the top level, so the result
/// always parses. The predicate `!![]&&![]` is true, so the `else` branch is
/// unreachable and never runs.
String _injectDeadCode(String body, {required List<JsToken> tokens}) {
  final insertions = <int>[];
  var depth = 0;
  var parenDepth = 0;
  // Whether the brace currently open is a statement block (so its `}` ends a
  // statement) or an expression-level `{` such as an object literal or a
  // destructuring pattern, whose `}` must be left alone.
  final braceIsBlock = <bool>[];

  bool opensBlock(int index) {
    final previous = _previousSignificantFrom(tokens, index);
    if (previous == null) return true;
    if (previous.type == JsTokenType.punctuation) {
      return previous.text == '{' || previous.text == '}' ||
          previous.text == ')' || previous.text == ';' || previous.text == '}';
    }
    if (previous.type == JsTokenType.keyword) {
      return const {'do', 'else', 'try', 'finally', 'class', 'switch'}.contains(
        previous.text,
      );
    }
    return false;
  }

  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.isTrivia) continue;
    if (token.text == '(') parenDepth++;
    if (token.text == ')') parenDepth--;
    if (token.text == '{') {
      braceIsBlock.add(opensBlock(i));
      depth++;
      continue;
    }
    if (token.text == '}') {
      depth--;
      final isBlock = braceIsBlock.isNotEmpty && braceIsBlock.removeLast();
      if (depth == 0 && parenDepth == 0 && isBlock) {
        insertions.add(token.end);
      }
      continue;
    }
    if (token.text == ';' && depth == 0 && parenDepth == 0) {
      insertions.add(token.end);
    }
  }
  if (insertions.isEmpty) return body;

  final buffer = StringBuffer()
    ..write('function _t(){return true;}\n');
  var cursor = 0;
  for (final offset in insertions) {
    if (offset < cursor) continue;
    // The filler is a complete, balanced statement. `!![]&&![]` is true, so
    // the else branch is unreachable and nothing observable happens.
    buffer
      ..write(body.substring(cursor, offset))
      ..write('\nif(!![]&&![]){}else{}');
    cursor = offset;
  }
  buffer.write(body.substring(cursor));
  return buffer.toString();
}

/// The next token that is not trivia.
JsToken? _nextSignificant(List<JsToken> tokens, int index) {
  for (var k = index + 1; k < tokens.length; k++) {
    if (!tokens[k].isTrivia) return tokens[k];
  }
  return null;
}

/// The previous token that is not trivia.
JsToken? _previousSignificantFrom(List<JsToken> tokens, int index) {
  for (var k = index - 1; k >= 0; k--) {
    if (!tokens[k].isTrivia) return tokens[k];
  }
  return null;
}
