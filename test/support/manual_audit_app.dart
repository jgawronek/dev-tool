import 'package:flutter/material.dart';
import 'package:dev_tool/app.dart';
import 'package:dev_tool/state/tool_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = ToolState.inMemory();
  state.workspace.openTool('file_checksum');
  runApp(DevToolApp(state: state));
}
