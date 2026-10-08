/// Payload embed/extract tool view.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../services/file_dialog_service.dart';
import '../../../services/payload_embedding_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';

class _PayloadEmbedderView extends StatefulWidget {
  const _PayloadEmbedderView();

  @override
  State<_PayloadEmbedderView> createState() => _PayloadEmbedderViewState();
}

class _PayloadEmbedderViewState extends State<_PayloadEmbedderView> {
  final TextEditingController _carrierPath = TextEditingController();
  final TextEditingController _payloadPath = TextEditingController();
  final TextEditingController _outputPath = TextEditingController();
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _status = TextEditingController();
  late final String _dropTargetScope = identityHashCode(this).toRadixString(16);

  int _modeIndex = 0;
  bool _busy = false;
  String? _error;
  EmbeddedPayloadInfo? _info;

  bool get _isEmbed => _modeIndex == 0;
  bool get _isCheck => _modeIndex == 1;
  bool get _isDecode => _modeIndex == 2;
  String get _carrierDropTargetId => 'payload-carrier-file-$_dropTargetScope';
  String get _payloadDropTargetId => 'payload-payload-file-$_dropTargetScope';

  @override
  void dispose() {
    _carrierPath.dispose();
    _payloadPath.dispose();
    _outputPath.dispose();
    _passphrase.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _embed() async {
    await _runFileAction(() async {
      final carrierFile = File(_carrierPath.text.trim());
      final payloadFile = File(_payloadPath.text.trim());
      if (!await carrierFile.exists()) {
        throw const FileSystemException('Carrier/stego file does not exist');
      }
      if (!await payloadFile.exists()) {
        throw const FileSystemException('Payload file does not exist');
      }
      final outputPath = _resolvedEmbedOutputPath(carrierFile.path);
      final result = PayloadEmbeddingService.embed(
        carrier: await carrierFile.readAsBytes(),
        payload: await payloadFile.readAsBytes(),
        payloadFileName: p.basename(payloadFile.path),
        passphrase: _passphrase.text,
      );
      await File(outputPath).writeAsBytes(result.bytes);
      _info = result.info;
      _outputPath.text = outputPath;
      _status.text = [
        'Embedded encrypted file.',
        'Output: $outputPath',
        'Carrier: ${result.info.format.label}',
        'Method: ${result.info.method}',
        'Envelope: ${_formatPayloadBytes(result.info.envelopeSize)}',
        'PBKDF2 iterations: ${result.info.iterations}',
      ].join('\n');
    });
  }

  Future<void> _check({bool preferOutput = false}) async {
    final targetPath = _checkTargetPath(preferOutput: preferOutput);
    await _runFileAction(
      () async {
        final stegoFile = File(targetPath);
        if (!await stegoFile.exists()) {
          throw const FileSystemException('File does not exist');
        }
        final bytes = await stegoFile.readAsBytes();
        _info = PayloadEmbeddingService.inspect(bytes);
        if (_info == null) {
          _status.text = [
            'No DevUtils encrypted payload found.',
            'Checked: $targetPath',
          ].join('\n');
          return;
        }
        _status.text = [
          'Encrypted payload found.',
          'Checked: $targetPath',
          'Carrier: ${_info!.format.label}',
          'Method: ${_info!.method}',
          'Stored envelope: ${_formatPayloadBytes(_info!.envelopeSize)}',
          'Carrier size: ${_formatPayloadBytes(_info!.carrierSize)}',
          'Segments/chunks: ${_info!.segmentCount}',
          'PBKDF2 iterations: ${_info!.iterations}',
        ].join('\n');
      },
      requirePassphrase: false,
      requirePayloadPath: false,
      targetPath: targetPath,
    );
  }

  String _checkTargetPath({required bool preferOutput}) {
    final outputPath = _outputPath.text.trim();
    if (preferOutput && outputPath.isNotEmpty) return outputPath;
    return _carrierPath.text.trim();
  }

  Future<void> _decode() async {
    await _runFileAction(() async {
      final carrierFile = File(_carrierPath.text.trim());
      if (!await carrierFile.exists()) {
        throw const FileSystemException('Carrier/stego file does not exist');
      }
      final bytes = await carrierFile.readAsBytes();
      final decoded = PayloadEmbeddingService.extract(
        carrier: bytes,
        passphrase: _passphrase.text,
      );
      final outputPath = _resolvedDecodeOutputPath(
        carrierFile.path,
        decoded.fileName,
      );
      await File(outputPath).writeAsBytes(decoded.bytes);
      _outputPath.text = outputPath;
      _info = PayloadEmbeddingService.inspect(bytes);
      _status.text = [
        'Decoded embedded file.',
        'Output: $outputPath',
        'Embedded filename: ${decoded.fileName}',
        'Payload size: ${_formatPayloadBytes(decoded.bytes.length)}',
        if (decoded.embeddedAt != null)
          'Embedded at: ${decoded.embeddedAt!.toLocal()}',
      ].join('\n');
    });
  }

  Future<void> _runFileAction(
    Future<void> Function() action, {
    bool requirePassphrase = true,
    bool requirePayloadPath = true,
    String? targetPath,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status.clear();
      _info = null;
    });
    try {
      if ((targetPath ?? _carrierPath.text.trim()).isEmpty) {
        throw ArgumentError('Enter a carrier/stego file path.');
      }
      if (requirePassphrase && _passphrase.text.isEmpty) {
        throw ArgumentError('Enter the passphrase.');
      }
      if (requirePayloadPath && _isEmbed && _payloadPath.text.trim().isEmpty) {
        throw ArgumentError('Enter the payload file path.');
      }
      await action();
    } catch (e) {
      _status.text = '';
      _error = _friendlyPayloadError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _resolvedEmbedOutputPath(String carrierPath) {
    final explicit = _outputPath.text.trim();
    if (explicit.isNotEmpty) {
      final type = FileSystemEntity.typeSync(explicit);
      if (type == FileSystemEntityType.directory) {
        return p.join(explicit, _defaultEmbeddedFileName(carrierPath));
      }
      return explicit;
    }
    return p.join(
      p.dirname(carrierPath),
      _defaultEmbeddedFileName(carrierPath),
    );
  }

  String _defaultEmbeddedFileName(String carrierPath) {
    final extension = p.extension(carrierPath);
    final baseName = p.basenameWithoutExtension(carrierPath);
    return '$baseName.embedded$extension';
  }

  String _resolvedDecodeOutputPath(String carrierPath, String decodedFileName) {
    final explicit = _outputPath.text.trim();
    if (explicit.isNotEmpty) {
      final type = FileSystemEntity.typeSync(explicit);
      if (type == FileSystemEntityType.directory) {
        return p.join(explicit, decodedFileName);
      }
      return explicit;
    }
    final directory = p.dirname(carrierPath);
    return p.join(directory, decodedFileName);
  }

  Future<void> _pickCarrierFile() async {
    final path = await FileDialogService.openFile(
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'pdf'],
    );
    if (path == null || !mounted) return;
    setState(() {
      _carrierPath.text = path;
      _error = null;
    });
  }

  Future<void> _pickPayloadFile() async {
    final path = await FileDialogService.openFile();
    if (path == null || !mounted) return;
    setState(() {
      _payloadPath.text = path;
      _error = null;
    });
  }

  Future<void> _pickOutputFile() async {
    final carrierPath = _carrierPath.text.trim();
    final suggestedName = carrierPath.isEmpty
        ? (_isDecode ? 'decoded-payload' : 'embedded-output')
        : _isDecode
        ? p.basename(
            _outputPath.text.trim().isEmpty
                ? 'decoded-payload'
                : _outputPath.text.trim(),
          )
        : _defaultEmbeddedFileName(carrierPath);
    final directoryPath = carrierPath.isEmpty ? null : p.dirname(carrierPath);
    final path = await FileDialogService.saveFile(
      suggestedName: suggestedName,
      directoryPath: directoryPath,
      allowedExtensions: _isDecode
          ? const []
          : const ['png', 'jpg', 'jpeg', 'pdf'],
    );
    if (path == null || !mounted) return;
    setState(() {
      _outputPath.text = path;
      _error = null;
    });
  }

  Future<void> _pickOutputDirectory() async {
    final path = await FileDialogService.openDirectory();
    if (path == null || !mounted) return;
    setState(() {
      _outputPath.text = path;
      _error = null;
    });
  }

  void _setDroppedPath(TextEditingController controller, List<String> paths) {
    if (paths.isEmpty) return;
    setState(() {
      controller.text = paths.first;
      _error = null;
    });
  }

  void _setExamplePaths() {
    _carrierPath.text = '/Users/me/Desktop/image.png';
    _payloadPath.text = '/Users/me/Desktop/secret.txt';
    _outputPath.text = '/Users/me/Desktop/image.embedded.png';
    _status.text =
        'Use PNG, JPG, or PDF carriers. The embedded file is encrypted before it is stored.';
    setState(() {
      _error = null;
      _info = null;
    });
  }

  void _clear() {
    _carrierPath.clear();
    _payloadPath.clear();
    _outputPath.clear();
    _passphrase.clear();
    _status.clear();
    setState(() {
      _error = null;
      _info = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResizableSplit(
      horizontal: true,
      initialRatio: 0.46,
      minFirstExtent: 420,
      minSecondExtent: 360,
      first: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedToggle(
                    options: const ['Embed', 'Check', 'Decode'],
                    initialIndex: _modeIndex,
                    onChanged: (index) => setState(() => _modeIndex = index),
                  ),
                  ToolButton(
                    label: 'Example paths',
                    onPressed: _setExamplePaths,
                  ),
                  ToolButton(label: 'Reset', onPressed: _clear),
                ],
              ),
              const SizedBox(height: 16),
              _PayloadPathField(
                label: _isEmbed ? 'Carrier file' : 'Stego file',
                controller: _carrierPath,
                hint: '/path/to/image.png, image.jpg, or document.pdf',
                onPickFile: _pickCarrierFile,
                dropTargetId: _carrierDropTargetId,
                onDropped: (paths) => _setDroppedPath(_carrierPath, paths),
              ),
              if (_isEmbed) ...[
                const SizedBox(height: 10),
                _PayloadPathField(
                  label: 'Payload file',
                  controller: _payloadPath,
                  hint: '/path/to/secret.txt',
                  onPickFile: _pickPayloadFile,
                  dropTargetId: _payloadDropTargetId,
                  onDropped: (paths) => _setDroppedPath(_payloadPath, paths),
                ),
              ],
              if (!_isCheck) ...[
                const SizedBox(height: 10),
                _PayloadPathField(
                  label: _isDecode ? 'Decoded output' : 'Output file',
                  controller: _outputPath,
                  hint: _isDecode
                      ? 'Leave empty to use embedded filename'
                      : 'Leave empty to create *.embedded.*',
                  onPickFile: _pickOutputFile,
                  onPickDirectory: _pickOutputDirectory,
                ),
              ],
              if (!_isCheck) ...[
                const SizedBox(height: 10),
                _PayloadPathField(
                  label: 'Passphrase',
                  controller: _passphrase,
                  hint: 'Required for encryption/decode',
                  obscureText: true,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_isEmbed)
                    ToolButton(
                      label: _busy ? 'Embedding...' : 'Embed encrypted',
                      onPressed: _busy ? null : _embed,
                    ),
                  if (_isCheck)
                    ToolButton(
                      label: _busy ? 'Checking...' : 'Check embedded data',
                      onPressed: _busy ? null : () => _check(),
                    ),
                  if (!_isCheck)
                    ToolButton(
                      label: _busy
                          ? 'Checking...'
                          : _isEmbed && _outputPath.text.trim().isNotEmpty
                          ? 'Check output'
                          : 'Check embedded data',
                      onPressed: _busy
                          ? null
                          : () => _check(preferOutput: _isEmbed),
                    ),
                  if (_isDecode)
                    ToolButton(
                      label: _busy ? 'Decoding...' : 'Decode',
                      onPressed: _busy ? null : _decode,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _PayloadMethodSummary(),
            ],
          ),
        ),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_info != null) ...[
            _PayloadInfoBar(info: _info!),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            Text(_error!, style: errorToolTextStyle(context)),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: EditorPane(
              label: 'Result',
              actions: const [],
              controller: _status,
              readOnly: true,
              showHeader: false,
              placeholder:
                  'Embed, check, or decode encrypted files inside PNG, JPG, or PDF carriers...',
            ),
          ),
        ],
      ),
    );
  }
}

