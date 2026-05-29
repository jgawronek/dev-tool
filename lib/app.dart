import 'package:flutter/material.dart';

import 'state/tool_state.dart';
import 'ui/main_shell.dart';

class DevToolApp extends StatelessWidget {
  const DevToolApp({super.key, required this.state});

  final ToolState state;

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFFF5F5F5);
    const sidebar = Color(0xFFE7E7E7);
    const accent = Color(0xFF3E5B6A);
    return MaterialApp(
      title: 'DevUtils',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
          surface: surface,
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F0F0),
        cardColor: Colors.white,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 13, color: Color(0xFF1F1F1F)),
          titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF3E3E3E)),
        dividerColor: const Color(0xFFD0D0D0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD0D0D0)),
          ),
        ),
        listTileTheme: ListTileThemeData(
          selectedColor: const Color(0xFF0E2C3C),
          selectedTileColor: const Color(0xFFD8E3EA),
          iconColor: const Color(0xFF4A4A4A),
          textColor: const Color(0xFF2B2B2B),
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        extensions: const [AppColors(sidebar: sidebar)],
      ),
      home: MainShell(state: state),
    );
  }
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.sidebar});

  final Color sidebar;

  @override
  AppColors copyWith({Color? sidebar}) {
    return AppColors(sidebar: sidebar ?? this.sidebar);
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(sidebar: Color.lerp(sidebar, other.sidebar, t) ?? sidebar);
  }
}
