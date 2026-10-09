/// Offline LLM tool view.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../services/local_llm_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';

class _OfflineLlmView extends StatefulWidget {
  const _OfflineLlmView();

  @override
  State<_OfflineLlmView> createState() => _OfflineLlmViewState();
}

class _ChatMessage {
  final String role; // 'user' or 'assistant'
  String content;
  _ChatMessage({required this.role, required this.content});
}

class _ChatInputField extends StatefulWidget {
  const _ChatInputField({
    required this.controller,
    required this.onSubmit,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool enabled;

  @override
  State<_ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<_ChatInputField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onSubmit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        maxLines: 4,
        minLines: 1,
        enabled: widget.enabled,
        decoration: InputDecoration(
          hintText: widget.enabled
              ? 'Type a message... (Enter to send)'
              : 'Start a model first...',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
          hintStyle: TextStyle(color: appColors.mutedText),
        ),
        style: TextStyle(
          fontFamily: 'Menlo',
          fontSize: 12,
          color: appColors.editorText,
        ),
      ),
    );
  }
}

class _OfflineLlmViewState extends State<_OfflineLlmView> {
  final LocalLLMService _service = LocalLLMService();
  final TextEditingController _prompt = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ModelInfo> _models = [];
  final List<_ChatMessage> _messages = [];
  bool _loadingModels = false;
  bool _startingServer = false;
  bool _stoppingServer = false;
  bool _generating = false;
  String? _error;

  ModelPreset? _downloadingPreset;
  double _downloadProgress = 0;
  StreamSubscription<String>? _generationSub;

  int _maxTokens = 256;
  double _temperature = 0.7;

  @override
  void initState() {
    super.initState();
    _refreshModels();
  }

