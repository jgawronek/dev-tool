import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> runFormatterEngine(
  String source,
  String operation, [
  String indentation = '2 spaces',
]) {
  final executable =
      Platform.environment['DEVUTILS_FORMATTER_RUNNER'] ??
      '/private/tmp/devutils-formatter-engine-test';
  final native = File(executable).existsSync();
  final directory = Directory.systemTemp.createTempSync('formatter-input-');
  final input = File('${directory.path}/input.json')
    ..writeAsStringSync(
      jsonEncode({
        'source': source,
        'operation': operation,
        'indentation': indentation,
      }),
    );
  try {
    // Process.runSync has no stdin argument. The shell only redirects a local
    // JSON file; source code is never interpolated into a command.
    String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
    final command = native
        ? quote(executable)
        : 'node test/support/formatter_engine.cjs';
    final result = Process.runSync('/bin/sh', [
      '-c',
      '$command < ${quote(input.path)}',
    ]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}

void installFormatterChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('devutils/javascript_code'),
        (call) async {
          if (call.method == 'initialize') return null;
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          return runFormatterEngine(
            arguments['source'] as String,
            arguments['operation'] as String,
            arguments['indentation'] as String,
          );
        },
      );
}
