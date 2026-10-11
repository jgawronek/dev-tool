import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/tool_harness.dart';

const fixture =
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAQklEQVR4nGO48/o/VmRUfAkrIlU9w6gFoxYMAQuoZRAu9aMWjFowFCyglkG41I9aMGrBULCAWgbhUj9qwagFQ8ACACkLenlPAV28AAAAAElFTkSuQmCC';
void main() {
  testWidgets(
    'image file encodes exact bytes, renders pixels, and copies an image',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('base64-image-audit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/sample.png');
      file.writeAsBytesSync(base64Decode(fixture));
      const dialog = MethodChannel('devutils/file_dialogs');
      const clipboard = MethodChannel('devutils/clipboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(dialog, (call) async => file.path);
      Uint8List? copied;
      messenger.setMockMethodCallHandler(clipboard, (call) async {
        expect(call.method, 'copyImage');
        copied = call.arguments as Uint8List;
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(dialog, null);
        messenger.setMockMethodCallHandler(clipboard, null);
      });
      final h = ToolHarness(tester);
      await h.open('base64_image_encode_decode');
      await h.tap('Choose image…');
      for (var i = 0; i < 20 && h.text(null).isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await h.settle();
      }
      expect(h.text(null), fixture);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await h.settle();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 32);
      await tester.tap(find.byTooltip('Copy image'));
      await h.settle();
      expect(copied, orderedEquals(base64Decode(fixture)));
      messenger.setMockMethodCallHandler(dialog, (_) async => null);
      await h.tap('Choose image…');
      expect(h.text(null), fixture);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('bad image file leaves previous content intact with recovery', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('base64-image-bad-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/bad.png')
      ..writeAsStringSync('not image data');
    const dialog = MethodChannel('devutils/file_dialogs');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(dialog, (_) async => file.path);
    addTearDown(() => messenger.setMockMethodCallHandler(dialog, null));
    final h = ToolHarness(tester);
    await h.open('base64_image_encode_decode');
    await h.tap('Load sample');
    await h.tap('Choose image…');
    for (
      var i = 0;
      i < 30 &&
          find.textContaining('Could not load that image').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await h.settle();
    }
    expect(h.text(null), fixture);
    expect(find.textContaining('Could not load that image'), findsOneWidget);
    await h.tap('Load sample');
    expect(tester.takeException(), isNull);
  });
}
