You are a senior Flutter engineer with strong macOS desktop experience. Build a native-feeling macOS desktop application using Flutter (latest stable) that recreates the attached screenshots of a “DevUtils” style developer toolbox application.

This is a production-quality macOS app, not a prototype. The goal is a fast, offline, extensible toolbox of daily developer utilities.

There are NO locked tools.

Target: Flutter macOS desktop (Runner). Ensure the project has macOS enabled (macos/ folder exists). Everything runs locally. No backend. No subscriptions.

────────────────────────────────────────────────────────
SOURCE OF TRUTH: SCREENSHOTS
────────────────────────────────────────────────────────
- The project contains a folder named `screenshots/`.
- There is one screenshot per utility, plus screenshots for Preferences/Settings.
- Treat the screenshots as the authoritative UI/UX specification.
- For each tool:
  1) Open its screenshot from `screenshots/`
  2) Match layout, spacing, control placement, labels, and pane structure
  3) Recreate all visible buttons, toggles, dropdowns, and headers
  4) If a control appears in the screenshot, include it even if its logic is initially stubbed
- If a behavior is ambiguous, infer it from the most similar tool screenshot rather than inventing a new UI pattern.

Before coding:
- Produce a checklist mapping:
  screenshot filename → tool id → layout pattern (vertical vs split) → required controls → options/settings.

────────────────────────────────────────────────────────
APP GOAL
────────────────────────────────────────────────────────
Build a scalable “Dev Toolbox” Flutter macOS app with:
1) Tool browser sidebar (search, categories, favorites, recents)
2) Tool workspace with Input / Output editors and action toolbars
3) Preferences window with multiple tabs (including Scripting)
4) A modular architecture where adding a new tool requires only:
   - one new tool file
   - one registry entry

Everything runs locally. No backend.

────────────────────────────────────────────────────────
UI / UX REQUIREMENTS
────────────────────────────────────────────────────────

MAIN WINDOW
- Use a desktop-appropriate layout:
  - Left sidebar (fixed width) + right content area
  - Prefer NavigationRail/Custom sidebar list with macOS-style selection highlight, or a custom ListView with Material 3 tuned to look native.
- Left sidebar:
  - Search field at top (“Search…”)
  - Tool list with icons
  - Sections:
    - Favorites (user-pinned tools)
    - Recent (auto-tracked)
    - Categories (Converters, Formatters, Encoders, Security, Text, Generators, etc.)
- Right content area:
  - Toolbar/header:
    - Title displays active tool name
    - Include a small “Demo” pill/button (loads sample data)
  - Workspace patterns:
    A) Vertical layout:
       - Input editor on top
       - Output editor below
    B) Split layout:
       - Input on left
       - Output on right

EDITORS
- Multi-line editors for input/output:
  - Use monospaced font (e.g., Menlo-like via GoogleFonts or default monospace).
  - Should perform well for large text.
  - Use TextField/TextFormField with maxLines: null + ScrollView, or a code editor widget if necessary.
- Input header buttons (as shown in screenshots):
  - ⚡ Run
  - Clipboard
  - Sample
  - Clear
  - Gear icon for tool-specific options
- Output header buttons:
  - Copy
  - Formatting dropdowns (e.g., indentation)
  - “Use as input” where shown in screenshots

MACOS-NATIVE BEHAVIOR (Flutter desktop)
- Clipboard integration via Flutter services clipboard.
- Menubar/shortcuts:
  - Implement keyboard shortcuts using Shortcuts + Actions:
    - ⌘F search
    - ⌘↩ run
    - ⌘⇧C copy output
    - ⌘1 / ⌘2 focus input/output
- Window resizing should be smooth and layout responsive.

────────────────────────────────────────────────────────
PREFERENCES WINDOW
────────────────────────────────────────────────────────
- Implement a separate Preferences window (NOT just a dialog).
  - Use a second window (recommended: `desktop_multi_window`) OR a dedicated route presented as a window-like page if multi-window is not used yet.
- Top tabs:
  - General
  - Hotkeys
  - Appearance
  - Integrations
  - Scripting
  - Updates
  - License

SCRIPTING TAB (match screenshots exactly)
- Segmented control: PHP | OpenSSL | Others
- PHP tab includes:
  - “Default command path” dropdown
  - Shows “No Usable PHP Runtime” if none configured
  - Buttons:
    - “Add New Path…” (opens a native file picker for executable path)
    - “Remove”
  - Text explaining safe mode execution
  - Editable multiline whitelist field
    Default:
      serialize,var_export,json_encode,json_decode,unserialize
