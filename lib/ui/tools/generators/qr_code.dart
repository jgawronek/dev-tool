/// QR code reader/generator tool view.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../services/file_dialog_service.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';
import '../../tool_sample_action.dart';

class _QrCodeView extends StatefulWidget {
  const _QrCodeView();

  @override
  State<_QrCodeView> createState() => _QrCodeViewState();
}

class _QrCodeViewState extends State<_QrCodeView> {
  final TextEditingController _content = TextEditingController();
  String _template = 'Plain text';
  String _errorCorrection = 'High (30%)';
  bool _roundedModules = false;
  bool _circleEyes = false;
  String? _logoPath;
  ui.Image? _logoImage;

  static const _ecLevels = <String, int>{
    'Low (7%)': QrErrorCorrectLevel.L,
    'Medium (15%)': QrErrorCorrectLevel.M,
    'Quartile (25%)': QrErrorCorrectLevel.Q,
    'High (30%)': QrErrorCorrectLevel.H,
  };

  int get _ecLevel => _ecLevels[_errorCorrection] ?? QrErrorCorrectLevel.H;

  QrEyeStyle get _eyeStyle => QrEyeStyle(
    eyeShape: _circleEyes ? QrEyeShape.circle : QrEyeShape.square,
    color: Colors.black,
  );

  QrDataModuleStyle get _dataModuleStyle => QrDataModuleStyle(
    dataModuleShape: _roundedModules
        ? QrDataModuleShape.circle
        : QrDataModuleShape.square,
    color: Colors.black,
  );

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  void _updatePreview() {
    setState(() {});
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  Future<void> _pickLogo() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    );
    if (path == null || !mounted) return;
    try {
      final bytes = await File(path).readAsBytes();
      final image = await _decodeUiImage(bytes);
      if (!mounted) return;
      setState(() {
        _logoPath = path;
        _logoImage = image;
        // A center logo covers data modules, so force the highest error
        // correction to keep the code scannable.
        _errorCorrection = 'High (30%)';
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load logo: $error')));
    }
  }

  void _removeLogo() {
    setState(() {
      _logoPath = null;
      _logoImage = null;
    });
  }

  Future<void> _savePng() async {
    final data = _content.text;
    if (data.isEmpty) return;
    try {
      const exportSize = 1024.0;
      const margin = exportSize * 0.08; // quiet zone
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: _ecLevel,
        gapless: true,
        eyeStyle: _eyeStyle,
        dataModuleStyle: _dataModuleStyle,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        const Rect.fromLTWH(0, 0, exportSize, exportSize),
      );
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, exportSize, exportSize),
        Paint()..color = Colors.white,
      );
      canvas.save();
      canvas.translate(margin, margin);
      painter.paint(
        canvas,
        const Size(exportSize - 2 * margin, exportSize - 2 * margin),
      );
      canvas.restore();

      final logo = _logoImage;
      if (logo != null) {
        const center = Offset(exportSize / 2, exportSize / 2);
        final plate = exportSize * 0.22;
        final plateRect = Rect.fromCenter(
          center: center,
          width: plate,
          height: plate,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(plateRect, const Radius.circular(24)),
          Paint()..color = Colors.white,
        );
        final inner = plate * 0.82;
        final scale = min(inner / logo.width, inner / logo.height);
        final drawn = Rect.fromCenter(
          center: center,
          width: logo.width * scale,
          height: logo.height * scale,
        );
        canvas.drawImageRect(
          logo,
          Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
          drawn,
          Paint()..filterQuality = FilterQuality.high,
        );
      }

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(
        exportSize.toInt(),
        exportSize.toInt(),
      );
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null || !mounted) return;
      final path = await FileDialogService.saveFile(
        suggestedName: 'qr-code.png',
        allowedExtensions: const ['png'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes.buffer.asUint8List());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save QR code: $error')));
    }
  }

  void _applyTemplate(String value) {
    final content = switch (value) {
      'vCard' =>
        'BEGIN:VCARD\nVERSION:3.0\nFN:Alex Johnson\nORG:DevUtils\nEMAIL:alex@example.com\nTEL:+15551234567\nEND:VCARD',
      'Wi-Fi' => 'WIFI:T:WPA;S:Example-Network;P:correct-horse-battery;;',
      'URL' => 'https://example.com',
      'Email' => 'mailto:alex@example.com?subject=Hello&body=Message',
      'SMS' => 'SMSTO:+15551234567:Hello from DevUtils',
      _ => 'Hello from DevUtils',
    };
    setState(() {
      _template = value;
      _content.text = content;
    });
    _updatePreview();
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: () {
        setState(() => _content.text = 'BEGIN:VCARD\nFN:DevUtils\nEND:VCARD');
        _updatePreview();
      },
      child: buildAdaptiveSplit(
        first: EditorPane(
          label: 'Content',
          actions: [
            SmallDropdown(
              items: const [
                'Plain text',
                'URL',
                'vCard',
                'Wi-Fi',
                'Email',
                'SMS',
              ],
              initialValue: _template,
              onChanged: _applyTemplate,
            ),
          ],
          controller: _content,
          onChanged: (_) => _updatePreview(),
          placeholder: 'BEGIN:VCARD...',
        ),
        second: Column(
          children: [
            Expanded(
              child: ToolPanel(
                title: 'QR code',
                actions: [
                  ToolButton(
                    label: 'Save PNG',
                    onPressed: _content.text.isEmpty ? null : _savePng,
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: _content.text.isEmpty
                        ? Text(
                            'Enter content to generate a QR code',
                            style: mutedToolTextStyle(context),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 320,
                              maxHeight: 320,
                            ),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      QrImageView(
                                        data: _content.text,
                                        version: QrVersions.auto,
                                        errorCorrectionLevel: _ecLevel,
                                        backgroundColor: Colors.white,
                                        eyeStyle: _eyeStyle,
                                        dataModuleStyle: _dataModuleStyle,
                                        errorStateBuilder: (context, error) =>
                                            Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Text(
                                                'Content too long for a QR code at this error-correction level.',
                                                textAlign: TextAlign.center,
                                                style: errorToolTextStyle(
                                                  context,
                                                ),
                                              ),
                                            ),
                                      ),
                                      if (_logoPath != null)
                                        FractionallySizedBox(
                                          widthFactor: 0.24,
                                          heightFactor: 0.24,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Image.file(
                                              File(_logoPath!),
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ToolToolbar(
              children: [
                SmallDropdown(
                  items: const ['Square modules', 'Rounded modules'],
                  initialValue: _roundedModules
                      ? 'Rounded modules'
                      : 'Square modules',
                  onChanged: (value) => setState(
                    () => _roundedModules = value == 'Rounded modules',
                  ),
                ),
                SmallDropdown(
                  items: const ['Square eyes', 'Circle eyes'],
                  initialValue: _circleEyes ? 'Circle eyes' : 'Square eyes',
                  onChanged: (value) =>
                      setState(() => _circleEyes = value == 'Circle eyes'),
                ),
                if (_logoPath == null)
                  ToolButton(label: 'Add Logo', onPressed: _pickLogo)
                else ...[
                  ToolButton(label: 'Change Logo', onPressed: _pickLogo),
                  ToolButton(label: 'Remove Logo', onPressed: _removeLogo),
                ],

                SmallDropdown(
                  items: _ecLevels.keys.toList(),
                  initialValue: _errorCorrection,
                  onChanged: (value) =>
                      setState(() => _errorCorrection = value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget buildQrCode() {
  return const _QrCodeView();
}
