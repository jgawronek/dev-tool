# Forms Reference

## Contents
- Form Widgets Available
- LabeledField Pattern
- SmallDropdown Pattern
- SegmentedToggle Pattern
- DO/DON'T Pairs
- WARNING: Controller Lifecycle

---

## Form Widgets Available

DevUtils has no traditional form submission flows. "Forms" are inline tool configuration rows: label + input + optional action. The canonical widgets are in `lib/ui/widgets.dart`:

| Widget | Use case |
|--------|----------|
| `LabeledField` | Key-value config row (label left, text field right) |
| `SmallDropdown` | Compact single-select option |
| `SegmentedToggle` | 2-3 mutually exclusive mode switches |
| `EditorPane` | Multi-line input/output with toolbar |

---

## LabeledField Pattern

```dart
// lib/ui/widgets.dart:399 — existing component
LabeledField(
  label: 'Key size',
  hintText: '256',
  controller: _keySizeController,
)
```

Label column is fixed at 160px (widgets.dart:421). Keep labels short — they do not truncate or wrap.

For read-only output rows:

```dart
LabeledField(
  label: 'Result',
  controller: _resultController,
  readOnly: true,        // prevents user editing
  trailing: ToolButton(label: 'Copy', onPressed: _copy),
)
```

---

## SmallDropdown Pattern

```dart
// lib/ui/widgets.dart:120 — existing component
SmallDropdown(
  items: const ['SHA-256', 'SHA-512', 'MD5'],
  initialValue: 'SHA-256',
  onChanged: (value) => setState(() => _algorithm = value),
)
```

**WARNING:** `SmallDropdown` owns its internal `_value` state (widgets.dart:139). If you need to reset it externally (e.g., "Clear" button resets all fields), use a `Key` to force rebuild:

```dart
// new code to add — reset dropdown via key
SmallDropdown(
  key: ValueKey(_resetCount),   // increment _resetCount on clear
  items: _algorithmOptions,
  initialValue: _defaultAlgorithm,
  onChanged: _onAlgorithmChanged,
)
```

---

## SegmentedToggle Pattern

```dart
// lib/ui/widgets.dart:175 — existing component, for 2-3 exclusive modes
SegmentedToggle(
  options: const ['Encode', 'Decode'],
  initialIndex: 0,
  onChanged: (index) => setState(() => _mode = index == 0 ? Mode.encode : Mode.decode),
)
```

Use for mode switches where both options are always valid. Do not use for conditional features — use a `Checkbox` or `Switch` instead.

---

## DO / DON'T Pairs

**DO** validate input inline — show the error in the output `EditorPane` with `readOnly: true`.  
**DON'T** use `showDialog` for recoverable input errors. Dialogs interrupt flow for a dense tool app.

**DO** use `onSubmit` on `EditorPane` to let Enter trigger the primary action.  
**DON'T** require mouse-only interaction — keyboard paths matter for developer tools.

**DO** use `LabeledField` for config rows that need a consistent 160px label column.  
**DON'T** create ad-hoc `Row(children: [Text(...), TextField(...)])` — misalignment accumulates.

---

### WARNING: Controller Lifecycle

**The Problem:**

```dart
// BAD — controller created inline in build(), leaks on every rebuild
child: TextField(controller: TextEditingController()),
```

**Why This Breaks:**
1. New controller created on every `build()` — old controller never disposed.
2. Memory leak accumulates across tool switches.
3. Text content resets on every rebuild.

**The Fix:**

```dart
// GOOD — controller owned by State, disposed in dispose()
class _MyToolState extends State<MyTool> {
  late final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}
```

---

## Verification

```bash
flutter analyze
# Check for TextEditingController leaks — look for controllers not disposed
grep -n "TextEditingController()" lib/ui/tool_views.dart
```