# State Matrix Reference

## Contents
- State Matrix Pattern
- Tool Processing States
- Search States
- Favorites States
- WARNING: Missing States
- Verification

---

## State Matrix Pattern

Define the full state matrix before editing any interactive widget. Missing states produce confusing or broken UI.

For every tool widget, cover:

| State | What triggers it | UI behavior |
|-------|-----------------|-------------|
| idle | app load, clear action | placeholder hint text in input pane |
| processing | user runs action | Go button disabled, optional spinner |
| success | operation returns result | output pane populated, Copy button enabled |
| error | invalid input / exception | error message in output pane (readOnly) |
| empty input | user clears input | output pane clears, Go button may disable |

---

## Tool Processing States

```dart
// new code to add — stateful tool pattern with processing state
class _MyToolState extends State<MyTool> {
  final _inputController = TextEditingController();
  final _outputController = TextEditingController();
  bool _processing = false;
  String? _error;

  void _run() {
    setState(() { _processing = true; _error = null; });
    try {
      final result = doWork(_inputController.text);
      setState(() { _outputController.text = result; _processing = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _processing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return EditorPane(
      label: 'Input',
      controller: _inputController,
      onSubmit: _processing ? null : _run,
      actions: [
        ToolButton(label: 'Go', onPressed: _processing ? null : _run),
      ],
      // ... output pane with _error ?? _outputController.text
    );
  }
}
```

`ToolButton` with `onPressed: null` renders as disabled automatically via Flutter's Material state.

---

## Search States

Defined in `MainShell` via `ValueListenableBuilder` (main_shell.dart:16-89):

| State | Condition | Rendered by |
|-------|-----------|-------------|
| Results | `filtered.isNotEmpty` | Sidebar list + tool panel |
| No match | `filtered.isEmpty` && query non-empty | `"No tools match your search."` at main_shell.dart:73 |
| No selection | `selectedTool == null` (edge) | Falls through to same empty message |

---

## Favorites States

Defined by `ValueNotifier<Set<String>> favorites` in `ToolState`:

| State | Condition | Sidebar behavior |
|-------|-----------|-----------------|
| No favorites | `favorites.isEmpty` | "No favorites yet." text (sidebar.dart:97) |
| Has favorites | `favorites.isNotEmpty` | Tools listed under "Favorites" section |
| Tool removed | `toggleFavorite` removes last | Returns to "No favorites yet." |

---

### WARNING: Missing States

**The Problem:**

```dart
// BAD — tool has no processing state; button stays enabled during work
ToolButton(label: 'Go', onPressed: _computeExpensiveResult),
```

**Why This Breaks:**
1. User can double-tap Go, launching duplicate operations.
2. Crypto tools (e.g., PBKDF2 via pointycastle) can block the UI thread — no visual feedback means user thinks the app is frozen.
3. Output pane may briefly show stale result while new computation runs.

**The Fix:**

```dart
// GOOD — disable during processing
ToolButton(label: 'Go', onPressed: _processing ? null : _computeExpensiveResult),
```

---

## Verification

```bash
flutter analyze
flutter test
```

Fix all analyzer warnings before shipping state changes — null safety violations in state callbacks cause runtime crashes on macOS.