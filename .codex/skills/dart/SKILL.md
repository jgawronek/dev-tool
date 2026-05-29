---
name: dart
description: |
  Primary programming language for Flutter desktop development with strong typing.
  Use when: writing or modifying any .dart file, adding new tools to the registry,
  working with ValueNotifier state, implementing new tool views, or fixing Dart
  type/analysis errors in the DevUtils macOS app.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# Dart

Dart 3.10+ with Flutter 3.24+ for the DevUtils native macOS desktop app. Strong
null safety, sound typing, and `ValueNotifier`-based reactive state without external
state management packages.

## Before You Code (REQUIRED)

This skill's content was captured at generation time and MAY be stale. For ANY non-trivial change involving dart, verify against current docs FIRST:



Then:

1. **Match the installed version.** Cross-reference against the version installed in this repo. APIs change across minor versions; do not assume.
2. **Discover provider best practices.** If the task touches a production-sensitive capability, inspect the provider service catalog, official docs, and project docs before choosing an implementation.
3. **Respect explicit direction.** If the user explicitly asks for a specific mechanism, follow it. If project docs clearly mandate a mechanism, follow the project. In both cases, mention the provider-recommended alternative and make the chosen path safe.
4. **Prefer provider-native primitives by default.** If no explicit user/project override exists and the change involves caching, rate limiting, background work, scheduled jobs, shared state, queues, or secrets, use the provider-recommended binding/API. Do not hand-roll an in-memory or polyfill solution that "works" locally but breaks under the provider's execution model — derive the need→native-primitive mapping yourself from this provider's docs.

## Skill Advantage Protocol

Using this skill should produce a meaningfully better result than an unskilled baseline. Apply this loop before and during implementation:

1. **Clarify only when it changes the outcome.** Ask the smallest useful set of questions when the request is ambiguous, preference-heavy, or could change architecture, user-visible behavior, data shape, security posture, analytics, or external side effects. If the safe assumption is obvious, state it and proceed.
2. **Inspect the nearest real patterns.** Read adjacent files, routes, components, tests, schema, infra, copy, and analytics surfaces before inventing structure. Treat local conventions as the starting point.
3. **Optimize the task's highest-leverage axis.** Identify what would make the result win a review: user-visible correctness, integration quality, accessibility, security, reliability, maintainability, operability, or speed of future change.
4. **Reuse before reimplementing.** Prefer existing components, hooks, helpers, data registries, metadata builders, analytics, pricing, checkout, auth, and routing utilities over local one-off clones.
5. **Use semantic structures.** Tables, lists, forms, buttons, links, headings, and disclosure controls should use native/project accessible primitives instead of div-only lookalikes.
6. **Prevent drift by construction.** Centralize repeated facts, labels, claims, product defaults, and shared table cells in registries or helpers when multiple surfaces need the same answer.
7. **Synthesize, do not merely comply.** Combine this skill's guidance with repo evidence and the user's goal. When two good approaches exist, borrow the strongest parts of each instead of blindly choosing one.
8. **Check claims against code.** Product copy, docs, and comments must not imply automation, integrations, performance, security, refresh cadence, counts, or data flow that the implementation does not actually provide.
9. **Ship the complete slice.** Include every adjacent artifact needed for the change to be usable and maintainable: wiring, state handling, validation, analytics, tests, docs, migrations, or infra when those surfaces are part of the behavior.

## Capability Contract

Use this section when the user prompt touches production risk, even if the prompt does not name this technology explicitly.




Required wiring surfaces:
- provider/runtime configuration discovered during implementation
- nearest typed request/context boundary
- handler/procedure boundary before external side effects

Side-effect barrier:
- Place guards before external APIs, auth mutations, email sends, analytics events, storage writes, and database mutations.


Fallback policy:
- Prefer provider-native/platform-managed primitives by default when no explicit override exists.
- Follow clear user/project overrides, but mention the native alternative and tradeoff.
- Fallbacks must be durable, multi-instance safe, and atomic under concurrency.

Verification rules:
- [error] native-or-explicit-override: Use the provider-native primitive first unless the user/project explicitly overrides it.
- [error] atomic-fallback: Fallback counters must be atomic under concurrency.

## Quick Start

### Existing: Add a New Tool

```dart
// lib/registry/tool_registry.dart — existing pattern
DevTool(
  id: 'my-tool',
  name: 'My Tool',
  icon: Icons.build,
  category: 'Converters',
  builder: (_) => buildMyTool(),   // builder function in tool_views.dart
),
```

### New: Tool View Builder

```dart
// lib/ui/tool_views.dart — new code to add
Widget buildMyTool() {
  final inputCtrl = TextEditingController();
  final outputCtrl = TextEditingController();
  return buildSplitEditors(
    inputCtrl: inputCtrl,
    outputCtrl: outputCtrl,
    actions: [
      ToolButton(label: 'Run', onPressed: () {
        outputCtrl.text = _transform(inputCtrl.text);
      }),
      ToolButton(label: 'Clear', onPressed: () {
        inputCtrl.clear(); outputCtrl.clear();
      }),
    ],
  );
}
```

## Key Concepts

| Concept | Pattern | Location |
|---------|---------|---------|
| Reactive state | `ValueNotifier<T>` + `ValueListenableBuilder` | `lib/state/tool_state.dart` |
| Tool registration | `DevTool` + `ToolRegistry.tools` | `lib/registry/tool_registry.dart` |
| Persistence | `SharedPreferences` via `ToolState.load()` | `lib/state/tool_state.dart` |
| Reusable layout | `buildSplitEditors()` | `lib/ui/tool_views.dart` |
| Custom buttons | `ToolButton(label: ..., onPressed: ...)` | `lib/ui/widgets.dart` |
| Theme tokens | `AppColors` `ThemeExtension` | `lib/app.dart` |

## Import Order

```dart
import 'dart:async';        // 1. dart: libraries
import 'dart:convert';

import 'package:flutter/material.dart';     // 2. flutter: packages
import 'package:shared_preferences/...';   // 3. third-party pub.dev

import '../models/dev_tool.dart';           // 4. local/relative
import 'widgets.dart';
```

## See Also

- [patterns](references/patterns.md)
- [workflows](references/workflows.md)

## Related Skills

- See the **flutter** skill for widget composition and layout patterns
- See the **shared-preferences** skill for persistence patterns
- See the **pointycastle** skill for cryptographic operations
- See the **frontend-design** skill for Material Design 3 theming