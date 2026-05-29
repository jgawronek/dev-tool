import 'package:flutter/material.dart';

import 'app.dart';
import 'state/tool_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await ToolState.load();
  runApp(DevToolApp(state: state));
}