class _PayloadPathField extends StatelessWidget {
  const _PayloadPathField({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscureText = false,
    this.onPickFile,
    this.onPickDirectory,
    this.dropTargetId,
    this.onDropped,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final VoidCallback? onPickFile;
  final VoidCallback? onPickDirectory;
  final String? dropTargetId;
  final FileDropHandler? onDropped;

  @override
  Widget build(BuildContext context) {
    return _PayloadPathDropField(
      label: label,
      controller: controller,
      hint: hint,
      obscureText: obscureText,
      onPickFile: onPickFile,
      onPickDirectory: onPickDirectory,
      dropTargetId: dropTargetId,
      onDropped: onDropped,
    );
  }
}

class _PayloadPathDropField extends StatefulWidget {
  const _PayloadPathDropField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.obscureText,
    this.onPickFile,
    this.onPickDirectory,
    this.dropTargetId,
    this.onDropped,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final VoidCallback? onPickFile;
  final VoidCallback? onPickDirectory;
  final String? dropTargetId;
  final FileDropHandler? onDropped;

  @override
  State<_PayloadPathDropField> createState() => _PayloadPathDropFieldState();
}

class _PayloadPathDropFieldState extends State<_PayloadPathDropField> {
  final GlobalKey _dropKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _registerDropTarget();
  }

  @override
  void didUpdateWidget(covariant _PayloadPathDropField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dropTargetId != widget.dropTargetId ||
        oldWidget.onDropped != widget.onDropped) {
      if (oldWidget.dropTargetId != null) {
        FileDropService.unregisterTarget(oldWidget.dropTargetId!);
      }
      _registerDropTarget();
    }
  }

