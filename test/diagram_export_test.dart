import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/diagram_export_service.dart';

void main() {
  testWidgets('capturePng rasterizes a RepaintBoundary to a PNG of its size',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(width: 120, height: 80, color: Colors.blue),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    ({Uint8List bytes, Size size})? capture;
    await tester.runAsync(() async {
      capture = await DiagramExportService.capturePng(key, pixelRatio: 2);
    });

    expect(capture, isNotNull);
    expect(capture!.size, const Size(120, 80));
    expect(capture!.bytes, isNotEmpty);
    // PNG magic number.
    expect(capture!.bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);

    Uint8List? pdf;
    await tester.runAsync(() async {
      pdf = await DiagramExportService.buildPdf(capture!.bytes, capture!.size);
    });
    expect(pdf, isNotNull);
    expect(pdf!, isNotEmpty);
    // PDF header.
    expect(String.fromCharCodes(pdf!.sublist(0, 4)), '%PDF');
  });

  testWidgets('capturePng returns null when the key has no boundary',
      (tester) async {
    final key = GlobalKey();
    ({Uint8List bytes, Size size})? capture = (
      bytes: Uint8List(0),
      size: Size.zero,
    );
    await tester.runAsync(() async {
      capture = await DiagramExportService.capturePng(key);
    });
    expect(capture, isNull);
  });
}
