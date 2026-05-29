# Dart Workflows Reference

## Contents
- Adding a New Tool (end-to-end)
- Running and Verifying
- Analysis and Linting
- Testing Patterns
- Anti-Patterns

---

## Adding a New Tool (End-to-End)

Copy this checklist when adding a tool:

- [ ] 1. Write builder function in `lib/ui/tool_views.dart`
- [ ] 2. Register `DevTool` entry in `lib/registry/tool_registry.dart`
- [ ] 3. Run `flutter analyze` — zero errors before continuing
- [ ] 4. Run `flutter run -d macos` and exercise the new tool manually
- [ ] 5. Run `flutter test` — all widget tests pass

**Step 1 — Builder in tool_views.dart:**
```dart
// lib/ui/tool_views.dart — new code to add
Widget buildBase32Encoder() {
  final inputCtrl = TextEditingController();
  final outputCtrl = TextEditingController();

  return buildSplitEditors(
    inputCtrl: inputCtrl,
    outputCtrl: outputCtrl,
    actions: [
      ToolButton(label: 'Encode', onPressed: () {
        // encode logic here
        outputCtrl.text = _base32Encode(inputCtrl.text);
      }),
      ToolButton(label: 'Sample', onPressed: () {
        inputCtrl.text = 'Hello, World!';
      }),
      ToolButton(label: 'Clear', onPressed: () {
        inputCtrl.clear(); outputCtrl.clear();
      }),
    ],
  );
}
```

**Step 2 — Registry entry:**
```dart
// lib/registry/tool_registry.dart — add to existing list
DevTool(
  id: 'base32-encoder',
  name: 'Base32 Encode/Decode',
  icon: Icons.data_array,
  category: 'Encoders',
  builder: (_) => buildBase32Encoder(),
),
```

---

## Running and Verifying

```bash
# Development with hot reload
flutter run -d macos --hot

# Production build
flutter build macos --release
# output: build/macos/Build/Products/Release/dev_tool.app

# Run tests
flutter test
```

**Iterate-until-pass for analysis:**
1. Make changes
2. Run: `flutter analyze`
3. If errors appear, fix them and repeat step 2
4. Only proceed when output shows `No issues found!`

---

## Analysis and Linting

`analysis_options.yaml` enables `flutter_lints` — treat all warnings as blockers,
not suggestions. The CI gate is `flutter analyze`.

```bash
# Check for issues
flutter analyze

# Auto-fix safe issues (import ordering, unnecessary casts, etc.)
dart fix --apply

# Format all Dart files
dart format lib/
```

**Never suppress lints with `// ignore:` unless the reason is documented.** An
ignored lint is a hidden assumption — the next developer won't know why.

---

## Testing Patterns

Tests live in `test/`. Use `ToolState.inMemory()` to avoid SharedPreferences I/O
in unit/widget tests.

```dart
// test/widget_test.dart — existing factory
final state = ToolState.inMemory();   // no async, no disk I/O
```

Widget test structure:
```dart
// new code to add
testWidgets('JSON formatter renders input pane', (tester) async {
  final state = ToolState.inMemory();
  await tester.pumpWidget(
    MaterialApp(home: DevToolApp(state: state)),
  );
  expect(find.byType(TextField), findsWidgets);
});
```

Run with coverage:
```bash
flutter test --coverage
# generates coverage/lcov.info
```

---

## WARNING: Missing `WidgetsFlutterBinding.ensureInitialized()`

**The Problem:**
```dart
// BAD — async plugin calls before binding is ready
void main() async {
  final state = await ToolState.load();  // SharedPreferences before binding
  runApp(DevToolApp(state: state));
}
```

**Why This Breaks:**
Platform channels (used by `shared_preferences`) require the Flutter engine
binding to be initialized first. Calling them before `ensureInitialized()` throws
`ServicesBinding not yet initialized`.

**The Fix:** The existing `main.dart` already does this correctly:
```dart
// lib/main.dart — existing, correct
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await ToolState.load();
  runApp(DevToolApp(state: state));
}
```

Never remove `ensureInitialized()` when refactoring `main()`.

---

## WARNING: Registering Tools Without Unique IDs

**The Problem:**
```dart
// BAD — duplicate ID
DevTool(id: 'json-formatter', name: 'JSON Formatter 2', ...),
// 'json-formatter' already exists in the registry
```

**Why This Breaks:**
1. `ToolState.selectedToolId` uses the ID as a key in `SharedPreferences`.
2. Two tools with the same ID means persisted selection is ambiguous.
3. Favorites set uses IDs — a duplicate ID will toggle both tools simultaneously.

**The Fix:** IDs are kebab-case slugs; make them globally unique across the registry.
Search before adding: `grep -r 'id:' lib/registry/tool_registry.dart`.

See the **flutter** skill for widget composition patterns.