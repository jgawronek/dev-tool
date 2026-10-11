import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dev_tool/services/native_clipboard_service.dart';
import '../test/tools/base64_image_file_test.dart' show fixture;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native clipboard accepts image objects and rejects invalid bytes', (tester) async {
    await NativeClipboardService.copyImage(base64Decode(fixture));
    await expectLater(NativeClipboardService.copyImage(Uint8List.fromList([1,2,3])), throwsA(anything));
  });
}
