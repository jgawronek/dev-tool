import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dev_tool/services/local_llm_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native model download, server startup, streamed inference and stop',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync(
        'devutils-native-model-audit-',
      );
      final service = LocalLLMService(modelDirectory: dir);
      addTearDown(() async {
        await service.stopServer();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      expect(File(service.serverBinaryPath).existsSync(), isTrue);
      final progress = <double>[];
      await tester.runAsync(() async {
        await service.downloadModel(kModelPresets.first, progress.add);
        final models = await service.getAvailableModels();
        expect(models, hasLength(1));
        expect(models.single.size, greaterThan(300000000));
        expect(progress.last, 1);
        await service.startServer(models.single.path);
        expect(service.isReady, isTrue);
        final output = await service
            .generate(
              'Reply with a short greeting.',
              maxTokens: 16,
              temperature: 0,
            )
            .join()
            .timeout(const Duration(seconds: 60));
        expect(output.trim(), isNotEmpty);
        await service.stopServer();
        expect(service.isReady, isFalse);
        await service.deleteModel(models.single.path);
        expect(await service.getAvailableModels(), isEmpty);
      });
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
