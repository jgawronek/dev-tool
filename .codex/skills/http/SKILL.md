---
name: http
description: |
  HTTP client for network requests and external API integration in the DevUtils Flutter app.
  Use when: making HTTP requests to external APIs, downloading files with progress tracking,
  consuming streaming responses (SSE), polling local server health endpoints, or calling
  REST endpoints from Dart/Flutter service code in lib/services/.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# Http

Dart `package:http` used in DevUtils for two distinct purposes: downloading model files
with progress streaming (`LocalLLMService.downloadModel`) and calling a local llama-server
over `http://127.0.0.1` for LLM inference (`LocalLLMService.generateChat`). All HTTP
usage lives in `lib/services/local_llm_service.dart`.

## Before You Code (REQUIRED)

This skill's content was captured at generation time and MAY be stale. For ANY non-trivial change involving http, verify against current docs FIRST:



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

### Existing: Simple GET (health poll)

```dart
// lib/services/local_llm_service.dart:115
final response = await http.get(Uri.parse('http://127.0.0.1:$_port/health'));
if (response.statusCode == 200) return;
```

### Existing: Streaming POST (SSE inference)

```dart
// lib/services/local_llm_service.dart:139
final request = http.Request('POST', Uri.parse('http://127.0.0.1:$_port/v1/chat/completions'));
request.headers['Content-Type'] = 'application/json';
request.body = jsonEncode({'messages': messages, 'stream': true});

final client = http.Client();
try {
  final response = await client.send(request);
  await for (final chunk in response.stream.transform(utf8.decoder)) {
    // parse SSE `data:` lines
  }
} finally {
  client.close(); // ALWAYS in finally — never skip
}
```

### Existing: File Download with Progress

```dart
// lib/services/local_llm_service.dart:63
final request = http.Request('GET', Uri.parse(preset.url));
final client = http.Client();
final response = await client.send(request);
final totalBytes = response.contentLength ?? 0;
var receivedBytes = 0;

final file = File(outputPath).openWrite();
await for (final chunk in response.stream) {
  file.add(chunk);
  receivedBytes += chunk.length;
  onProgress(totalBytes == 0 ? 0.0 : receivedBytes / totalBytes);
}
await file.close();
client.close();
```

## Key Concepts

| Pattern | Use | When |
|---------|-----|------|
| `http.get(uri)` | One-shot GET, auto-closed | Health checks, small JSON |
| `http.Client().send(request)` | Streaming or reusable connection | File downloads, SSE |
| `response.stream.transform(utf8.decoder)` | Decode streamed bytes to String | SSE line parsing |
| `client.close()` in `finally` | Prevent socket leaks | Every explicit `Client()` |
| `response.contentLength ?? 0` | Guard null length | Progress calculation |

## See Also

- [patterns](references/patterns.md)
- [workflows](references/workflows.md)

## Related Skills

- See the **dart** skill for language patterns, import conventions, and async/await
- See the **flutter** skill for integrating async streams into widget `setState`
- See the **yaml** skill for structured API response parsing