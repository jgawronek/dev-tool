---
name: ux
description: |
  Guides concrete interaction quality for DevUtils Flutter desktop app: tool navigation, editor UI
  states, sidebar search, favorites flow, and accessibility.
  Use when: editing sidebar.dart, tool_views.dart, widgets.dart, main_shell.dart, or any interactive
  flow in lib/ui/; adding new tool states (loading, error, empty, disabled); improving keyboard
  navigation; writing microcopy for tool labels, tooltips, or error messages.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# UX Skill — DevUtils

DevUtils is a dense, keyboard-driven developer tool. Every interaction decision should optimize for **speed and clarity**, not marketing aesthetics. The sidebar is always visible; tools are stateless panels; state lives in `ToolState` via `ValueNotifier`.

## Before You Code (REQUIRED)

This skill's content was captured at generation time and MAY be stale. For ANY non-trivial change involving ux, verify against current docs FIRST:



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

## Journey Map

Map the path the user is trying to complete before touching UI code: entry point, decision point, action, server response, confirmation, and recovery. For this repo, inspect forms, dialogs, settings, dashboards, onboarding, checkout, or CLI flows touched by the task.

## User Intent

- Name the user's immediate job and the anxiety/risk around it.
- Preserve the surrounding flow's existing mental model, navigation, and terminology.
- Avoid premature success copy; say what happened, what is pending, and what the user can do next.

## State Matrix

Cover loading, empty, error, disabled, pending, success, and recovery. A flow is incomplete if it only implements the happy path or relies on backend errors surfacing as raw messages.

## Failure + Recovery

- Explain failures in user-safe language.
- Keep privacy and anti-enumeration behavior for auth, account, invite, checkout, and recovery flows.
- Provide a retry, resend, return, or contact-support path when the user can reasonably recover.

## Accessibility Contract

Verify labels, focus states, keyboard flow, semantics, and contrast. Prefer native controls and existing accessible primitives before custom interaction code.

## Microcopy Rules

- Match local product voice and nearby copy.
- Keep labels explicit, errors actionable, and pending states honest.
- Do not use vague copy such as "Something went wrong" when a safe, specific recovery instruction is possible.

## Acceptance Checklist

- The primary journey and all meaningful states are represented.
- Validation, disabled states, loading states, success/failure feedback, and recovery copy are present where relevant.
- The UI remains understandable on mobile/desktop or the target CLI/desktop/mobile surface.
- The implementation uses local component and accessibility patterns.

## Quick Start

### Verified Existing Pattern — Tool Selection

```dart
// lib/ui/main_shell.dart — selection driven by ValueNotifier
onSelect: (id) => state.selectedToolId.value = id,
```

### Verified Existing Pattern — Search with Clear

```dart
// lib/ui/sidebar.dart:71-79
suffixIcon: widget.searchQuery.isEmpty
    ? null
    : IconButton(
        icon: const Icon(Icons.clear, size: 16),
        onPressed: () {
          _searchController.clear();
          widget.onSearch('');
        },
      ),
```

### New Code Pattern — Rich Empty Search State

```dart
// new code to add — replace line 73 in main_shell.dart
child: selectedTool == null
    ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 32, color: Color(0xFFAAAAAA)),
            const SizedBox(height: 8),
            Text('No tools match "$query"',
                style: const TextStyle(color: Color(0xFF888888))),
          ],
        ),
      )
    : selectedTool.builder(context),
```

## Key Concepts

| Concept | Usage | Example |
|---------|-------|---------|
| `ValueNotifier<T>` | Reactive state without rebuild overhead | `state.selectedToolId.value = id` |
| `EditorPane` | Canonical input/output layout for tools | `EditorPane(label: 'Input', actions: [...])` |
| `ToolButton` | Action buttons in tool toolbars | `ToolButton(label: 'Go', onPressed: ...)` |
| `SectionHeader` | Sidebar category labels | `SectionHeader(title: 'Encoding')` |
| `LabeledField` | Key-value form rows | `LabeledField(label: 'Algorithm', ...)` |
| `SmallDropdown` | Compact option selector | `SmallDropdown(items: [...], initialValue: ...)` |

## Common Patterns

### Keyboard Interaction in EditorPane

`EditorPane` handles Enter-to-submit at `lib/ui/widgets.dart:351-365`. Wire `onSubmit`:

```dart
EditorPane(
  label: 'Input',
  onSubmit: _runTool,   // Enter submits, Shift+Enter inserts newline
  actions: [ToolButton(label: 'Go', onPressed: _runTool)],
)
```

## See Also

- [journey-map](references/journey-map.md)
- [state-matrix](references/state-matrix.md)
- [forms](references/forms.md)
- [accessibility](references/accessibility.md)
- [microcopy](references/microcopy.md)

## Related Skills

- See the **flutter** skill for widget lifecycle and `ValueNotifier`
- See the **frontend-design** skill for Material 3 color tokens and density
- See the **shared-preferences** skill for persistence wiring in `ToolState`