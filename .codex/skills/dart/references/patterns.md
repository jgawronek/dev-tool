# Dart Patterns Reference

## Contents
- ValueNotifier State Pattern
- Tool Registry Pattern
- Import Organization
- Null Safety Patterns
- Anti-Patterns

---

## ValueNotifier State Pattern

`ToolState` owns all reactive state. Listeners rebuild only the widgets that
subscribe — no `setState` on parent widgets, no `InheritedWidget` boilerplate.

```dart
// lib/state/tool_state.dart — existing
class ToolState {
  final ValueNotifier<String?> selectedToolId = ValueNotifier(null);
  final ValueNotifier<String> searchQuery = ValueNotifier('');
  final ValueNotifier<Set<String>> favorites = ValueNotifier({});

  void toggleFavorite(String id) {
    final updated = Set<String>.from(favorites.value);
    updated.contains(id) ? updated.remove(id) : updated.add(id);
    favorites.value = updated;          // triggers rebuild in listeners
    _persist();
  }
}
```

Consume in widgets with `ValueListenableBuilder`:

```dart
// new code to add
ValueListenableBuilder<String?>(
  valueListenable: toolState.selectedToolId,
  builder: (context, id, _) => Text(id ?? 'No tool selected'),
)
```

**Never mutate `ValueNotifier.value` in-place for collections** — mutations to
the underlying Set/List don't fire listeners. Always assign a new collection
(as `toggleFavorite` does above).

---

## Tool Registry Pattern

`ToolRegistry.tools` is the single source of truth. Adding a tool requires
exactly two edits: a builder in `tool_views.dart` and an entry in the registry.

```dart
// lib/registry/tool_registry.dart — existing pattern (add to list)
DevTool(
  id: 'url-parser',
  name: 'URL Parser',
  icon: Icons.link,
  category: 'Parsers',
  builder: (_) => buildUrlParser(),
),
```

`DevTool.builder` is typed as `ToolViewBuilder` — a `typedef` returning a
`Widget`. The `(_)` receives `BuildContext` but most tools don't need it.

---

## Null Safety Patterns

Dart 3 enforces sound null safety at compile time. Common patterns in this codebase:

```dart
// GOOD — factory with nullable SharedPreferences result
static Future<ToolState> load() async {
  final prefs = await SharedPreferences.getInstance();
  final savedId = prefs.getString('selectedToolId');  // String? — may be null
  final state = ToolState();
  if (savedId != null) state.selectedToolId.value = savedId;
  return state;
}

// GOOD — in-memory factory for tests (no async, no prefs)
static ToolState inMemory() => ToolState();
```

**NEVER use `!` (bang operator) on values that can legitimately be null.** Use
`??`, `if (x != null)`, or pattern matching instead. A `Null check operator
used on a null value` crash in production is always a missing null check.

---

## AppColors ThemeExtension

Access brand colors without hardcoding hex anywhere outside `app.dart`:

```dart
// lib/app.dart — existing
class AppColors extends ThemeExtension<AppColors> {
  final Color sidebar;
  // ...
}

// Consuming in widgets — new code to add
final colors = Theme.of(context).extension<AppColors>()!;
Container(color: colors.sidebar, ...)
```

---

## WARNING: Mutating ValueNotifier Collections In-Place

**The Problem:**
```dart
// BAD — listener never fires
toolState.favorites.value.add('jwt-debugger');
```

**Why This Breaks:**
1. `ValueNotifier` fires listeners only when `.value` is reassigned.
2. Mutating the existing `Set` skips the assignment, so the UI never rebuilds.
3. State and UI silently diverge — the Set has the new item but the sidebar doesn't show the star.

**The Fix:**
```dart
// GOOD — new Set assignment triggers rebuild
final next = Set<String>.from(toolState.favorites.value)..add('jwt-debugger');
toolState.favorites.value = next;
```

---

## WARNING: Synchronous I/O in Build Methods

**The Problem:**
```dart
// BAD — SharedPreferences.getInstance() is async
@override
Widget build(BuildContext context) {
  final prefs = SharedPreferences.getInstance(); // returns Future, not instance
}
```

**Why This Breaks:**
1. `build()` is synchronous; you cannot `await` inside it.
2. The `Future` object is useless without `await` — you get a type error or stale data.
3. Causes repeated async work on every frame.

**The Fix:** Initialize in `main()` before `runApp()`, as the project already does via `ToolState.load()`.
```dart
// lib/main.dart — existing pattern
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await ToolState.load();
  runApp(DevToolApp(state: state));
}
```

See the **shared-preferences** skill for persistence patterns.