  @override
  void dispose() {
    _generationSub?.cancel();
    unawaited(_service.stopServer());
    _prompt.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshModels() async {
    setState(() {
      _loadingModels = true;
      _error = null;
    });
    try {
      final models = await _service.getAvailableModels();
      models.sort((a, b) => a.name.compareTo(b.name));
      setState(() => _models = models);
    } catch (e) {
      setState(() => _error = 'Failed to load models: $e');
    } finally {
      setState(() => _loadingModels = false);
    }
  }

  Future<void> _startServer(ModelInfo model) async {
    if (_startingServer) return;
    final serverBinary = File(_service.serverBinaryPath);
    final serverDir = Directory(_service.serverBundleDir);
    if (!serverBinary.existsSync() || !serverDir.existsSync()) {
      setState(
        () => _error =
            'Missing server bundle. Expected ${_service.serverBundleDir}',
      );
      return;
    }
    final requiredLibs = ['libllama.dylib', 'libggml.dylib'];
    final missingLibs = requiredLibs
        .where(
          (lib) => !File(p.join(_service.serverBundleDir, lib)).existsSync(),
        )
        .toList();
    if (missingLibs.isNotEmpty) {
      setState(
        () => _error =
            'Server bundle is incomplete (missing ${missingLibs.join(", ")}).',
      );
      return;
    }
    setState(() {
      _startingServer = true;
      _error = null;
    });
    try {
      await _service.startServer(model.path);
      setState(() {});
    } catch (e) {
      setState(() => _error = 'Failed to start server: $e');
    } finally {
      setState(() => _startingServer = false);
    }
  }

  Future<void> _stopServer() async {
    if (_stoppingServer) return;
    setState(() => _stoppingServer = true);
    await _service.stopServer();
    setState(() => _stoppingServer = false);
  }

  Future<void> _downloadPreset(ModelPreset preset) async {
    if (_downloadingPreset != null) return;
    if (_isPresetInstalled(preset)) return;
    setState(() {
      _downloadingPreset = preset;
      _downloadProgress = 0;
      _error = null;
    });
    try {
      await _service.downloadModel(preset, (progress) {
        setState(() => _downloadProgress = progress);
      });
      await _refreshModels();
    } catch (e) {
      setState(() => _error = 'Download failed: $e');
    } finally {
      setState(() {
        _downloadingPreset = null;
        _downloadProgress = 0;
      });
    }
  }

  Future<void> _deleteModel(ModelInfo model) async {
    await _service.deleteModel(model.path);
    await _refreshModels();
  }

  Future<void> _run() async {
    if (_generating) return;
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) return;
    if (!_service.isReady) {
      setState(() => _error = 'Start the server before generating.');
      return;
    }

    // Add user message to history and clear input
    final userMessage = _ChatMessage(role: 'user', content: prompt);
    final assistantMessage = _ChatMessage(role: 'assistant', content: '');

    setState(() {
      _messages.add(userMessage);
      _messages.add(assistantMessage);
      _prompt.clear();
      _generating = true;
      _error = null;
    });

    // Build conversation history for context
    final chatHistory = _messages
        .where((m) => m.content.isNotEmpty || m == assistantMessage)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();
    // Remove the empty assistant message from history sent to API
    if (chatHistory.isNotEmpty && chatHistory.last['content']!.isEmpty) {
      chatHistory.removeLast();
    }

    _scrollToBottom();
    _generationSub?.cancel();
    _generationSub = _service
        .generateChat(
          chatHistory,
          maxTokens: _maxTokens,
          temperature: _temperature,
        )
        .listen(
          (chunk) {
            assistantMessage.content += chunk;
            setState(() {});
            _scrollToBottom();
          },
          onError: (err) {
            setState(() {
              _error = 'Generation failed: $err';
              _generating = false;
            });
          },
          onDone: () {
            setState(() => _generating = false);
          },
        );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearHistory() {
    _generationSub?.cancel();
    setState(() {
      _messages.clear();
      _generating = false;
    });
  }

  Future<void> _stopGeneration() async {
    await _generationSub?.cancel();
    _generationSub = null;
    setState(() => _generating = false);
  }

  bool _isPresetInstalled(ModelPreset preset) {
    return _models.any((model) => p.basename(model.path) == preset.filename);
  }

  bool _isModelActive(ModelInfo model) {
    return _service.isReady && _service.currentModel == model.path;
  }

  String _presetSize(ModelPreset preset) {
    final size = preset.sizeBytes;
    if (size > 1e9) return '${(size / 1e9).toStringAsFixed(1)} GB';
    return '${(size / 1e6).toStringAsFixed(0)} MB';
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: toolSurfaceDecoration(context, radius: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The title shrinks with an ellipsis rather than pushing the card's
          // trailing action out of bounds on a narrow panel.
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: Row(
            children: [
              Expanded(
                child: _buildCard(
                  context,
                  title: 'Installed Models',
                  trailing: _loadingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ToolIconButton(
                          icon: Icons.refresh,
                          tooltip: 'Refresh',
                          onPressed: _refreshModels,
                        ),
                  child: _models.isEmpty
                      ? const Center(child: Text('No models downloaded yet.'))
                      : ListView.separated(
                          itemCount: _models.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 12),
                          itemBuilder: (context, index) {
                            final model = _models[index];
                            final isActive = _isModelActive(model);
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        model.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        model.sizeFormatted,
                                        style: mutedToolTextStyle(context),
                                      ),
                                      if (isActive)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            'Running',
                                            style: TextStyle(
                                              color: appColors.success,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ToolButton(
                                  label: isActive ? 'Stop' : 'Start',
                                  onPressed: isActive || _startingServer
                                      ? (isActive ? _stopServer : null)
                                      : () => _startServer(model),
                                ),
                                const SizedBox(width: 6),
                                ToolIconButton(
                                  icon: Icons.delete,
                                  tooltip: 'Delete',
                                  onPressed: isActive
                                      ? null
                                      : () => _deleteModel(model),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCard(
                  context,
                  title: 'Download Presets',
                  child: ListView.separated(
                    itemCount: kModelPresets.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final preset = kModelPresets[index];
                      final installed = _isPresetInstalled(preset);
                      final downloading = _downloadingPreset == preset;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      preset.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_presetSize(preset)} · ${preset.description}',
                                      style: mutedToolTextStyle(context),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ToolButton(
                                label: installed ? 'Installed' : 'Download',
                                onPressed: installed || downloading
                                    ? null
                                    : () => _downloadPreset(preset),
                              ),
                            ],
                          ),
                          if (downloading)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: LinearProgressIndicator(
                                value: _downloadProgress,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Chat history section
        Expanded(
          child: Container(
            decoration: toolSurfaceDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Conversation',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Tokens', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          SmallDropdown(
                            items: const ['128', '256', '512', '1024', '2048'],
                            initialValue: '$_maxTokens',
                            onChanged: (value) =>
                                setState(() => _maxTokens = int.parse(value)),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Temp', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          SmallDropdown(
                            items: const [
                              '0.2',
                              '0.4',
                              '0.6',
                              '0.7',
                              '0.8',
                              '1.0',
                            ],
                            initialValue: _temperature.toStringAsFixed(1),
                            onChanged: (value) => setState(
                              () => _temperature = double.parse(value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      ToolIconButton(
                        icon: Icons.delete_outline,
                        tooltip: 'Clear history',
                        onPressed: _messages.isEmpty ? null : _clearHistory,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Messages list
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Text(
                            _service.isReady
                                ? 'Start a conversation...'
                                : 'Start a model to begin chatting',
                            style: mutedToolTextStyle(context),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isUser = msg.role == 'user';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: isUser
                                          ? appColors.success
                                          : const Color(0xFF6B7280),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      isUser ? Icons.person : Icons.smart_toy,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isUser ? 'You' : 'Assistant',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: appColors.mutedText,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          msg.content.isEmpty &&
                                                  !isUser &&
                                                  _generating
                                              ? '...'
                                              : msg.content,
                                          style: const TextStyle(
                                            fontFamily: 'Menlo',
                                            fontSize: 12,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Input section
        Container(
          decoration: toolSurfaceDecoration(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _ChatInputField(
                  controller: _prompt,
                  onSubmit: _run,
                  enabled: _service.isReady,
                ),
              ),
              if (_generating)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: IconButton(
                    icon: Icon(Icons.stop, color: appColors.error),
                    tooltip: 'Stop',
                    onPressed: _stopGeneration,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: IconButton(
                    icon: Icon(Icons.send, color: appColors.success),
                    tooltip: 'Send',
                    onPressed: _service.isReady ? _run : null,
                  ),
                ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: errorToolTextStyle(context)),
        ],
      ],
    );
  }
}

Widget buildOfflineLlm() {
  return const _OfflineLlmView();
}