- Persist settings using a local store:
  - Prefer `shared_preferences` for simple settings, or `hive`/`isar` if you want structured persistence.
- Actual execution of PHP/OpenSSL is NOT required yet — config UI + persistence only.
- File picking:
  - Use `file_selector` (desktop friendly) to select an executable path.

────────────────────────────────────────────────────────
ARCHITECTURE
────────────────────────────────────────────────────────
Design for growth. Use clean architecture / MVVM-ish.

- Define a DevTool interface (abstract class):
  - id
  - name
  - icon (Material icon or custom asset)
  - category
  - defaultSample
  - supportsBidirectional
  - run(input, options, mode) → output/result (sync or async)
- Each tool has a controller/viewmodel:
  - inputText (TextEditingController)
  - outputText
  - run() method
  - optional live-run toggle per tool
- ToolRegistry:
  - Single source of truth for sidebar ordering and metadata
- Reusable widgets:
  - EditorPane (header + buttons + editor)
  - SplitEditorView
  - OptionsPopover (use MenuAnchor/Popover-like UI)
- Persist:
  - Last selected tool
  - Last input (optional)
  - Last options per tool
  - Window/layout preferences

STATE MANAGEMENT
- Use a straightforward approach:
  - Riverpod preferred (or Provider) for app state + tool selection.
  - Keep tool logic pure and testable.

────────────────────────────────────────────────────────
TOOLS TO IMPLEMENT (FULLY FUNCTIONAL)
────────────────────────────────────────────────────────
Implement these tools exactly as shown in screenshots:

1) HTML Entity Encode / Decode
- Encode and Decode modes (radio buttons or segmented control)
- Encode: < > & " ' → entities
- Decode: standard + numeric entities
- “Use as input” button
- Suggest dependency: `html_unescape` (supports encode/decode via convert()) OR implement manually if preferred.

2) CSV to JSON
- Header row → array of objects
- Handle quoted values and escaped quotes
- Indentation selector (2 spaces / 4 spaces / tabs)
- Pretty-printed JSON output
- Use Dart CSV parsing (either a small robust parser you write or a well-known package if available).

3) Hex ↔ ASCII
- Hex to ASCII:
  - Accept space/newline separated hex
  - Ignore 0x prefixes
- ASCII to Hex:
  - Space-separated byte output
- Side-by-side layout like screenshot

4) JSON Format / Validate
- Pretty print
- Error message on invalid JSON
- Indentation control

5) Unix Time Converter
- Convert between:
  - Unix seconds
  - Unix milliseconds
  - ISO-8601 (local + UTC)

────────────────────────────────────────────────────────
SIDEBAR TOOL LIST (STUBS OK)
────────────────────────────────────────────────────────
Create placeholder tools (UI shells) for the rest of the list shown in screenshots, including but not limited to:
- Base64 Encode/Decode
- JWT Debugger
- RegExp Tester
- URL Encode/Decode
- URL Parser
- Backslash Escape/Unescape
- UUID/ULID
- HTML Preview
- Text Diff
- YAML ↔ JSON
- Beautify/Minify (HTML/CSS/JS/etc.)
- Hash Generator
- SQL Formatter
- Cron Parser
- Color Converter
- PHP / JSON tools
- Certificate Decoder (X.509)
- Line Sort / Dedupe
These should navigate correctly and show correct UI layout even if logic is stubbed.

────────────────────────────────────────────────────────
ERGONOMICS & POLISH
────────────────────────────────────────────────────────
- Drag & drop files into input editor:
  - Use `desktop_drop` (or equivalent) and load file contents into input.
- Open file / Save output:
  - Use `file_selector` for desktop dialogs.
- Error output shown inline (not alerts).
- No third-party dependencies unless necessary; prefer small, stable packages.

────────────────────────────────────────────────────────
DELIVERABLE
────────────────────────────────────────────────────────
Provide:
- A complete Flutter macOS project structure (lib/ + any required desktop plugins)
- All Dart files required to compile and run
- Clear comments
- Clean separation of UI / logic
- Easy extension path for future tools

Build this as if it were a real macOS app you would ship, matching the screenshots as closely as practical in Flutter.