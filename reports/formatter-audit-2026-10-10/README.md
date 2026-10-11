# Formatter audit — 10 October 2026

## Scope

All seven formatter screens and every dropdown value were exercised through
the tool widgets. The macOS integration run also exercised the real formatter
channel, built-in preview, samples, and clipboard actions. Clipboard text was
restored after native checks. Tests use fixed fixtures, not user editor content.

| Screen | Checked dropdown options |
| --- | --- |
| JSON | Prettify, Minify, Stringify, JSON → XML, Escape, Sort keys, Sort arrays; Wrap / No wrap; 2 spaces / 4 spaces / Tabs |
| HTML | Beautify, Minify, Preview; 2 spaces / 4 spaces / Tabs |
| CSS | Beautify, Minify; 2 spaces / 4 spaces / Tabs |
| JS/TS | Beautify, Minify, Obfuscate, Verify; 2 spaces / 4 spaces / Tabs |
| Ruby | Beautify, Minify; 2 spaces / 4 spaces / Tabs; Keep comments / Strip comments |
| XML | Beautify, Minify; 2 spaces / 4 spaces / Tabs; Keep comments / Strip comments |
| SQL | Format, SQL to English; Uppercase / Lowercase; 2 spaces / 4 spaces / Tabs |

Samples, live recomputation, empty input, copying, and returning between modes
were checked for each screen. Regression cases cover quoted values, comments,
Unicode, meaningful whitespace, malformed-input recovery, and indentation.

## Changes

- HTML/CSS use bundled offline formatting libraries instead of global regex
  replacements. HTML preserves inline spacing and raw script/style/pre/textarea
  content. CSS preserves strings, `calc()` separators, and custom-property values.
- JS/TS uses the bundled TypeScript parser in JavaScriptCore. Function bodies
  expand across lines; loop headers stay together. Minify preserves syntax and
  literal text. Tests compare fixed JS fixtures before/after using Node.
- Obfuscate validates input, compiles standalone TypeScript to JS first, and
  correctly wraps Unicode. Modules and JSX get a clear unsupported-input message.
- XML uses the existing XML parser. Mixed text, CDATA, attributes, and xml:space
  content are preserved. Malformed XML produces an error and recovers on editing.
- Ruby protects multiline strings, percent literals, heredocs, and __END__ data.
  Comment stripping removes inline/full-line comments, retaining special directives.
- SQL formatting protects quoted values, identifiers, and comments. English
  explanations protect literals, handle BETWEEN, recognize final clauses, split
  lists outside parentheses, and avoid invented row counts for subquery inserts.
- JSON → XML honors indentation. Indentation controls are hidden for compact
  string/minify operations. SQL's single-choice dialect dropdown is now a label.
- HTML/CSS show processing feedback; native preview load failures are handled.

## Evidence

- `automated-tests.log`: combined formatter/widget/edge-case suite.
- `native-options.log`: seven complete macOS formatter journeys.
- `native-preview.log`: additional native checks of actual preview DOM text and SQL.
- `analysis.log`: full-project Flutter static analysis.
- `build.log`: macOS release build.

Native assets are tested with `test/support/formatter_engine.swift` using the
same JavaScriptCore API and shipped assets as the app. A Node VM fallback lets
those tests run on other systems. Vendored library versions/licenses and rebuild
instructions are in `scripts/formatters/README.md`.

## Limits

These checks cover the listed options and regression fixtures; they cannot prove
correctness for every possible program. Verify checks JS/TS syntax, not types or
behavior. Obfuscate is reversible Base64 for standalone scripts, not encryption.
Ruby is a conservative layout tool, not a full Ruby compiler. SQL to English is
a reading aid for supported structures, not database execution or validation.
HTML Preview disables page JavaScript; the native test reads its DOM with a fixed
trusted expression to check rendered fixture text. External resources were not
tested. File-picker dialogs and file-drop actions were outside this dropdown audit.
