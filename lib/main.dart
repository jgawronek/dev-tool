import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/app_appearance_service.dart';
import 'state/tool_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await ToolState.load();
  runApp(DevToolApp(state: state));

  // Apply the saved status-bar / Dock preferences once the native method
  // channel is registered (after the first frame).
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final prefs = await SharedPreferences.getInstance();
    await AppAppearanceService.apply(
      showStatusBar: prefs.getBool('pref_show_status_bar') ?? true,
      showDock: prefs.getBool('pref_show_dock') ?? true,
    );
  });
}
