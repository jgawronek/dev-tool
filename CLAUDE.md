# DevUtils

A native macOS desktop application built with Flutter that provides a comprehensive toolbox of developer utilities. DevUtils is fast, offline, and extensible—enabling developers to quickly access common tasks like JSON formatting, base64 encoding/decoding, JWT debugging, and cryptographic operations without leaving their desktop.

## Tech Stack

| Layer | Technology | Version | Purpose |
|-------|------------|---------|---------|
| Runtime | Flutter | 3.24+ (stable) | Cross-platform desktop framework |
| Language | Dart | 3.10.4+ | Primary language with strong typing |
| UI Framework | Material Design 3 | Latest | Native Material Design components |
| State Management | ValueNotifier | Built-in | Simple, lightweight reactive state |
| Crypto | pointycastle | 3.7+ | Advanced cryptographic operations |
| Persistence | shared_preferences | 2.3+ | Local key-value storage for settings |
| Serialization | yaml, http | Latest | YAML parsing and HTTP requests |

## Quick Start

```bash
# Prerequisites
- Flutter 3.24+ (stable channel)
- Dart 3.10.4+
- macOS 10.15+ (for development and deployment)
- Xcode command line tools

# Installation
git clone [repository-url]
cd dev-tool
flutter pub get

# Development
flutter run -d macos
# Or with hot reload enabled:
flutter run -d macos --hot

# Testing
flutter test

# Build for production
flutter build macos --release
# Output: build/macos/Build/Products/Release/dev_tool.app
```

## Project Structure

```
dev-tool/
├── lib/
│   ├── main.dart              # Entry point, app initialization
│   ├── app.dart               # App widget, theme configuration
│   ├── models/
│   │   └── dev_tool.dart      # DevTool model definition
│   ├── state/
│   │   └── tool_state.dart    # Reactive state (selected tool, favorites, search)
│   ├── registry/
│   │   └── tool_registry.dart # Central registry of all available tools
│   ├── services/
│   │   └── local_llm_service.dart # External service integrations
│   ├── ui/
│   │   ├── main_shell.dart    # Root shell/layout widget
│   │   ├── sidebar.dart       # Left sidebar (search, categories, favorites)
│   │   ├── tool_views.dart    # Barrel re-exporting all tool builders
│   │   ├── widgets.dart       # Reusable UI components
│   │   └── tools/             # One file per tool, grouped by category
│   │       ├── common/        # Shared helpers and split-editor layouts
│   │       ├── ai/  converters/  encoders/  formatters/
│   │       ├── generators/  network/  parsers/  preferences/
│   │       ├── preview/  reference/  security/  text/
│   │       └── diagrams/
│   └── data/
│       └── mime_types.dart    # MIME type constants and utilities
├── test/
│   └── widget_test.dart       # Widget tests
├── android/, ios/, linux/, macos/, windows/ # Platform-specific code
├── pubspec.yaml               # Dart package manifest
├── analysis_options.yaml      # Linting rules
├── .metadata                  # Flutter project metadata
└── README.md                  # Public-facing documentation
```

## Architecture Overview

DevUtils follows a **tool-registry pattern** designed for extensibility. The application maintains a clear separation between the tool definitions, UI presentation, state management, and individual tool implementations.

### Key Architectural Patterns

**Tool Registry (Single Source of Truth)**
- All available tools are registered in `ToolRegistry.tools` (lib/registry/tool_registry.dart)
- Each tool is defined as a `DevTool` object containing: id, name, icon, builder (widget factory), category, and demo data
- Adding a new tool requires only: (1) creating a builder function in a new file under `lib/ui/tools/<category>/`, (2) exporting it from the `lib/ui/tool_views.dart` barrel, (3) registering it in `ToolRegistry`

**State Management via ValueNotifier**
- `ToolState` (lib/state/tool_state.dart) manages reactive state without external dependencies
- Reactive properties: `selectedToolId`, `searchQuery`, `favorites`
- State is persisted to device storage via `shared_preferences`
- ValueNotifier listeners automatically trigger rebuilds when state changes

