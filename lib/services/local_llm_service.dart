import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class LocalLLMService {
  LocalLLMService({
    Directory? modelDirectory,
    http.Client Function()? clientFactory,
  }) : _modelDirectory = modelDirectory,
       _clientFactory = clientFactory ?? http.Client.new;

  final Directory? _modelDirectory;
  final http.Client Function() _clientFactory;
  final Set<String> _downloads = {};

  Process? _serverProcess;
  final int _port = 8847;
  String? _currentModel;
  bool _isReady = false;

  bool get isReady => _isReady;
  String? get currentModel => _currentModel;
  int get port => _port;
  String get serverBinaryPath => _serverBinary;

  // Paths
  Future<String> get _modelsDir async {
    if (_modelDirectory != null) return _modelDirectory.path;
    final appSupport = await getApplicationSupportDirectory();
    return path.join(appSupport.path, 'models');
  }

  String get _serverBinary {
    return path.normalize(
      path.join(
        Platform.resolvedExecutable,
        '..',
        '..',
        'Resources',
        'llama-server',
        'llama-server',
      ),
    );
  }

  String get serverBundleDir => path.dirname(_serverBinary);

  // ============ Model Management ============

  Future<List<ModelInfo>> getAvailableModels() async {
    final dir = Directory(await _modelsDir);
    if (!await dir.exists()) return [];

    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gguf'))
        .map(
          (f) => ModelInfo(
            name: path.basenameWithoutExtension(f.path),
            path: f.path,
            size: File(f.path).lengthSync(),
          ),
        )
        .toList();
  }

  Future<void> downloadModel(
    ModelPreset preset,
    Function(double) onProgress,
  ) async {
    if (path.basename(preset.filename) != preset.filename ||
        !preset.filename.endsWith('.gguf')) {
      throw const FormatException('Choose a valid model filename.');
    }
    if (!_downloads.add(preset.filename)) {
      throw StateError('This model is already downloading.');
    }
    http.Client? client;
    IOSink? sink;
    File? temporary;
    try {
      final dir = Directory(await _modelsDir);
      await dir.create(recursive: true);
      final output = File(path.join(dir.path, preset.filename));
      temporary = File(
        '${output.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );
      client = _clientFactory();
      final response = await client.send(
        http.Request('GET', Uri.parse(preset.url)),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          'Model download failed (HTTP ${response.statusCode}).',
        );
      }
      sink = temporary.openWrite();
      final header = <int>[];
      var received = 0;
      final total = response.contentLength;
      await for (final chunk in response.stream) {
        for (final byte in chunk) {
          if (header.length == 4) break;
          header.add(byte);
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(
          total == null || total == 0 ? 0 : (received / total).clamp(0, 1),
        );
      }
      await sink.close();
      sink = null;
      if (header.length != 4 ||
          ascii.decode(header, allowInvalid: true) != 'GGUF' ||
          (total != null && received != total)) {
        throw const FormatException(
          'The downloaded model is incomplete or is not a GGUF file.',
        );
      }
      await temporary.rename(output.path);
      temporary = null;
      onProgress(1);
    } finally {
      try {
        await sink?.close();
      } finally {
        try {
          client?.close();
          if (temporary != null && await temporary.exists()) {
            await temporary.delete();
          }
        } finally {
          _downloads.remove(preset.filename);
        }
      }
    }
  }

  Future<void> deleteModel(String modelPath) async {
    await File(modelPath).delete();
  }

  // ============ Server Management ============

  Future<void> startServer(String modelPath) async {
    if (_serverProcess != null) {
      await stopServer();
    }

    _currentModel = modelPath;

    final workingDir = path.dirname(_serverBinary);
    _serverProcess = await Process.start(
      _serverBinary,
      [
        '-m',
        modelPath,
        '--port',
        '$_port',
        '--host',
        '127.0.0.1',
        '-c',
        '2048',
        '-ngl',
        '999',
        '--log-disable',
      ],
      workingDirectory: workingDir,
      environment: {'DYLD_LIBRARY_PATH': workingDir},
    );

    await _waitForServer();
    _isReady = true;
  }

  Future<void> _waitForServer() async {
    for (var i = 0; i < 30; i++) {
      try {
        final response = await http.get(
          Uri.parse('http://127.0.0.1:$_port/health'),
        );
        if (response.statusCode == 200) return;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw Exception('Server failed to start');
  }

  Future<void> stopServer() async {
    _serverProcess?.kill();
    _serverProcess = null;
    _isReady = false;
  }

  // ============ Inference ============

  /// Generate a response from a list of messages (chat history).
  /// Each message should have 'role' ('user' or 'assistant') and 'content'.
  Stream<String> generateChat(
    List<Map<String, String>> messages, {
    int maxTokens = 512,
    double temperature = 0.7,
  }) async* {
    if (!_isReady) throw Exception('Server not running');

    final request = http.Request(
      'POST',
      Uri.parse('http://127.0.0.1:$_port/v1/chat/completions'),
    );

    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream': true,
    });

    final client = _clientFactory();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('Generation failed (HTTP ${response.statusCode}).');
      }
      yield* decodeChatEvents(response.stream);
    } finally {
      client.close();
    }
  }

  /// Network chunks do not align with SSE lines or UTF-8 character boundaries.
  static Stream<String> decodeChatEvents(Stream<List<int>> bytes) async* {
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data == '[DONE]') return;
      Map<String, dynamic> event;
      try {
        event = jsonDecode(data) as Map<String, dynamic>;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
      final choices = event['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        continue;
      }
      final choice = choices.first as Map;
      final delta = choice['delta'];
      final content = delta is Map ? delta['content'] : null;
      if (content is String) yield content;
      if (choice['finish_reason'] != null) return;
    }
  }

  /// Simple single-prompt generation (wraps generateChat)
  Stream<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    return generateChat(
      [
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  Future<String> complete(String prompt) async {
    final buffer = StringBuffer();
    await for (final chunk in generate(prompt)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }
}

class ModelInfo {
  final String name;
  final String path;
  final int size;

  ModelInfo({required this.name, required this.path, required this.size});

  String get sizeFormatted {
    if (size > 1e9) return '${(size / 1e9).toStringAsFixed(1)} GB';
    return '${(size / 1e6).toStringAsFixed(0)} MB';
  }
}

class ModelPreset {
  final String name;
  final String filename;
  final String url;
  final int sizeBytes;
  final String description;

  const ModelPreset({
    required this.name,
    required this.filename,
    required this.url,
    required this.sizeBytes,
    required this.description,
  });
}

const kModelPresets = [
  ModelPreset(
    name: 'SmolLM 360M',
    filename: 'smollm2-360m-instruct-q8_0.gguf',
    url:
        'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf',
    sizeBytes: 420 * 1024 * 1024,
    description: 'Tiny & fast. Good for simple tasks.',
  ),
  ModelPreset(
    name: 'Qwen2.5 0.5B',
    filename: 'qwen2.5-0.5b-q4.gguf',
    url:
        'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
    sizeBytes: 400 * 1024 * 1024,
    description: 'Great balance of size and capability.',
  ),
  ModelPreset(
    name: 'Qwen2.5 1.5B',
    filename: 'qwen2.5-1.5b-q4.gguf',
    url:
        'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    sizeBytes: 900 * 1024 * 1024,
    description: 'Solid all-rounder for most tasks.',
  ),
  ModelPreset(
    name: 'Phi-3 Mini',
    filename: 'phi-3-mini-q4.gguf',
    url:
        'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf',
    sizeBytes: 2200 * 1024 * 1024,
    description: 'Most capable. Best for coding tasks.',
  ),
];
