import 'package:flutter/rendering.dart';
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
      // When the native side reports drop coordinates (it always does), resolve
      // the target purely from those — the mouse pointer isn't tracked during
      // an OS drag, so `_activeTargetId` would be stale. Only fall back to the
      // active target when coordinates are unavailable.
      final hasCoordinates =
          args is Map && args['x'] is num && args['y'] is num;
      final targetId = hasCoordinates
          ? _targetIdForArguments(args)
          : _activeTargetId;
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

    // Primary: a real render-tree hit test. `result.path` is ordered front to
    // back, so the topmost (visually on top) panel under the point wins even
    // when panels overlap — fixing drops landing in an occluded panel.
    final views = RendererBinding.instance.renderViews;
    if (views.isNotEmpty) {
      final result = BoxHitTestResult();
      views.first.hitTest(result, position: position);
      for (final entry in result.path) {
        final entryTarget = entry.target;
        RenderObject? node = entryTarget is RenderObject ? entryTarget : null;
        while (node != null) {
          for (final candidate in _targets.entries) {
            final renderObject = candidate.value.key.currentContext
                ?.findRenderObject();
            if (renderObject != null && identical(renderObject, node)) {
              return candidate.key;
            }
          }
          final parent = node.parent;
          node = parent is RenderObject ? parent : null;
        }
      }
    }

    // Fallback: smallest containing rect (most specific) if hit testing missed.
    String? bestId;
    double bestArea = double.infinity;
    for (final entry in _targets.entries) {
      final renderObject = entry.value.key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.inflate(10).contains(position)) {
        final area = rect.width * rect.height;
        if (area < bestArea) {
          bestArea = area;
          bestId = entry.key;
        }
      }
    }
    return bestId;
  }
}

class _FileDropTarget {
  const _FileDropTarget({required this.key, required this.handler});

  final GlobalKey key;
  final FileDropHandler handler;
}
