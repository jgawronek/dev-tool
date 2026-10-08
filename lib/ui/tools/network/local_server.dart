/// Local server tool view.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/file_dialog_service.dart';
import '../../../services/local_server_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

class _LocalServerView extends StatefulWidget {
  const _LocalServerView();

  @override
  State<_LocalServerView> createState() => _LocalServerViewState();
}

class _LocalServerViewState extends State<_LocalServerView> {
  final LocalServerService _service = LocalServerService();
  final TextEditingController _port = TextEditingController(text: '8080');
  final ScrollController _logScroll = ScrollController();
  final List<ServerLogEntry> _logs = [];
  static const int _maxLogs = 1000;
  String? _folder;
  bool _localOnly = true;
  bool _running = false;
  String? _error;

  @override
  void dispose() {
    _service.stop();
    _port.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final path = await FileDialogService.openDirectory();
    if (path == null || !mounted) return;
    setState(() => _folder = path);
  }

  Future<void> _toggle() async {
    if (_running) {
      await _service.stop();
      if (!mounted) return;
      setState(() => _running = false);
    } else {
      final folder = _folder;
      if (folder == null) {
        setState(() => _error = 'Choose a folder to serve first.');
        return;
      }
      final port = int.tryParse(_port.text.trim());
      if (port == null || port < 1 || port > 65535) {
        setState(() => _error = 'Enter a valid port (1–65535).');
        return;
      }
      try {
        await _service.start(
          root: folder,
          port: port,
          localOnly: _localOnly,
          onLog: _onLog,
        );
        if (!mounted) return;
        setState(() {
          _running = true;
          _error = null;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = _friendlyServerError(error, port));
      }
    }
  }

  void _onLog(ServerLogEntry entry) {
    if (!mounted) return;
    final atBottom =
        !_logScroll.hasClients ||
        _logScroll.position.pixels >= _logScroll.position.maxScrollExtent - 40;
    setState(() {
      _logs.add(entry);
      if (_logs.length > _maxLogs) {
        _logs.removeRange(0, _logs.length - _maxLogs);
      }
    });
    if (atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) {
          _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        }
      });
    }
  }

  String _friendlyServerError(Object error, int port) {
    if (error is SocketException) {
      final message = error.osError?.message ?? error.message;
      return 'Could not start server on port $port: $message';
    }
    return 'Could not start server: $error';
  }

  String get _url => 'http://localhost:${_port.text.trim()}/';

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: toolSurfaceDecoration(context),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: appColors.mutedText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _folder ?? 'No folder selected',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 12,
                        color: _folder == null
                            ? appColors.mutedText
                            : appColors.editorText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToolButton(
                    label: 'Choose Folder',
                    icon: Icons.folder_open,
                    onPressed: _running ? null : _pickFolder,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Port', style: TextStyle(color: appColors.mutedText)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _port,
                      enabled: !_running,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CompactCheck(
                    label: 'Local only',
                    value: _localOnly,
                    onChanged: _running
                        ? (_) {}
                        : (value) => setState(() => _localOnly = value),
                  ),
                  const Spacer(),
                  ToolButton(
                    label: _running ? 'Stop' : 'Start',
                    icon: _running ? Icons.stop : Icons.play_arrow,
                    onPressed: _toggle,
                  ),
                ],
              ),
              if (_running) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.circle, size: 9, color: appColors.success),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Serving at $_url',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 12,
                          color: appColors.editorText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ToolIconButton(
                      icon: Icons.copy,
                      tooltip: 'Copy URL',
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _url)),
                    ),
                    Text(
                      _localOnly ? 'local only' : 'network accessible',
                      style: TextStyle(
                        fontSize: 11,
                        color: _localOnly
                            ? appColors.mutedText
                            : appColors.warning,
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: errorToolTextStyle(context, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Access log',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: appColors.editorText,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${_logs.length})',
              style: TextStyle(color: appColors.mutedText, fontSize: 12),
            ),
            const Spacer(),
            if (_logs.isNotEmpty)
              ToolButton(
                label: 'Clear log',
                onPressed: () => setState(_logs.clear),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: toolSurfaceDecoration(context),
            child: _logs.isEmpty
                ? Center(
                    child: Text(
                      _running
                          ? 'Waiting for requests…'
                          : 'Start the server to see access logs here.',
                      style: mutedToolTextStyle(context),
                    ),
                  )
                : ListView.builder(
                    controller: _logScroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) =>
                        _ServerLogRow(entry: _logs[index]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ServerLogRow extends StatelessWidget {
  const _ServerLogRow({required this.entry});

  final ServerLogEntry entry;

  String _two(int v) => v.toString().padLeft(2, '0');

  String get _time =>
      '${_two(entry.time.hour)}:${_two(entry.time.minute)}:${_two(entry.time.second)}';

  String get _size {
    if (entry.bytes < 1024) return '${entry.bytes} B';
    if (entry.bytes < 1024 * 1024) {
      return '${(entry.bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(entry.bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final Color statusColor;
    if (entry.status < 300) {
      statusColor = appColors.success;
    } else if (entry.status < 400) {
      statusColor = appColors.accent;
    } else if (entry.status < 500) {
      statusColor = appColors.warning;
    } else {
      statusColor = appColors.error;
    }
    final style = TextStyle(
      fontFamily: 'Menlo',
      fontSize: 12,
      color: appColors.editorText,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _time,
            style: TextStyle(
              fontFamily: 'Menlo',
              fontSize: 12,
              color: appColors.mutedText,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(
              entry.status.toString(),
              style: style.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              entry.method,
              style: style.copyWith(color: appColors.mutedText),
            ),
          ),
          Expanded(
            child: Text(
              entry.path,
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(_size, style: style.copyWith(color: appColors.mutedText)),
          const SizedBox(width: 10),
          Text(entry.client, style: style.copyWith(color: appColors.mutedText)),
        ],
      ),
    );
  }
}

Widget buildLocalServer() {
  return const _LocalServerView();
}