  @override
  void dispose() {
    final targetId = widget.dropTargetId;
    if (targetId != null) FileDropService.unregisterTarget(targetId);
    super.dispose();
  }

  void _registerDropTarget() {
    final targetId = widget.dropTargetId;
    final onDropped = widget.onDropped;
    if (targetId == null || onDropped == null) return;
    FileDropService.registerTarget(targetId, key: _dropKey, handler: onDropped);
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final targetId = widget.dropTargetId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: appColors.editorText,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        MouseRegion(
          onEnter: targetId == null
              ? null
              : (_) => FileDropService.setActiveTarget(targetId),
          onExit: targetId == null
              ? null
              : (_) => FileDropService.setActiveTarget(null),
          child: Row(
            key: _dropKey,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  obscureText: widget.obscureText,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    filled: true,
                    fillColor: appColors.panelElevated,
                  ),
                  style: TextStyle(color: appColors.editorText, fontSize: 13),
                ),
              ),
              if (widget.onPickFile != null) ...[
                const SizedBox(width: 6),
                ToolIconButton(
                  icon: Icons.insert_drive_file,
                  tooltip: 'Choose file',
                  onPressed: widget.onPickFile,
                ),
              ],
              if (widget.onPickDirectory != null) ...[
                const SizedBox(width: 6),
                ToolIconButton(
                  icon: Icons.folder_open,
                  tooltip: 'Choose folder',
                  onPressed: widget.onPickDirectory,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PayloadMethodSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final rows = const [
      ('PNG', 'private ancillary chunk'),
      ('JPG', 'APP15 metadata segments'),
      ('PDF', 'comment payload block'),
      ('Crypto', 'AES-256-CBC + HMAC-SHA256'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: toolSurfaceDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Format support',
            style: TextStyle(
              color: appColors.editorText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        color: appColors.mutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      style: TextStyle(color: appColors.editorText),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PayloadInfoBar extends StatelessWidget {
  const _PayloadInfoBar({required this.info});

  final EmbeddedPayloadInfo info;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: appColors.accentSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(
            info.format.label,
            style: TextStyle(
              color: appColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(info.method, style: TextStyle(color: appColors.editorText)),
          Text(
            _formatPayloadBytes(info.envelopeSize),
            style: TextStyle(color: appColors.mutedText),
          ),
        ],
      ),
    );
  }
}

String _friendlyPayloadError(Object error) {
  if (error is FileSystemException) {
    return error.message;
  }
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Invalid input.';
  }
  if (error is FormatException) {
    return error.message;
  }
  return error.toString();
}

String _formatPayloadBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Widget buildPayloadEmbedder() {
  return const _PayloadEmbedderView();
}
