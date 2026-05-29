# Microcopy Reference

## Contents
- Principles for DevUtils
- Existing Copy Audit
- Tooltip Standards
- Error Messages
- Empty States
- DO/DON'T Pairs

---

## Principles for DevUtils

DevUtils copy must be **terse, direct, and action-oriented**. Users are developers who know what tools do — do not explain basic concepts. Every word competes for attention in a dense UI.

Rules:
1. Verb-first for actions: "Copy", "Go", "Clear", "Sample" — not "Click to copy" or "Run tool"
2. No exclamation marks, no marketing language
3. Error messages say what went wrong and what to fix — not "Something went wrong"
4. Placeholder text shows expected input format, not generic "Enter text here"

---

## Existing Copy Audit

| Location | Current copy | Assessment |
|----------|-------------|------------|
| sidebar.dart:69 | `'Search...'` | Good — terse |
| sidebar.dart:97 | `'No favorites yet.'` | Good — informative without drama |
| main_shell.dart:73 | `'No tools match your search.'` | Good — clear cause |
| main_shell.dart:136 | `'Add to favorites'` / `'Remove from favorites'` | Good — action labels |
| widgets.dart:29 | `'Clipboard'` tooltip | Acceptable — could be `'Paste from clipboard'` for clarity |
| widgets.dart:38 | `'Sample'` tooltip | Acceptable — could be `'Load sample data'` |

---

## Tooltip Standards

Every `IconButton` must have a tooltip. Follow this verb pattern:

| Icon | Tooltip |
|------|---------|
| `Icons.content_paste` | `'Paste from clipboard'` |
| `Icons.auto_awesome` | `'Load sample data'` |
| `Icons.clear` | `'Clear'` |
| `Icons.copy_all` | `'Copy result'` |
| `Icons.star_border` | `'Add to favorites'` |
| `Icons.star` | `'Remove from favorites'` |

---

## Error Messages

Error copy shown in output `EditorPane` (readOnly):

| Scenario | Bad copy | Good copy |
|----------|---------|-----------|
| Invalid JSON | `'Error'` | `'Invalid JSON — check for missing brackets or trailing commas'` |
| Empty input | `'No input'` | leave output pane empty; disable Go button |
| Decode failure | `'Failed'` | `'Could not decode — input may not be valid Base64'` |
| Crypto error | `'Exception: ...'` (raw stack) | `'Encryption failed — check key length and input encoding'` |

**NEVER** surface raw exception messages or stack traces in the output pane. Catch, interpret, and display a user-readable cause.

---

## Empty States

| Context | Copy |
|---------|------|
| No search results | `'No tools match "$query"'` |
| No favorites | `'No favorites yet.'` |
| Empty output after clear | *(leave blank — empty placeholder is self-explanatory)* |
| Tool output pending | *(placeholder hint text in EditorPane, e.g., `'Result will appear here'`)* |

---

## DO / DON'T Pairs

**DO** use placeholder text to show input format:
```dart
// GOOD
EditorPane(placeholder: 'Paste JWT token here...', ...)
EditorPane(placeholder: '{"key": "value"}', ...)
```

**DON'T** use generic placeholders:
```dart
// BAD
EditorPane(placeholder: 'Enter input here', ...)
```

**DO** write section headers in title case (`SectionHeader`) matching existing style ("Favorites", "Encoding", "Crypto").  
**DON'T** use ALL CAPS section headers — the existing style uses `fontWeight: w600` at 11px for hierarchy, not caps.

**DO** keep button labels to 1-2 words max: "Go", "Clear", "Encode", "Decode", "Copy".  
**DON'T** write "Click to encode" or "Run Encoder" — the button placement makes the action obvious.

**DO** use sentence case for messages and hint text: `'No favorites yet.'`  
**DON'T** use title case for messages: `'No Favorites Yet'` — inconsistent with existing copy.