**UI Composition**
- `MainShell`: Root layout with sidebar + content area
- `EditorPane`: Reusable component for input/output editor pairs
- Tool-specific views returned as widget builders from the registry
- Material Design 3 theming applied globally in `app.dart`

### Module Purposes

| Module | Location | Purpose |
|--------|----------|---------|
| Models | `lib/models/` | Data structures (`DevTool`) defining tool metadata |
| State | `lib/state/` | Reactive state holders using `ValueNotifier` for app state |
| Registry | `lib/registry/` | Central registry listing all available tools |
| Services | `lib/services/` | External integrations (LLM, file system, network) |
| UI - Widgets | `lib/ui/widgets.dart` | Reusable UI components (buttons, editors, dropdowns) |
| UI - Tools | `lib/ui/tools/<category>/` | One file per tool (JSON formatter, Base64, etc.); `lib/ui/tool_views.dart` is the barrel |
| UI - Shell | `lib/ui/main_shell.dart` | Root layout and navigation structure |
| Data | `lib/data/` | Constants and utilities (MIME types) |

## UI/UX Quality Contract

For frontend, mobile, desktop, CLI, form, dashboard, onboarding, account/settings, or visual polish tasks:

1. Inspect nearby screens/components, the component library, design tokens, and existing density before creating new structure or styles.
2. Reuse existing components and hooks for repeated UI jobs such as tables, FAQs/accordions, forms, sticky CTAs, pricing, checkout, navigation, and analytics-triggered controls.
3. Choose a surface-appropriate direction: dashboard/tooling should be quiet, dense, and scannable; marketing can be more memorable; CLI/Ink should prioritize stable layout, truncation, and keyboard clarity.
4. Avoid generic AI slop, template-looking screens, random gradient/card stacks, and UI that ignores the product context.
5. For changed interactive flows, define the state matrix before coding: loading, empty, error, disabled, pending, success, retry/recovery, and long-text cases.
6. Verify accessibility basics: labels, focus states, keyboard path, semantic controls, contrast, ARIA state for disclosure widgets, and non-hover-only guidance.
7. Keep UX distinct from product strategy: UX covers concrete journeys, states, affordances, microcopy, and accessibility; product strategy covers activation, adoption, experiments, and metrics.

## Development Guidelines

### File Naming Conventions

- **Dart files**: `snake_case` (e.g., `tool_views.dart`, `main_shell.dart`, `tool_state.dart`)
- **Tests**: `*_test.dart` suffix (e.g., `widget_test.dart`)

### Code Naming Conventions

- **Classes/Widgets**: `PascalCase` (e.g., `ToolButton`, `EditorPane`, `MainShell`)
- **Functions/Methods**: `camelCase` (e.g., `buildJsonFormatter()`, `handleInputChange()`)
- **Variables**: `camelCase` (e.g., `selectedTool`, `inputController`, `isLoading`)
- **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `const MAX_RETRIES = 3`)
- **Private members**: Prefix with underscore (e.g., `_prefs`, `_inputController`)
- **State listeners**: Suffix with `Listener` or use callback pattern (e.g., `onInputChanged`)

### Import Organization

Follow this import order in all Dart files:

1. Dart libraries (`dart:*`)
2. Flutter libraries (`package:flutter/*`)
3. External packages (third-party pub.dev packages)
4. Local/relative imports

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dev_tool.dart';
import '../registry/tool_registry.dart';
import 'widgets.dart';
```

### Widget Architecture Pattern

Follow this pattern for tool implementations:

```dart
Widget buildToolName() {
  // Return a stateful or stateless widget
  // Use EditorPane for input/output layouts
  // Register actions (Run, Clear, Sample) in toolbar
}
```

Example structure:
```dart
Widget buildJsonFormatValidate() {
  return _JsonFormatValidateView();
}

class _JsonFormatValidateView extends StatefulWidget {
  const _JsonFormatValidateView();

  @override
  State<_JsonFormatValidateView> createState() => _JsonFormatValidateViewState();
}

