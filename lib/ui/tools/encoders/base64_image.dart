/// Base64 image encode/decode tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../../../services/file_dialog_service.dart';
import '../../../services/native_clipboard_service.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _Base64ImageView extends StatefulWidget {
  const _Base64ImageView();

  @override
  State<_Base64ImageView> createState() => _Base64ImageViewState();
}

class _Base64ImageViewState extends State<_Base64ImageView> {
  final TextEditingController _input = TextEditingController();
  String _previewLabel = 'Image preview (base64 only)';
  Uint8List? _previewBytes;
  String? _previewError;
  bool _loading = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _setSample() {
    // A valid 32 × 32 blue checkerboard, large enough to see in the preview.
    _input.text =
        'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAQklEQVR4nGO48/o/VmRUfAkrIlU9w6gFoxYMAQuoZRAu9aMWjFowFCyglkG41I9aMGrBULCAWgbhUj9qwagFQ8ACACkLenlPAV28AAAAAElFTkSuQmCC';
    _updatePreview();
  }

  Future<void> _copyString() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
  }

  Future<void> _copyImage() async {
    final bytes = _previewBytes;
    if (bytes == null) return;
    try {
      await NativeClipboardService.copyImage(bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not copy the image. Please try again.'),
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final path = await FileDialogService.openFile(
        allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      );
      if (!mounted || path == null) return;
      await _loadImage(path);
    } catch (_) {
      if (mounted) {
        setState(
          () => _previewError = 'Could not open the image. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadImage(String path) async {
    try {
      final file = File(path);
      if (await file.length() > 20 * 1024 * 1024) {
        throw const FormatException('Image too large');
      }
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted) return;
      _input.text = base64Encode(bytes);
      _updatePreview();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _previewError = 'Choose a supported image smaller than 20 MB.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not load that image. Choose PNG, JPEG, GIF, WebP, or BMP under 20 MB.',
          ),
        ),
      );
    }
  }

  void _updatePreview() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _previewLabel = 'Image preview (base64 only)';
        _previewBytes = null;
        _previewError = null;
      });
      return;
    }
    try {
      final bytes = _decodeBase64Image(text);
      setState(() {
        _previewBytes = bytes;
        _previewLabel = '${bytes.length} bytes';
        _previewError = null;
      });
    } catch (error) {
      setState(() {
        _previewBytes = null;
        _previewLabel = 'Image preview (base64 only)';
        _previewError = 'Invalid image data';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: buildAdaptiveSplit(
        first: FileDropTargetRegion(
          targetId: 'base64-image-${identityHashCode(this)}',
          onDropped: (paths) {
            if (paths.isNotEmpty) {
              _loadImage(paths.first);
            }
          },
          child: EditorPane(
            label: 'String',
            enableFileDrop: false,
            actions: [
              ToolButton(
                label: _loading ? 'Loading…' : 'Choose image…',
                onPressed: _loading ? null : _pickImage,
              ),
              ToolButton(label: 'Copy', onPressed: _copyString),
            ],
            controller: _input,
            onChanged: (_) => _updatePreview(),
          ),
        ),
        second: ToolPanel(
          title: 'Image',
          actions: [
            IconButton(
              tooltip: 'Copy image',
              onPressed: _previewBytes == null ? null : _copyImage,
              icon: const Icon(Icons.copy_outlined, size: 17),
            ),
          ],
          child: Stack(
            children: [
              Center(
                child: _previewBytes == null
                    ? Text(
                        _previewError ?? _previewLabel,
                        style: _previewError == null
                            ? mutedToolTextStyle(context)
                            : errorToolTextStyle(context),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(18),
                        child: Image.memory(
                          _previewBytes!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (context, error, stackTrace) => Text(
                            'Could not render image',
                            style: errorToolTextStyle(context),
                          ),
                        ),
                      ),
              ),
              if (_previewBytes != null)
                Positioned(
                  left: 12,
                  bottom: 10,
                  child: Text(
                    _previewLabel,
                    style: mutedToolTextStyle(context, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Uint8List _decodeBase64Image(String input) {
  var value = input.trim();
  final comma = value.indexOf(',');
  if (value.toLowerCase().startsWith('data:image/') && comma >= 0) {
    value = value.substring(comma + 1);
  }
  value = value.replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) throw const FormatException('No image data.');
  return Uint8List.fromList(base64Decode(value));
}

Widget buildBase64Image() {
  return const _Base64ImageView();
}
