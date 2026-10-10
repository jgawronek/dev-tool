import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.sidebar,
    required this.canvas,
    required this.panel,
    required this.panelHeader,
    required this.panelElevated,
    required this.border,
    required this.editorBackground,
    required this.editorText,
    required this.mutedText,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.error,
    required this.statusBar,
    required this.hover,
    required this.selected,
    required this.shadow,
  });

  final Color sidebar;
  final Color canvas;
  final Color panel;
  final Color panelHeader;
  final Color panelElevated;
  final Color border;
  final Color editorBackground;
  final Color editorText;
  final Color mutedText;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color error;
  final Color statusBar;
  final Color hover;
  final Color selected;
  final Color shadow;

  static const light = AppColors(
    sidebar: Color(0xFFE7E7E7),
    canvas: Color(0xFFF0F2F4),
    panel: Color(0xFFFFFFFF),
    panelHeader: Color(0xFFF7F8FA),
    panelElevated: Color(0xFFFFFFFF),
    border: Color(0xFFD0D6DC),
    editorBackground: Color(0xFFFFFFFF),
    editorText: Color(0xFF1F2328),
    mutedText: Color(0xFF66717C),
    accent: Color(0xFF3E6B7F),
    accentSoft: Color(0xFFD8E7EE),
    success: Color(0xFF2FA866),
    warning: Color(0xFFD18A00),
    error: Color(0xFFCF3F4A),
    statusBar: Color(0xFFE8ECEF),
    hover: Color(0xFFE1E9EE),
    selected: Color(0xFFD8E3EA),
    shadow: Color(0x33000000),
  );

  static const dark = AppColors(
    sidebar: Color(0xFF171B20),
    canvas: Color(0xFF0F1216),
    panel: Color(0xFF1C2229),
    panelHeader: Color(0xFF222932),
    panelElevated: Color(0xFF252D36),
    border: Color(0xFF343D48),
    editorBackground: Color(0xFF11161C),
    editorText: Color(0xFFE7EDF3),
    mutedText: Color(0xFF9CAAB8),
    accent: Color(0xFF6CB8D8),
    accentSoft: Color(0xFF1C3A49),
    success: Color(0xFF58C987),
    warning: Color(0xFFE3A72F),
    error: Color(0xFFFF6B78),
    statusBar: Color(0xFF151A20),
    hover: Color(0xFF26313B),
    selected: Color(0xFF244050),
    shadow: Color(0x99000000),
  );

  static const sandstone = AppColors(
    sidebar: Color(0xFFEDEAE5),
    canvas: Color(0xFFFCFBF9),
    panel: Color(0xFFFFFFFF),
    panelHeader: Color(0xFFF6F4F1),
    panelElevated: Color(0xFFFFFFFF),
    border: Color(0xFFDDD9D3),
    editorBackground: Color(0xFFFFFFFF),
    editorText: Color(0xFF202130),
    mutedText: Color(0xFF72717A),
    accent: Color(0xFFB65335),
    accentSoft: Color(0xFFF1E3DC),
    success: Color(0xFF35843D),
    warning: Color(0xFF976218),
    error: Color(0xFFB83D3D),
    statusBar: Color(0xFFF3F0EC),
    hover: Color(0xFFE8E2DA),
    selected: Color(0xFFE5D8CE),
    shadow: Color(0x18000000),
  );

  static const colorThemes = <AppColorThemeChoice>[
    AppColorThemeChoice(
      name: 'Sandstone',
      lightAccent: Color(0xFFB65335),
      lightAccentSoft: Color(0xFFF1E3DC),
      lightSelected: Color(0xFFE5D8CE),
      lightHover: Color(0xFFE8E2DA),
      darkAccent: Color(0xFFDF9878),
      darkAccentSoft: Color(0xFF49352C),
      darkSelected: Color(0xFF46372F),
      darkHover: Color(0xFF362C27),
    ),
    AppColorThemeChoice(
      name: 'Classic Blue',
      lightAccent: Color(0xFF3E6B7F),
      lightAccentSoft: Color(0xFFD8E7EE),
      lightSelected: Color(0xFFD8E3EA),
      lightHover: Color(0xFFE1E9EE),
      darkAccent: Color(0xFF6CB8D8),
      darkAccentSoft: Color(0xFF1C3A49),
      darkSelected: Color(0xFF244050),
      darkHover: Color(0xFF26313B),
    ),
    AppColorThemeChoice(
      name: 'Emerald',
      lightAccent: Color(0xFF2C7A55),
      lightAccentSoft: Color(0xFFD7EEE3),
      lightSelected: Color(0xFFD9E9E0),
      lightHover: Color(0xFFE1EFE7),
      darkAccent: Color(0xFF58C987),
      darkAccentSoft: Color(0xFF183B2A),
      darkSelected: Color(0xFF203F31),
      darkHover: Color(0xFF24382F),
    ),
    AppColorThemeChoice(
      name: 'Amber',
      lightAccent: Color(0xFF9A6216),
      lightAccentSoft: Color(0xFFF1E3C9),
      lightSelected: Color(0xFFECE0CD),
      lightHover: Color(0xFFF0E7D8),
      darkAccent: Color(0xFFE3A72F),
      darkAccentSoft: Color(0xFF3C2F18),
      darkSelected: Color(0xFF443821),
      darkHover: Color(0xFF363026),
    ),
    AppColorThemeChoice(
      name: 'Rose',
      lightAccent: Color(0xFF9F3E51),
      lightAccentSoft: Color(0xFFF2DCE1),
      lightSelected: Color(0xFFECDDE1),
      lightHover: Color(0xFFF1E4E7),
      darkAccent: Color(0xFFFF6B78),
      darkAccentSoft: Color(0xFF44212A),
      darkSelected: Color(0xFF4A2932),
      darkHover: Color(0xFF3B2830),
    ),
    AppColorThemeChoice(
      name: 'Violet',
      lightAccent: Color(0xFF6A5AA8),
      lightAccentSoft: Color(0xFFE5E1F3),
      lightSelected: Color(0xFFE1DFF0),
      lightHover: Color(0xFFE9E7F3),
      darkAccent: Color(0xFFA79BFF),
      darkAccentSoft: Color(0xFF302B4D),
      darkSelected: Color(0xFF373052),
      darkHover: Color(0xFF302D42),
    ),
  ];

  static List<String> get colorThemeNames {
    return [for (final theme in colorThemes) theme.name];
  }

  static AppColorThemeChoice colorThemeFor(String name) {
    return colorThemes.firstWhere(
      (theme) => theme.name == name,
      orElse: () => colorThemes.first,
    );
  }

  static AppColors lightForTheme(String name) {
    final theme = colorThemeFor(name);
    return (name == 'Sandstone' ? sandstone : light).copyWith(
      accent: theme.lightAccent,
      accentSoft: theme.lightAccentSoft,
      selected: theme.lightSelected,
      hover: theme.lightHover,
    );
  }

  static AppColors darkForTheme(String name) {
    final theme = colorThemeFor(name);
    return dark.copyWith(
      accent: theme.darkAccent,
      accentSoft: theme.darkAccentSoft,
      selected: theme.darkSelected,
      hover: theme.darkHover,
    );
  }

  @override
  AppColors copyWith({
    Color? sidebar,
    Color? canvas,
    Color? panel,
    Color? panelHeader,
    Color? panelElevated,
    Color? border,
    Color? editorBackground,
    Color? editorText,
    Color? mutedText,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? error,
    Color? statusBar,
    Color? hover,
    Color? selected,
    Color? shadow,
  }) {
    return AppColors(
      sidebar: sidebar ?? this.sidebar,
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      panelHeader: panelHeader ?? this.panelHeader,
      panelElevated: panelElevated ?? this.panelElevated,
      border: border ?? this.border,
      editorBackground: editorBackground ?? this.editorBackground,
      editorText: editorText ?? this.editorText,
      mutedText: mutedText ?? this.mutedText,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      statusBar: statusBar ?? this.statusBar,
      hover: hover ?? this.hover,
      selected: selected ?? this.selected,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      sidebar: Color.lerp(sidebar, other.sidebar, t) ?? sidebar,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      panel: Color.lerp(panel, other.panel, t) ?? panel,
      panelHeader: Color.lerp(panelHeader, other.panelHeader, t) ?? panelHeader,
      panelElevated:
          Color.lerp(panelElevated, other.panelElevated, t) ?? panelElevated,
      border: Color.lerp(border, other.border, t) ?? border,
      editorBackground:
          Color.lerp(editorBackground, other.editorBackground, t) ??
          editorBackground,
      editorText: Color.lerp(editorText, other.editorText, t) ?? editorText,
      mutedText: Color.lerp(mutedText, other.mutedText, t) ?? mutedText,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t) ?? accentSoft,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      error: Color.lerp(error, other.error, t) ?? error,
      statusBar: Color.lerp(statusBar, other.statusBar, t) ?? statusBar,
      hover: Color.lerp(hover, other.hover, t) ?? hover,
      selected: Color.lerp(selected, other.selected, t) ?? selected,
      shadow: Color.lerp(shadow, other.shadow, t) ?? shadow,
    );
  }
}

@immutable
class AppColorThemeChoice {
  const AppColorThemeChoice({
    required this.name,
    required this.lightAccent,
    required this.lightAccentSoft,
    required this.lightSelected,
    required this.lightHover,
    required this.darkAccent,
    required this.darkAccentSoft,
    required this.darkSelected,
    required this.darkHover,
  });

  final String name;
  final Color lightAccent;
  final Color lightAccentSoft;
  final Color lightSelected;
  final Color lightHover;
  final Color darkAccent;
  final Color darkAccentSoft;
  final Color darkSelected;
  final Color darkHover;
}

extension AppColorLookup on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}
