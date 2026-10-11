import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:dev_tool/services/local_llm_service.dart';
import 'package:dev_tool/ui/app_colors.dart';
import 'package:dev_tool/ui/tools/ai/offline_llm.dart';

// Controlled delivery latency makes the cancel state observable even on a fast GPU.
class _ChatDelayClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (request.url.path != '/v1/chat/completions') return response;
    var first = true;
    return http.StreamedResponse(
      response.stream.asyncMap((chunk) async {
        if (first) {
          first = false;
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        return chunk;
      }),
      response.statusCode,
      headers: response.headers,
      request: response.request,
    );
  }

  @override
  void close() => _inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Offline LLM Download, Refresh, Start, Send, cancel, Stop and Delete',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('devutils-llm-ui-audit-');
      final service = LocalLLMService(
        modelDirectory: dir,
        clientFactory: _ChatDelayClient.new,
      );
      addTearDown(() async {
        await service.stopServer();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await const MethodChannel(
        'devutils/testing',
      ).invokeMethod<void>('activate');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(body: buildOfflineLlm(service: service)),
        ),
      );
      Future<void> waitUntil(bool Function() done) async {
        for (var i = 0; i < 600 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        if (!done()) {
          debugPrint(
            'LLM UI timeout: ready=${service.isReady} icons=${tester.widgetList<IconButton>(find.byType(IconButton)).map((w) => w.tooltip).toList()} messages=${tester.widgetList<SelectableText>(find.byType(SelectableText)).map((w) => w.data).toList()}',
          );
          debugPrint(
            'Visible text: ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}',
          );
        }
        expect(done(), isTrue);
      }

      await waitUntil(
        () => find.text('No models downloaded yet.').evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Send',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Download').first);
      await waitUntil(() => find.text('Start').evaluate().isNotEmpty);
      expect(
        (await service.getAvailableModels()).single.size,
        greaterThan(300000000),
      );
      await tester.tap(find.byTooltip('Refresh'));
      await waitUntil(() => find.text('Start').evaluate().isNotEmpty);
      await tester.tap(find.text('Start'));
      await waitUntil(
        () => service.isReady && find.text('Running').evaluate().isNotEmpty,
      );
      final prompt = find.byWidgetPredicate(
        (w) => w is TextField && w.enabled == true && w.maxLines == 4,
      );
      // Find the actual enabled chat field.
      final chat = prompt.evaluate().isNotEmpty
          ? prompt
          : find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.hintText == 'Type a message... (Enter to send)',
            );
      tester.widget<TextField>(chat).controller!.text =
          'Reply with a short greeting.';
      await tester.pump();
      final send = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Send',
      );
      await tester.tap(send);
      await waitUntil(
        () =>
            send.evaluate().isNotEmpty &&
            tester
                    .widgetList<SelectableText>(find.byType(SelectableText))
                    .length ==
                2,
      );
      final messages = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList();
      expect(messages.first.data, 'Reply with a short greeting.');
      expect(messages.last.data!.trim(), isNotEmpty);
      expect(messages.last.data, isNot('...'));
      tester.widget<TextField>(chat).controller!.text = 'Write a long story.';
      await tester.pump();
      expect(
        tester.widget<TextField>(chat).controller!.text,
        'Write a long story.',
      );
      await tester.tap(send);

      await tester.pump();
      final cancel = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Stop response',
      );
      await waitUntil(() => cancel.evaluate().isNotEmpty);
      await tester.tap(cancel);
      await tester.pump();
      await waitUntil(() => send.evaluate().isNotEmpty);
      expect(
        service.isReady,
        isTrue,
        reason: 'Cancel must stop the response, not the server.',
      );
      await tester.tap(find.text('Stop'));
      await waitUntil(
        () => !service.isReady && find.text('Start').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Delete'));
      await waitUntil(
        () => find.text('No models downloaded yet.').evaluate().isNotEmpty,
      );
      expect(await service.getAvailableModels(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
