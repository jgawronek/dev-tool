# Http Workflows Reference

## Contents
- Adding a new external API call
- Integrating streaming into a Flutter widget
- Server health polling loop
- Testing HTTP service methods

---

## Adding a New External API Call

Copy this checklist and track progress:

- [ ] Step 1: Add method to `LocalLLMService` (or new service class in `lib/services/`)
- [ ] Step 2: Use `http.Client()` for streaming/large bodies; `http.get` for small JSON
- [ ] Step 3: Catch `SocketException` and `TimeoutException` specifically
- [ ] Step 4: Close the client in a `finally` block
- [ ] Step 5: Register any new `ModelPreset` constants in `kModelPresets`
- [ ] Step 6: Wire the service call into the appropriate tool view in `lib/ui/tool_views.dart`

```dart
// new code to add — template for a new GET-JSON method
Future<Map<String, dynamic>> fetchRemoteConfig(String url) async {
  final response = await http.get(Uri.parse(url))
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw Exception('Request failed: ${response.statusCode}');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}
```

---

## Integrating Streaming into a Flutter Widget

The `generateChat` method returns `Stream<String>`. Consume it in a `StatefulWidget`
to drive incremental UI updates. See the **flutter** skill for general `setState` patterns.

```dart
// new code to add — widget consuming a streaming service method
class _LLMOutputState extends State<LLMOutput> {
  final _buffer = StringBuffer();
  StreamSubscription<String>? _sub;

  void _start(LocalLLMService svc, List<Map<String, String>> messages) {
    _sub = svc.generateChat(messages).listen(
      (token) => setState(() => _buffer.write(token)),
      onError: (e) => setState(() => _buffer.write('\n[Error: $e]')),
      onDone: () => _sub = null,
    );
  }

  @override
  void dispose() {
    _sub?.cancel(); // prevent setState after unmount
    super.dispose();
  }
}
```

### Iterate-Until-Pass: Stream Integration Validation

1. Implement `listen` with `onError` and `onDone` handlers
2. Run: `flutter analyze`
3. If analysis fails, fix type errors and repeat step 2
4. Hot-reload and confirm tokens appear incrementally in the widget
5. Navigate away mid-stream — confirm no "setState after dispose" errors in console

---

## Server Health Polling Loop

`_waitForServer` in `LocalLLMService` polls up to 30 times with 500 ms gaps. Extend
this pattern when adding health checks for new local processes.

```dart
// lib/services/local_llm_service.dart:112 — existing pattern
Future<void> _waitForServer() async {
  for (var i = 0; i < 30; i++) {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:$_port/health'));
      if (response.statusCode == 200) return;
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
  }
  throw Exception('Server failed to start');
}
```

**DO:** Use a finite retry count. Infinite loops block the calling isolate.  
**DON'T:** Await inside a `Timer.periodic` — it creates unbounded overlapping requests.

---

## Testing HTTP Service Methods

`package:http` ships `package:http/testing.dart` with `MockClient`. Use it to unit-test
service methods without a live server.

```dart
// new code to add — test/local_llm_service_test.dart
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

test('fetchRemoteConfig parses JSON response', () async {
  final client = MockClient((request) async {
    return http.Response('{"version": "1.0"}', 200);
  });
  // inject client into service under test
});
```

**WARNING: No Mock Client in Existing Tests**  
The current test suite (`test/widget_test.dart`) does not mock HTTP. Service methods that
call live endpoints will fail in CI. Inject `http.Client` as a constructor parameter on
`LocalLLMService` to enable testing:

```dart
// new code to add — make client injectable
class LocalLLMService {
  final http.Client _client;
  LocalLLMService({http.Client? client}) : _client = client ?? http.Client();
}
```

Validate with:
```
flutter test
```
Repeat after each change until all tests pass.