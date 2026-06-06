import 'package:flutter/material.dart';

import 'state/tool_state.dart';
import 'state/tool_state_scope.dart';
import 'ui/app_colors.dart';
import 'ui/main_shell.dart';

class DevToolApp extends StatelessWidget {
  const DevToolApp({super.key, required this.state});

  final ToolState state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: state.darkMode,
      builder: (context, darkMode, _) {
        return ValueListenableBuilder<String>(
          valueListenable: state.colorTheme,
          builder: (context, colorTheme, _) {
            return MaterialApp(
              title: 'DevUtils',
              theme: _buildLightTheme(colorTheme),
              darkTheme: _buildDarkTheme(colorTheme),
              themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
              home: ToolStateScope(
                state: state,
                child: MainShell(state: state),
              ),
            );
          },
        );
      },
    );
  }
}

ThemeData _buildLightTheme(String colorTheme) {
  final colors = AppColors.lightForTheme(colorTheme);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: Brightness.light,
      surface: colors.canvas,
    ),
    scaffoldBackgroundColor: colors.canvas,
    cardColor: colors.panel,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 12, color: Color(0xFF1F2328)),
      titleMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1F2328),
      ),
    ),
    iconTheme: const IconThemeData(color: Color(0xFF3E3E3E)),
    dividerColor: colors.border,
    inputDecorationTheme: _inputDecorationTheme(colors),
    listTileTheme: _listTileTheme(colors, Brightness.light),
    extensions: [colors],
  );
}

ThemeData _buildDarkTheme(String colorTheme) {
  final colors = AppColors.darkForTheme(colorTheme);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: Brightness.dark,
      surface: colors.canvas,
    ),
    scaffoldBackgroundColor: colors.canvas,
    cardColor: colors.panel,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 12, color: Color(0xFFE7EDF3)),
      titleMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFFE7EDF3),
      ),
    ),
    iconTheme: const IconThemeData(color: Color(0xFFC9D4DE)),
    dividerColor: colors.border,
    inputDecorationTheme: _inputDecorationTheme(colors),
    listTileTheme: _listTileTheme(colors, Brightness.dark),
    extensions: [colors],
  );
}

InputDecorationTheme _inputDecorationTheme(AppColors colors) {
  return InputDecorationTheme(
    filled: true,
    fillColor: colors.panelElevated,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    hintStyle: TextStyle(color: colors.mutedText),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.accent),
    ),
  );
}

ListTileThemeData _listTileTheme(AppColors colors, Brightness brightness) {
  return ListTileThemeData(
    selectedColor: brightness == Brightness.dark
        ? colors.editorText
        : colors.accent,
    selectedTileColor: colors.selected,
    iconColor: brightness == Brightness.dark
        ? const Color(0xFFC9D4DE)
        : const Color(0xFF4A4A4A),
    textColor: colors.editorText,
    dense: true,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
