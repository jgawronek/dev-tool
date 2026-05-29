# Http Patterns Reference

## Contents
- Client lifecycle
- Streaming responses (SSE)
- Progress tracking
- Error handling
- Anti-patterns

---

## Client Lifecycle

Always use `http.Client()` when streaming. The top-level helpers (`http.get`, `http.post`)
create and close a client internally — they buffer the full response body and cannot stream.

```dart
// GOOD — explicit client for streaming
final client = http.Client();
try {
  final response = await client.send(request);
  await for (final chunk in response.stream) { ... }
} finally {
  client.close();
}

// GOOD — top-level helper for non-streaming, small responses
final response = await http.get(Uri.parse(url));
```

---

## Streaming SSE Responses

The llama-server returns `text/event-stream`. Each line is either `data: {json}` or
`data: [DONE]`. Parse defensively — network chunking can split a logical SSE line across
multiple `await for` iterations.

```dart
// lib/services/local_llm_service.dart:155 — existing pattern
await for (final chunk in response.stream.transform(utf8.decoder)) {
  for (final line in chunk.split('\n')) {
    if (line.startsWith('data: ') && line.trim() != 'data: [DONE]') {
      try {
        final json = jsonDecode(line.substring(6));
        final content = (json['choices'] as List?)
            ?.firstOrNull?['delta']?['content'] as String?;
        if (content != null) yield content;
      } catch (_) {
        // skip malformed lines — chunking can deliver partial JSON
      }
    }
  }
}
```

### WARNING: Assuming Chunk == Line

**The Problem:**

```dart
// BAD — one chunk is not guaranteed to be one SSE event
await for (final chunk in response.stream.transform(utf8.decoder)) {
  final json = jsonDecode(chunk); // crashes on partial JSON
}
```

**Why This Breaks:**
1. TCP delivers data in arbitrary byte boundaries, not logical SSE lines.
2. `jsonDecode` throws `FormatException` on partial JSON, silently terminating the stream.
3. The llama-server sends `data: [DONE]` as a plain string — `jsonDecode` crashes on it.

**The Fix:** Always `split('\n')` inside the loop and guard with `startsWith('data: ')`.

---

## Progress Tracking for Downloads

`response.contentLength` is `null` when the server omits `Content-Length` (chunked
transfer). Guard with `?? 0` and treat `0` as indeterminate progress.

```dart
// lib/services/local_llm_service.dart:67 — existing pattern
final totalBytes = response.contentLength ?? 0;
var receivedBytes = 0;

await for (final chunk in response.stream) {
  file.add(chunk);
  receivedBytes += chunk.length;
  final ratio = totalBytes == 0 ? 0.0 : receivedBytes / totalBytes;
  onProgress(ratio.toDouble());
}
```

Pass `onProgress` as a `Function(double)` callback rather than a `ValueNotifier` so the
service layer stays decoupled from Flutter's widget tree. See the **flutter** skill for
wiring this callback into a `StatefulWidget`.

---

## Error Handling

`http.get` and `client.send` throw on network failure (no connection, DNS failure, timeout)
but return normally for HTTP error status codes. Check `response.statusCode` explicitly.

```dart
// new code to add — wrap calls in service methods
Future<void> _checkHealth() async {
  try {
    final response = await http.get(Uri.parse('http://127.0.0.1:$_port/health'))
        .timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) {
      throw Exception('Unhealthy: ${response.statusCode}');
    }
  } on SocketException {
    throw Exception('Server not reachable');
  } on TimeoutException {
    throw Exception('Health check timed out');
  }
}
```

### WARNING: Catching `_` Silently on Network Errors

**The Problem:**

```dart
// BAD — from _waitForServer, acceptable there but not in user-facing paths
try {
  final response = await http.get(Uri.parse(url));
} catch (_) {} // swallows all errors including programming mistakes
```

**Why This Breaks:**
1. `TypeError`, `StateError`, and other programming errors become invisible.
2. Retry loops silently spin on coding bugs, not just transient network failures.
3. Users see a frozen UI with no diagnosis path.

**The Fix:** Catch `SocketException`, `TimeoutException`, and `HttpException` specifically.
Use bare `catch (_)` only in tight retry loops where the failure mode is well-understood
(e.g., `_waitForServer` polling for a process that hasn't bound its port yet).

---

## Anti-Patterns

### WARNING: Re-using a Closed Client

```dart
// BAD
final client = http.Client();
await client.send(request1);
client.close();
await client.send(request2); // throws StateError: HTTP client is closed
```

Create a new `http.Client()` per logical operation, or maintain a long-lived client with
explicit lifecycle tied to the service (e.g., dispose in `stopServer`).

### WARNING: Blocking the Dart Isolate with Large Responses

`http.get` buffers the full body in memory before returning. For multi-GB model files,
this exhausts RAM. Always use `client.send(request)` + `response.stream` for large
payloads.