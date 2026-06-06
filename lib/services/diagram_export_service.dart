import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Rasterizes a diagram [RepaintBoundary] to PNG and wraps it in a PDF for
/// export or printing. The boundary is captured at its natural (unscaled) size
/// regardless of the canvas's current pan/zoom, so the whole diagram is
/// exported — not just the visible viewport.
class DiagramExportService {
  DiagramExportService._();

  /// Longest captured side in pixels, capped so a large diagram can't allocate
  /// a gigantic bitmap.
  static const double _maxSidePx = 6000;

  /// Captured diagram as PNG bytes, plus the source bounds (logical px). Returns
  /// null if the boundary isn't laid out (nothing to export).
  static Future<({Uint8List bytes, Size size})?> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 2.5,
  }) async {
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    final size = object.size;
    if (size.isEmpty) return null;

    // Clamp the ratio so the longest side stays within [_maxSidePx].
    final longest = size.longestSide;
    final ratio = longest * pixelRatio > _maxSidePx
        ? (_maxSidePx / longest)
        : pixelRatio;

    final image = await object.toImage(
      pixelRatio: ratio.clamp(1.0, pixelRatio),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return (bytes: data.buffer.asUint8List(), size: size);
    } finally {
      image.dispose();
    }
  }

  /// A single-page PDF containing [png], scaled to fit [format] (defaulting to
  /// A4 in the orientation that matches the image) with a small margin.
  static Future<Uint8List> buildPdf(
    Uint8List png,
    Size imageSize, {
    PdfPageFormat? format,
  }) async {
    final doc = pw.Document();
    final image = pw.MemoryImage(png);
    final base = format ?? PdfPageFormat.a4;
    // Orient the page to match the diagram's aspect.
    final page = imageSize.width >= imageSize.height
        ? base.landscape
        : base.portrait;
    doc.addPage(
      pw.Page(
        pageFormat: page,
        margin: const pw.EdgeInsets.all(18),
        build: (context) =>
            pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
    return doc.save();
  }

  /// Opens the native print / "Save as PDF" dialog for the captured diagram.
  /// [title] names the print job.
  static Future<void> printPng(
    Uint8List png,
    Size imageSize, {
    required String title,
  }) {
    return Printing.layoutPdf(
      name: title,
      onLayout: (format) => buildPdf(png, imageSize, format: format),
    );
  }
}