class _JsonFormatValidateViewState extends State<_JsonFormatValidateView> {
  late TextEditingController _inputController;
  late TextEditingController _outputController;
  
  // ... implementation
}
```

### State Persistence

Use `shared_preferences` for simple key-value persistence:

```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('key', value);
final value = prefs.getString('key') ?? defaultValue;
```

For complex state, consider initializing in `ToolState.load()` and listening to changes via `ValueNotifier`.

### Error Handling

- Wrap async operations in try-catch blocks
- Display user-friendly error messages via ScaffoldMessenger snackbars
- Log errors using print() or a logging service for debugging
- Validate user input before processing

### Testing

- Write widget tests in `test/` directory with `*_test.dart` suffix
- Test tool logic independently from UI when possible
- Use `flutter test` to run all tests
- Aim for coverage of tool implementations and edge cases

## Available Commands

| Command | Description |
|---------|-------------|
| `flutter run -d macos` | Start development server on macOS |
| `flutter run -d macos --hot` | Run with hot reload enabled |
| `flutter test` | Run all widget tests |
| `flutter analyze` | Run static analysis (Dart linter) |
| `flutter build macos --release` | Build production release for macOS |
| `flutter clean` | Clean build artifacts |
| `flutter pub get` | Download and install dependencies |
| `flutter pub outdated` | Check for outdated packages |

## Environment & Configuration

### Flutter Analysis

The project uses Flutter's built-in linting with `flutter_lints` (v6.0+). Analysis is configured in `analysis_options.yaml` and includes:

- Flutter recommended lints
- Customizable lint rules (currently using defaults)
- Run analysis with: `flutter analyze`

### Key Configuration Files

| File | Purpose |
|------|---------|
| `pubspec.yaml` | Package manifest, dependencies, app metadata |
| `pubspec.lock` | Locked versions of all dependencies |
| `analysis_options.yaml` | Dart analyzer and linter configuration |
| `.metadata` | Flutter project metadata (platform versions, migration info) |
| `devtools_options.yaml` | DevTools configuration |

### Platform-Specific Notes

- **macOS target**: Native macOS app built with Flutter's desktop support
- **Other platforms**: Android, iOS, Linux, Windows folders exist but macOS is the primary target
- **No backend**: All utilities run locally; no network calls required (except optional integrations)
- **No subscriptions**: Free and fully functional without account/licensing

## Platform-Native Production Patterns

Before implementing production behavior, identify the runtime, hosting platform, database, queue, storage, auth, payment, analytics, and email systems involved. Inspect the provider service catalog, official docs, runtime config, and project docs before choosing a fallback implementation.

For changes touching abuse protection, rate limits, background work, scheduled jobs, queues, caching, shared state, secrets, file/object storage, database connectivity, webhooks, payments, auth/session flows, email sending, analytics events, or externally visible side effects:

1. Prefer managed/platform-native primitives over in-process memory, local timers, singleton clients, ad hoc counters, or frontend-only controls.
2. Wire platform capabilities through the repository's infrastructure/config layer, runtime environment, and typed app/context boundary.
3. Place guards before expensive or externally visible side effects such as payment APIs, auth mutations, email sends, analytics events, storage writes, or database mutations.
4. Preserve privacy and anti-enumeration behavior in auth, recovery, invite, checkout, and email flows.
5. Decide and document the failure stance: fail open, fail closed, retry, or degrade gracefully.
6. Check concurrency, retries, serverless/edge isolates, transaction boundaries, and multi-instance behavior before choosing a storage or coordination pattern.
7. Keep the change consistent with the repo's existing deployment/runtime setup rather than introducing a parallel mechanism.

Precedence: follow a clear user instruction first, then explicit project docs, then provider best practices. When a fallback is explicitly required, state the provider-native alternative and make the chosen path durable, multi-instance safe, and atomic under concurrency. Do not present module-scope mutable state, frontend-only checks, detached timers, untyped env access, or non-atomic select-then-update counters as production-ready.

For macOS desktop features and behaviors:

**File Access & Permissions**
- Use `path_provider` for accessing app directories and user documents
- Respect macOS sandbox restrictions; request permissions explicitly
- Store user preferences in Application Support directory

**Clipboard Integration**
- Use `flutter/services.dart` Clipboard API for copy/paste operations
- Example: `Clipboard.setData(ClipboardData(text: outputText))`

**Keyboard Shortcuts**
- Implement global shortcuts using `SingleActivator` or `CallbackShortcuts` widgets
- Common shortcuts: ⌘F (search), ⌘↩ (run), ⌘⇧C (copy output)
- Bind to actions at the MainShell level for app-wide availability

**Window Management**
- Flutter macOS automatically handles window resizing and layout responsiveness
- Use `MediaQuery` to build responsive layouts that adapt to window size changes
- Persist window size/position preferences to `shared_preferences` if needed

**Performance Considerations**
- Use `ScrollView` with `maxLines: null` for large text in editors
- Debounce input change listeners to avoid excessive rebuilds
- Consider `buildTree` optimization for deeply nested widgets
- Profile with Flutter DevTools: `flutter pub global activate devtools`

## Dependencies

### Key External Dependencies

- **crypto** (3.0+): Standard cryptographic operations (SHA, MD5, HMAC)
- **pointycastle** (3.7+): Advanced encryption algorithms (AES, DES, RSA, EC)
- **http** (1.2+): HTTP client for network requests
- **shared_preferences** (2.3+): Persistent local key-value storage
- **path_provider** (2.1+): Access to app/user directories
- **yaml** (3.1+): YAML parsing for config files
- **path** (1.9+): Cross-platform path manipulation

### Development Dependencies

- **flutter_test**: Flutter testing framework
- **flutter_lints** (6.0+): Recommended linting rules for Flutter apps

## Testing Strategy

- **Widget tests**: Test UI components in isolation (`test/widget_test.dart`)
- **Integration tests**: Test tool workflows end-to-end (as needed)
- **Unit tests**: Test pure functions and business logic
- Run tests with: `flutter test`
- Coverage is not currently tracked; consider adding with `coverage` package if needed

## Deployment

### Building for Production

```bash
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/dev_tool.app`

### Code Signing & Notarization

For distribution:
1. Code sign with valid Apple Developer certificate
2. Notarize with Apple for Gatekeeper compliance
3. Create DMG installer or direct distribution

### Distribution

- Direct distribution as `.app` bundle
- Distribute via GitHub Releases, website, or Mac App Store

## Code Quality

### Linting & Analysis

Run regularly:
```bash
flutter analyze
```

Fix issues automatically where possible:
```bash
dart fix --apply
```

### Best Practices

- Keep widgets focused and single-responsibility
- Extract complex logic into separate functions/classes
- Use const constructors where possible for performance
- Comment non-obvious logic or workarounds only
- Name variables descriptively to reduce need for comments
- Test edge cases and error conditions

## Additional Resources

- **Flutter Docs**: https://flutter.dev/docs
- **Dart Docs**: https://dart.dev/guides
- **Material Design 3**: https://m3.material.io/
- **Flutter Desktop**: https://flutter.dev/multi-platform/desktop
- **Project Screenshots**: `screenshots/` directory (UI specification source of truth)


## Skill Usage Guide

When working on tasks involving these technologies, invoke the corresponding skill:

| Skill | Invoke When |
|-------|-------------|
| dart | Primary programming language for Flutter desktop development with strong typing |
| flutter | Cross-platform desktop UI framework with Material Design 3 components |
| shared-preferences | Local key-value storage for app settings and user preferences persistence |
| pointycastle | Advanced cryptographic operations including AES, RSA, and EC algorithms |
| frontend-design | Material Design 3 theming, widget styling, and Flutter UI component patterns |
| ux | Interactive navigation flows, editor UI states, tool search, and accessibility |
| path-provider | File system access and app directory management for macOS desktop |
| crypto | Standard cryptographic operations including SHA, MD5, and HMAC hashing |
| yaml | YAML parsing and configuration file handling in Dart |
| http | HTTP client for network requests and external API integration |

## Prompt-Aware Production Contract

Before coding, scan the user's prompt for relevant skills and production-risk signals.

- Load or inspect the relevant skill when the task matches a skill name, its Use when description, or nearby technology terms.
- Use skills as a quality multiplier, not a checklist. Inspect nearby repo patterns, infer the task's highest-leverage success criteria, and produce the complete slice that would win a review against an unskilled baseline.
- Reuse existing product primitives before reimplementing: components, hooks, helpers, data registries, metadata builders, analytics, pricing, checkout, auth, and routing utilities.
- Use semantic, accessible structures for core content and controls, and centralize repeated facts/copy/defaults in shared helpers when multiple surfaces need the same answer.
- When two approaches each have strengths, synthesize the best repo-consistent parts instead of blindly picking one.
- Ground product copy and documentation claims in implemented behavior; do not imply automation, integrations, refresh behavior, security, metrics, counts, cadences, or data flow that does not exist in code.
- Skill usage must not suppress clarifying questions. If the task is ambiguous, underspecified, or depends on user preference that cannot be inferred from the repo, ask the smallest useful set of questions before coding.
- If a reasonable assumption is safe, state it briefly and proceed; if the assumption could change architecture, user-visible behavior, data shape, security posture, or external side effects, ask first.
- Production-risk signals include: abuse/rate-limit guard, background/lifecycle work, scheduled/recurring work, cache/shared state, secrets/env wiring, database/concurrency, webhook/side-effect flow, email/external side effect, API/auth flow.
- For those signals, create a short task contract before coding: likely skills, provider docs to inspect, preferred native service, wiring surfaces, side-effect barriers, fallback policy, and verification criteria.
- Infer provider/runtime from repository evidence even when the user does not name it. If a repo uses Cloudflare Workers via Alchemy, an abuse/rate-limit prompt should consider Cloudflare runtime capabilities before a DB counter.
- Inspect provider service catalogs, best-practice docs, and runtime/database/config surfaces before choosing code.
- If the user's prompt clearly asks for a different mechanism, follow the user and mention the provider-recommended alternative plus the tradeoff.
- If project docs clearly mandate a different mechanism, follow project docs and preserve their constraints.
- Otherwise prefer the platform-recommended/native primitive before in-memory, frontend-only, detached async, or ad hoc counter solutions.
- Place guards before external side effects and document failure behavior.
- If a fallback is used, make it durable, multi-instance safe, and atomic under concurrency; non-atomic select-then-update counters are not production-safe.

## UI/UX Quality Contract

For frontend, mobile, desktop, CLI, form, dashboard, onboarding, account/settings, or visual polish tasks:

- UI/UX signals include: UI/interface change, form/flow UX, state coverage, accessibility/interaction quality, responsive layout, conversion/onboarding flow.
- Load or inspect frontend-design for visual/interface craft and ux for journeys, state coverage, microcopy, and interaction quality when those skills exist.
- Inspect nearby screens/components, the component library, design tokens, and current density before creating a new visual direction.
- Reuse existing components and hooks for repeated UI jobs such as tables, FAQs/accordions, forms, sticky CTAs, pricing, checkout, navigation, and analytics-triggered controls.
- Choose a surface-appropriate direction: dashboard/tooling should be quiet, dense, and scannable; marketing can be more memorable; CLI/Ink should prioritize stable layout, truncation, and keyboard clarity.
- Avoid generic AI slop, template-looking screens, random gradient/card stacks, and UI that ignores the product context.
- For changed interactive flows, define the state matrix before coding: loading, empty, error, disabled, pending, success, retry/recovery, and long-text cases.
- Verify accessibility basics: labels, focus states, keyboard path, semantic controls, contrast, ARIA state for disclosure widgets, and non-hover-only guidance.
- The final hook check is advisory and may warn about missing UI states, responsive constraints, or accessibility cues without blocking completion.






