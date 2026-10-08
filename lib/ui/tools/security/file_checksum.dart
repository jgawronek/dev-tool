/// File checksum tool view.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/file_checksum_service.dart';
import '../../../services/file_dialog_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

const _dropTargetId = 'file-checksum-input';

class _FileChecksumView extends StatefulWidget {
  const _FileChecksumView();

  @override
  State<_FileChecksumView> createState() => _FileChecksumViewState();
}

class _FileChecksumViewState extends State<_FileChecksumView> {
  final TextEditingController _path = TextEditingController();
  final TextEditingController _expected = TextEditingController();
  final TextEditingController _report = TextEditingController();

  FileChecksumOutcome? _outcome;
  String _status = 'Choose a file or drop one onto the panel.';
  String? _error;
  var _running = false;
  int _token = 0;

  @override
  void dispose() {
    _path.dispose();
    _expected.dispose();
    _report.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await FileDialogService.openFile();
    if (picked == null || picked.isEmpty) return;
    await _run(picked);
  }

  Future<void> _handleDrop(List<String> paths) async {
    if (paths.isEmpty) return;
    await _run(paths.first);
  }

  Future<void> _run(String filePath) async {
    if (_running) return;
    final token = ++_token;
    setState(() {
      _path.text = filePath;
      _running = true;
      _error = null;
      _status = 'Hashing...';
    });

    FileChecksumOutcome outcome;
    try {
      outcome = await compute(checksumFileWorker, (filePath, _expected.text));
    } catch (error) {
      outcome = FileChecksumOutcome.failure('$error');
    }
    if (!mounted || token != _token) return;

    setState(() {
      _running = false;
      _outcome = outcome.error == null ? outcome : null;
      _error = outcome.error;
      _status = outcome.error != null
          ? ''
          : '${outcome.fileName} · ${humanJsonSize(outcome.sizeBytes)}';
      _report.text = outcome.error == null ? _buildReport(outcome) : '';
    });
  }

  String _buildReport(FileChecksumOutcome outcome) {
    final buffer = StringBuffer()
      ..writeln('file:     ${outcome.fileName}')
      ..writeln('size:     ${humanJsonSize(outcome.sizeBytes)}')
      ..writeln();
    for (final checksum in outcome.checksums) {
      buffer
        ..writeln('${checksum.algorithm.label} (${checksum.algorithm.command})')
        ..writeln(checksum.digest)
        ..writeln();
    }
    buffer.write('shasum -c manifest:\n');
    buffer.write(outcome.toManifest());
    final match = outcome.match;
    if (match != null) {
      buffer
        ..writeln()
        ..writeln();
      buffer.write(
        match
            ? 'verify: MATCH against the expected digest'
                  '${outcome.checkedAlgorithm != null ? ' (${outcome.checkedAlgorithm!.label})' : ''}.'
            : 'verify: no computed digest matches the expected value.',
      );
    }
    return buffer.toString().trimRight();
  }

  void _clear() {
    setState(() {
      _path.clear();
      _outcome = null;
      _expected.clear();
      _report.clear();
      _error = null;
      _status = 'Choose a file or drop one onto the panel.';
    });
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _report.text));
  }

  Future<void> _copyManifest() async {
    final outcome = _outcome;
    if (outcome == null) return;
    await Clipboard.setData(ClipboardData(text: outcome.toManifest()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            outputActions: [
              ToolButton(label: 'Copy', onPressed: _copyReport),
              ToolButton(label: 'Copy manifest', onPressed: _copyManifest),
            ],
            inputController: _path,
            outputController: _report,
            inputLabel: 'File',
            outputLabel: 'Checksums',
            inputPlaceholder: 'No file selected',
            outputPlaceholder: 'Digests appear here...',
            showInputHeader: false,
            showOutputHeader: false,
            // EditorPane only renders inputActions when no overlay is given,
            // so the file controls are composed into the overlay row.
            inputOverlay: _buildInputControls(context),
            inputDropTargetId: _dropTargetId,
            onInputDropped: _handleDrop,
          ),
        ),
        if (_error != null || _status.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error ?? _status,
                style: _error != null
                    ? errorToolTextStyle(context)
                    : mutedToolTextStyle(context),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInputControls(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      // The overlay is width-constrained, so scroll rather than overflow.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToolButton(label: 'Choose file...', onPressed: _pickFile),
            const SizedBox(width: 6),
            ToolButton(label: 'Clear', onPressed: _clear),
            const SizedBox(width: 12),
            const Text(
              'Expected digest',
              style: TextStyle(fontSize: 11.5),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints.tightFor(width: 320),
              child: TextField(
                controller: _expected,
                onSubmitted: (_) =>
                    _path.text.isEmpty ? null : _run(_path.text),
                style: TextStyle(
                  color: appColors.editorText,
                  fontFamily: 'Menlo',
                  fontSize: 11.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Paste a checksum to verify',
                  hintStyle: TextStyle(
                    color: appColors.mutedText,
                    fontSize: 11.5,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5),
                    borderSide: BorderSide(color: appColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5),
                    borderSide: BorderSide(color: appColors.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ToolButton(
              label: 'Verify',
              onPressed: _path.text.isEmpty || _running
                  ? null
                  : () => _run(_path.text),
            ),
            if (_running) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget buildFileChecksum() {
  return const _FileChecksumView();
}

String humanFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
