import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dev_tool/services/local_llm_service.dart';

const preset = ModelPreset(
  name: 'fixture',
  filename: 'fixture.gguf',
  url: 'https://fixture.invalid/model',
  sizeBytes: 8,
  description: 'fixture',
);
void main() {
  test(
    'model download rejects HTTP errors, preserves existing files, cleans temporary files and recovers',
    () async {
      final dir = Directory.systemTemp.createTempSync('model-audit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final previous = File('${dir.path}/fixture.gguf')
        ..writeAsStringSync('GGUFprevious');
      var status = 404;
      var body = 'not a model';
      final service = LocalLLMService(
        modelDirectory: dir,
        clientFactory: () =>
            MockClient((_) async => http.Response(body, status)),
      );
      await expectLater(
        service.downloadModel(preset, (_) {}),
        throwsA(isA<HttpException>()),
      );
      expect(previous.readAsStringSync(), 'GGUFprevious');
      status = 200;
      await expectLater(
        service.downloadModel(preset, (_) {}),
        throwsA(isA<FormatException>()),
      );
      expect(previous.readAsStringSync(), 'GGUFprevious');
      expect(dir.listSync(), hasLength(1));
      body = 'GGUFdata';
      final progress = <double>[];
      await service.downloadModel(preset, progress.add);
      expect(previous.readAsStringSync(), 'GGUFdata');
      expect(progress.last, 1);
      expect((await service.getAvailableModels()).single.size, 8);
      await service.deleteModel(previous.path);
      expect(await service.getAvailableModels(), isEmpty);
    },
  );
  test(
    'interrupted download cleans partial bytes and preserves previous model',
    () async {
      final dir = Directory.systemTemp.createTempSync('model-interrupt-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final previous = File('${dir.path}/fixture.gguf')
        ..writeAsStringSync('GGUFprevious');
      final service = LocalLLMService(
        modelDirectory: dir,
        clientFactory: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream<List<int>>.fromIterable([ascii.encode('GGUF')]),
            200,
            contentLength: 8,
          ),
        ),
      );
      await expectLater(
        service.downloadModel(preset, (_) {}),
        throwsA(isA<FormatException>()),
      );
      expect(previous.readAsStringSync(), 'GGUFprevious');
      expect(dir.listSync(), hasLength(1));
    },
  );
  test(
    'SSE tokens survive every byte boundary, Unicode, CRLF, malformed lines and finish',
    () async {
      final payload =
          ': comment\r\ndata: malformed\n'
          'data: {"choices":[{"delta":{"content":"é漢🙂"},"finish_reason":null}]}\r\n'
          'data: {"choices":[{"delta":{"content":" done"},"finish_reason":"stop"}]}\n'
          'data: {"choices":[{"delta":{"content":"ignored"}}]}\n';
      final bytes = utf8.encode(payload);
      for (var split = 1; split < bytes.length; split++) {
        final result = await LocalLLMService.decodeChatEvents(
          Stream.fromIterable([bytes.sublist(0, split), bytes.sublist(split)]),
        ).join();
        expect(result, 'é漢🙂 done', reason: 'boundary $split');
      }
      expect(
        await LocalLLMService.decodeChatEvents(
          Stream.fromIterable(bytes.map((b) => [b])),
        ).join(),
        'é漢🙂 done',
      );
      expect(
        await LocalLLMService.decodeChatEvents(
          Stream.value(
            utf8.encode(
              'data: [DONE]\ndata: {"choices":[{"delta":{"content":"ignored"}}]}\n',
            ),
          ),
        ).join(),
        isEmpty,
      );
    },
  );
}
