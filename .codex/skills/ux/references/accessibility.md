# Accessibility Reference

## Contents
- Desktop Accessibility Baseline
- Keyboard Navigation
- Semantic Labels
- Focus Management
- Contrast and Density
- DO/DON'T Pairs
- WARNING: Icon-Only Buttons

---

## Desktop Accessibility Baseline

DevUtils targets macOS desktop. Flutter on macOS supports VoiceOver via the Semantics tree. Every interactive element must have a readable label — either via `tooltip`, `Semantics`, or native widget semantics.

Minimum bar:
- All `IconButton` widgets have `tooltip` set
- All clickable `InkWell` widgets have `Semantics(label: ...)` or a visible text child
- Focus can reach every interactive control via Tab

---

## Keyboard Navigation

`EditorPane` already wires Enter-to-submit at `lib/ui/widgets.dart:351-365`:

```dart
// Existing — Enter submits, Shift+Enter inserts newline
if (event is KeyDownEvent &&
    event.logicalKey == LogicalKeyboardKey.enter &&
    !HardwareKeyboard.instance.isShiftPressed) {
  onSubmit!();
  return KeyEventResult.handled;
}
```

For Tab order in tool panels: Flutter's default Tab order follows widget tree order. Keep `EditorPane` input above output in the widget tree so Tab moves top-to-bottom logically.

For sidebar navigation — arrow key support is not currently implemented. If adding it:

```dart
// new code to add — keyboard selection in sidebar
Focus(
  onKeyEvent: (node, event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _selectNext();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _selectPrev();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  },
  child: sidebarListView,
)
```

---

## Semantic Labels

```dart
// Existing — IconButton with tooltip (widgets.dart:29-35)
IconButton(
  onPressed: onPressed,
  icon: const Icon(Icons.content_paste, size: 20),
  tooltip: 'Clipboard',     // VoiceOver reads this
)
```

For `_SidebarItem` (`InkWell` wrapping icon + text): the `Text` child provides implicit semantics. If you add icon-only items, wrap with `Semantics`:

```dart
// new code to add — if icon-only sidebar item ever added
Semantics(
  label: tool.name,
  button: true,
  child: InkWell(onTap: onTap, child: Icon(tool.icon)),
)
```

For the favorites star button in `_ToolHeader` (main_shell.dart:132):

```dart
// Existing — tooltip already set
IconButton(
  tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
  ...
)
```

---

## Focus Management

When a tool panel switches (user selects new tool), focus does not automatically move to the new panel's input. For tools where immediate typing is the primary action, request focus explicitly:

```dart
// new code to add — auto-focus input on tool mount
class _MyToolState extends State<MyTool> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
}
```

---

## Contrast and Density

Existing color tokens used in the app:

| Token | Hex | Usage |
|-------|-----|-------|
| sidebar background | `#E4E4E4` | `AppColors.sidebar` |
| selection highlight | `#D8E3EA` | `_SidebarItem` selected |
| hover | `#E2EBF0` | `_SidebarItem` hoverColor |
| section header text | `#6A6A6A` | `SectionHeader` |
| primary action (Go) | `#2FA866` | `ToolButton` Go variant |
| icon accent | `#3E5B6A` | `_ToolHeader` icon |

**Do not introduce new colors** without checking contrast against the background. `#6A6A6A` on `#E4E4E4` is borderline — do not go lighter for instructional text.

---

## DO / DON'T Pairs

**DO** set `tooltip` on every `IconButton` — this is the only accessible label for icon-only controls.  
**DON'T** rely on hover-only `Tooltip` as the sole affordance for required guidance.

**DO** use `VisualDensity.compact` for dense tool UIs (already used in `_ToolHeader`).  
**DON'T** expand padding to marketing-page proportions — this is a utility app.

**DO** keep disabled state visually distinct — `onPressed: null` handles this automatically in Material buttons.  
**DON'T** grey out text without also disabling the control; mismatched states confuse users.

---

### WARNING: Icon-Only Buttons Without Tooltip

**The Problem:**

```dart
// BAD — no tooltip, VoiceOver announces "button"
IconButton(
  icon: const Icon(Icons.copy_all),
  onPressed: _copy,
)
```

**Why This Breaks:**
1. VoiceOver on macOS reads the widget role only: "button". User cannot determine the action.
2. New users have no hover-discoverable label.

**The Fix:**

```dart
// GOOD
IconButton(
  icon: const Icon(Icons.copy_all),
  tooltip: 'Copy result',
  onPressed: _copy,
)
```