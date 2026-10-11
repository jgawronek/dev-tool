# Offline formatter assets

`build_vendor.cjs` bundles js-beautify 1.15.4 (HTML/CSS beautification),
CSSO 5.0.5 (CSS minification), and html-minifier 4.0.0 (HTML minification).
The application uses JavaScriptCore and does not need Node or network access.
Embedded JS/CSS/URL minifiers are excluded; HTML formatting preserves those
contents and does not fetch referenced resources. Contributor licenses ship
in `assets/javascript/FORMATTER-LICENSES.txt`.

Rebuild with the command in `build_vendor.cjs`, then `node scripts/formatters/build_vendor.cjs`.

Native regression runner:

```
xcrun swiftc -module-cache-path /private/tmp/devutils-swift-module-cache -framework JavaScriptCore test/support/formatter_engine.swift -o /private/tmp/devutils-formatter-engine-test
flutter test test/tools/formatter_options_test.dart test/tools/formatters_test.dart test/tools/json_operations_test.dart
```

The tests use the native runner when present and the Node VM runner otherwise.
Both load the exact shipped assets. Only fixed test fixtures are executed for
JS semantic comparisons; the application never executes formatter input.
