// Uses the bundled TypeScript 5.9.3 parser. User code is parsed, never executed.
function devutilsCodeOperation(source, operation, indentation) {
  if (operation.startsWith('CSS ') || operation.startsWith('HTML ')) {
    try {
      return {output: DevutilsFormatters.process(source, operation, indentation), valid: true};
    } catch (error) {
      return {output: 'Could not format: ' + error.message, valid: false};
    }
  }
  function parse(text) {
    var file = ts.createSourceFile('input.ts', text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
    if (file.parseDiagnostics.length) {
      var jsx = ts.createSourceFile('input.tsx', text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
      if (!jsx.parseDiagnostics.length) return jsx;
    }
    return file;
  }
  var file = parse(source);
  var errors = file.parseDiagnostics.map(function(diagnostic) {
    var at = file.getLineAndCharacterOfPosition(diagnostic.start || 0);
    return 'Line ' + (at.line + 1) + ', Col ' + (at.character + 1) + ': ' +
      ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n');
  });
  if (errors.length) return {output: errors.join('\n'), valid: false};
  if (operation === 'Verify') {
    return {output: 'No syntax errors found.\nSyntax check only; code was not run and types were not checked.', valid: true};
  }

  if (operation === 'Obfuscate') {
    var jsx = false;
    function findJsx(node) {
      if (ts.isJsxElement(node) || ts.isJsxSelfClosingElement(node) || ts.isJsxFragment(node)) jsx = true;
      ts.forEachChild(node, findJsx);
    }
    findJsx(file);
    if (ts.isExternalModule(file) || jsx) {
      return {output: 'Obfuscation needs a standalone script. Bundle modules and compile JSX first.', valid: false};
    }
    return {output: ts.transpileModule(source, {compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None, removeComments: false}}).outputText, valid: true};
  }

  if (operation === 'Beautify') {
    // Format a syntax-tree printout, rather than splitting every semicolon.
    // This keeps for-loop headers, literal text, comments, and generics intact.
    function expandBlocks(node) {
      if (ts.isBlock(node)) node.multiLine = true;
      ts.forEachChild(node, expandBlocks);
    }
    expandBlocks(file);
    var readable = ts.createPrinter({removeComments: false, newLine: ts.NewLineKind.LineFeed}).printFile(file);
    var options = ts.getDefaultFormatCodeSettings('\n');
    options.indentSize = indentation === '4 spaces' || indentation === 'Tabs' ? 4 : 2;
    options.tabSize = 4;
    options.convertTabsToSpaces = indentation !== 'Tabs';
    var edits = ts.formatting.formatDocument(parse(readable), ts.formatting.getFormatContext(options));
    edits.sort(function(a, b) { return b.span.start - a.span.start; });
    edits.forEach(function(edit) {
      readable = readable.slice(0, edit.span.start) + edit.newText +
        readable.slice(edit.span.start + edit.span.length);
    });
    return {output: readable.trimEnd(), valid: true};
  }

  // Printing the AST inserts statement separators before removing whitespace,
  // preserving automatic semicolon insertion (e.g. return followed by a newline).
  var printed = ts.createPrinter({removeComments: true, newLine: ts.NewLineKind.LineFeed}).printFile(file);
  var normalized = parse(printed);
  var protectedRanges = new Map();
  function protect(node) {
    // Preserve literal content, including whitespace and slashes. A whole
    // template or JSX expression stays intact because its text can be meaningful.
    if (ts.isStringLiteralLike(node) || ts.isRegularExpressionLiteral(node) ||
        ts.isTemplateExpression(node) || ts.isJsxFragment(node) || ts.isJsxElement(node) || ts.isJsxSelfClosingElement(node)) {
      protectedRanges.set(node.getStart(normalized), node.end);
      return;
    }
    ts.forEachChild(node, protect);
  }
  protect(normalized);
  var scanner = ts.createScanner(ts.ScriptTarget.Latest, true, normalized.languageVariant, printed);
  var tokens = [];
  while (scanner.scan() !== ts.SyntaxKind.EndOfFileToken) {
    var start = scanner.getTokenPos();
    var end = protectedRanges.get(start);
    if (end !== undefined) {
      tokens.push(printed.slice(start, end));
      scanner.setTextPos(end);
    } else {
      tokens.push(scanner.getTokenText());
    }
  }
  function needsSpace(left, right) {
    // If merging changes token boundaries (const number, + +, / /, numeric
    // property access, etc.), that space is required by the language.
    var pair = ts.createScanner(ts.ScriptTarget.Latest, true, normalized.languageVariant, left + right);
    pair.scan();
    if (pair.getTokenText() !== left) return true;
    pair.scan();
    if (pair.getTokenText() !== right) return true;
    return pair.scan() !== ts.SyntaxKind.EndOfFileToken;
  }
  var output = '';
  for (var i = 0; i < tokens.length; i++) {
    if (i && needsSpace(tokens[i - 1], tokens[i])) output += ' ';
    output += tokens[i];
  }
  // Keep interpreter directives on their own line.
  if (printed.startsWith('#!')) {
    var newline = printed.indexOf('\n');
    output = printed.slice(0, newline) + '\n' + output;
  }
  return {output: output, valid: true};
}
