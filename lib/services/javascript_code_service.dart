import 'package:flutter/services.dart';

/// Parses JS/TS with a bundled compiler using macOS JavaScriptCore.
/// User source is an argument to the parser, never an evaluated script.
class JavascriptCodeService {
  static const _channel = MethodChannel('devutils/javascript_code');
  static Future<void>? _ready;

  static Future<void> _initialize() async {
    final assets = await Future.wait([
      rootBundle.loadString('assets/javascript/typescript-5.9.3.js'),
      rootBundle.loadString('assets/javascript/tool-code-engine.js'),
      rootBundle.loadString('assets/javascript/formatter-vendors.js'),
    ]);
    await _channel.invokeMethod<void>('initialize', {
      'compiler': assets[0],
      'engine': '${assets[2]}\n${assets[1]}',
    });
  }

  static Future<String> process(
    String source,
    String operation, {
    String indentation = '2 spaces',
  }) async {
    if (source.trim().isEmpty) return '';
    try {
      await (_ready ??= _initialize());
    } catch (_) {
      _ready = null;
      rethrow;
    }
    final result = await _channel.invokeMapMethod<String, dynamic>('process', {
      'source': source,
      'operation': operation,
      'indentation': indentation,
    });
    if (result == null || result['output'] is! String) {
      throw const FormatException('The code parser returned no result.');
    }
    if (operation == 'Obfuscate' && result['valid'] == false) {
      throw FormatException(result['output'] as String);
    }
    return result['output'] as String;
  }
}
