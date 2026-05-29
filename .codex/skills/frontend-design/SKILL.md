---
name: frontend-design
description: |
  Material Design 3 theming, widget styling, and Flutter UI component patterns.
  Use when: implementing or refactoring Frontend Design work, troubleshooting aesthetics, components, layouts, or aligning new changes with the repository's existing conventions
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# Frontend Design Skill

This fallback skill keeps Frontend Design work aligned with the conventions already present in this repository. Prefer extending the closest existing implementation over inventing a new abstraction, and verify neighboring states before finishing.

## Before You Code (REQUIRED)

This skill's content was captured at generation time and MAY be stale. For ANY non-trivial change involving frontend-design, verify against current docs FIRST:



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

## Design Direction

Pick a clear visual direction from the product context before writing styles. The direction must fit the target surface (unknown) and the repo's actual UI vocabulary, not a generic AI-looking template. A SaaS dashboard should usually feel dense, quiet, and fast to scan; a marketing page can be more memorable; an Ink/CLI view should prioritize stable layout, truncation, and keyboard clarity.

## Interface Quality Bar

- Make the interface feel intentionally designed for this repo, not assembled from interchangeable cards and gradients.
- Use distinctive choices only when they serve the surface; restraint is a design choice when the product is operational or data-heavy.
- Avoid AI slop: random purple/blue gradients, unrelated glass panels, oversized hero typography inside tools, fake depth, decorative noise with no product meaning, and one-note color palettes.
- Keep text, icons, states, and layout aligned with the user's actual workflow.

## Component System Fit

- Styling system: the styling system discovered in this repo.
- Component primitives/libraries: the existing component primitives.
- Real UI surfaces to inspect first: the nearest real screen, component, or interactive surface.
- Reuse local tokens, spacing, border radii, density, icons, and interaction patterns before creating new primitives.

## Responsive + State Coverage

- Cover loading, empty, error, disabled, pending, success, and recovery.
- Keep layouts stable for long labels, long data values, narrow mobile widths, and wide desktop.
- For interactive elements, verify labels, focus states, keyboard flow, semantics, and contrast.

## Visual Anti-Patterns

- Do not copy a generic design-skill template or repeat the same aesthetic across projects.
- Do not introduce a new brand palette, font stack, shadow system, animation language, or card style unless it matches repo evidence or the user explicitly asks.
- Do not make dashboards look like landing pages, or landing pages look like admin tables.

## Verification Checklist

- Nearby components/screens were inspected.
- Visual direction matches the target surface and product context.
- Responsive behavior, overflow, empty/loading/error/disabled states, and accessibility basics were checked.
- Any generated example uses real repo files/symbols from the evidence pack or is labeled as new code to add.

## Quick Start

### Inspect the current implementation

```sh
rg -n "frontend-design|aesthetics|components|layouts" .
rg --files | rg "frontend-design|aesthetics|components"
```

### Make the smallest compatible change

- Reuse the current design tokens, spacing rhythm, and component primitives before inventing new ones.
- Keep visual changes consistent across loading, empty, hover, focus, and mobile states.
- Favor intentional, legible UI over trend-driven styling flourishes.

### Verify before finishing

- Check responsive behavior and the primary interactive states affected by the change.
- Verify empty, loading, error, and disabled states if the surface exposes them.
- Confirm accessibility basics still hold: labels, focus states, semantics, and contrast.

## Key Concepts

| Concept | Why it matters | What to check |
|---------|----------------|---------------|
| Existing patterns | Keeps the repo coherent | Start from the nearest matching implementation before editing |
| Scope control | Prevents abstraction creep | Keep the change in the same layer as surrounding code |
| Verification | Catches regressions early | Recheck adjacent states, edge cases, and integration points |
| References | Speeds up repeat work | Use the linked topic files when the task needs deeper guidance |

## Common Patterns

### Aesthetics

**When:** The task touches aesthetics in Frontend Design work.

- Inspect the nearest existing implementation before introducing a new pattern.
- Reuse naming, file placement, and helper utilities that are already established in this repo.
- Keep the change easy to review and easy to extend without widening scope unnecessarily.

### Components

**When:** The task touches components in Frontend Design work.

- Inspect the nearest existing implementation before introducing a new pattern.
- Reuse naming, file placement, and helper utilities that are already established in this repo.
- Keep the change easy to review and easy to extend without widening scope unnecessarily.

### Layouts

**When:** The task touches layouts in Frontend Design work.

- Inspect the nearest existing implementation before introducing a new pattern.
- Reuse naming, file placement, and helper utilities that are already established in this repo.
- Keep the change easy to review and easy to extend without widening scope unnecessarily.

## See Also

- [Aesthetics](references/aesthetics.md)
- [Components](references/components.md)
- [Layouts](references/layouts.md)
- [Motion](references/motion.md)
- [Patterns](references/patterns.md)