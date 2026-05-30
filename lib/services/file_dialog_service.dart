import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class FileDialogService {
  FileDialogService._();

  static const MethodChannel _channel = MethodChannel('devutils/file_dialogs');

  static Future<String?> openFile({List<String> allowedExtensions = const []}) {
    return _invokePath('openFile', {'extensions': allowedExtensions});
  }

  static Future<String?> openDirectory() {
    return _invokePath('openDirectory');
  }

  static Future<String?> saveFile({
    String? suggestedName,
    String? directoryPath,
    List<String> allowedExtensions = const [],
  }) {
    return _invokePath('saveFile', {
      'suggestedName': suggestedName,
      'directoryPath': directoryPath,
      'extensions': allowedExtensions,
    });
  }

  static Future<String?> _invokePath(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    try {
      return await _channel.invokeMethod<String>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }
}

typedef FileDropHandler = void Function(List<String> paths);

class FileDropService {
  FileDropService._();

  static const MethodChannel _channel = MethodChannel('devutils/file_drop');
  static final Map<String, _FileDropTarget> _targets = {};
  static bool _initialized = false;
  static String? _activeTargetId;

  static void registerTarget(
    String targetId, {
    required GlobalKey key,
    required FileDropHandler handler,
  }) {
    _ensureInitialized();
    _targets[targetId] = _FileDropTarget(key: key, handler: handler);
  }

  static void unregisterTarget(String targetId) {
    _targets.remove(targetId);
    if (_activeTargetId == targetId) {
      _activeTargetId = null;
    }
  }

  static void setActiveTarget(String? targetId) {
    _activeTargetId = targetId;
  }

  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'filesDropped') return null;
      final args = call.arguments;
      final paths = _pathsFromArguments(args);
      if (paths.isEmpty) return null;
      final targetId = _targetIdForArguments(args) ?? _activeTargetId;
      if (targetId == null) return null;
      _targets[targetId]?.handler(paths);
      return null;
    });
  }

  static List<String> _pathsFromArguments(Object? arguments) {
    if (arguments is List) return arguments.whereType<String>().toList();
    if (arguments is Map) {
      final paths = arguments['paths'];
      if (paths is List) return paths.whereType<String>().toList();
    }
    return const <String>[];
  }

  static String? _targetIdForArguments(Object? arguments) {
    if (arguments is! Map) return null;
    final x = arguments['x'];
    final y = arguments['y'];
    if (x is! num || y is! num) return null;
    final position = Offset(x.toDouble(), y.toDouble());
    for (final entry in _targets.entries) {
      final context = entry.value.key.currentContext;
      if (context == null) continue;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.inflate(10).contains(position)) return entry.key;
    }
    return null;
  }
}

class _FileDropTarget {
  const _FileDropTarget({required this.key, required this.handler});

  final GlobalKey key;
  final FileDropHandler handler;
}
