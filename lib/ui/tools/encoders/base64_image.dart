/// Base64 image encode/decode tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
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

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _setSample() {
    _input.text =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l5F7cwAAAABJRU5ErkJggg==';
    _updatePreview();
  }

  Future<void> _copyString() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
  }

  Future<void> _copyImage() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
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
        first: EditorPane(
          label: 'String',
          actions: [ToolButton(label: 'Copy', onPressed: _copyString)],
          controller: _input,
          onChanged: (_) => _updatePreview(),
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
