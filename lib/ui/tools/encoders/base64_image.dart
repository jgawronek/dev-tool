/// Base64 image encode/decode tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

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

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    _input.text = text;
    _updatePreview();
  }

  void _setSample() {
    _input.text =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l5F7cwAAAABJRU5ErkJggg==';
    _updatePreview();
  }

  void _clear() {
    setState(() {
      _input.clear();
      _previewLabel = 'Image preview (base64 only)';
      _previewBytes = null;
      _previewError = null;
    });
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
    return ResizableSplit(
      horizontal: true,
      first: EditorPane(
        label: 'String',
        actions: [
          ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
          ToolButton(label: 'Sample', onPressed: _setSample),
          ToolButton(label: 'Clear', onPressed: _clear),
          ToolButton(label: 'Copy', onPressed: _copyString),
        ],
        controller: _input,
        onChanged: (_) => _updatePreview(),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Image',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: toolSurfaceDecoration(context),
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
                              errorBuilder: (context, error, stackTrace) =>
                                  Text(
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
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Load File...',
                          child: IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.upload_file, size: 18),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            splashRadius: 16,
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: _copyImage,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 24),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          child: const Text('Copy'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
