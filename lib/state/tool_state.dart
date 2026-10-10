import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'workspace_state.dart';

class ToolState {
  ToolState._({
    required this.selectedToolId,
    required this.searchQuery,
    required this.favorites,
    required this.darkMode,
    required this.colorTheme,
    required this.sidebarWidth,
    required this.workspace,
    SharedPreferences? prefs,
  }) : _prefs = prefs {
    final prefs = _prefs;
    if (prefs != null) {
      selectedToolId.addListener(() {
        prefs.setString('selectedToolId', selectedToolId.value);
      });
      searchQuery.addListener(() {
        prefs.setString('searchQuery', searchQuery.value);
      });
      favorites.addListener(() {
        prefs.setStringList('favorites', favorites.value.toList());
      });
      darkMode.addListener(() {
        prefs.setBool('darkMode', darkMode.value);
      });
      colorTheme.addListener(() {
        prefs.setString('colorTheme', colorTheme.value);
      });
      sidebarWidth.addListener(() {
        prefs.setDouble('sidebarWidth', sidebarWidth.value);
      });
    }
  }

  final SharedPreferences? _prefs;

  final ValueNotifier<String> selectedToolId;
  final ValueNotifier<String> searchQuery;
  final ValueNotifier<Set<String>> favorites;
  final ValueNotifier<bool> darkMode;
  final ValueNotifier<String> colorTheme;
  final ValueNotifier<double> sidebarWidth;
  final WorkspaceState workspace;

  void toggleFavorite(String toolId) {
    final current = Set<String>.from(favorites.value);
    if (current.contains(toolId)) {
      current.remove(toolId);
    } else {
      current.add(toolId);
    }
    favorites.value = current;
  }

  static Future<ToolState> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ToolState._(
      selectedToolId: ValueNotifier<String>(
        prefs.getString('selectedToolId') ?? 'unix_time_converter',
      ),
      searchQuery: ValueNotifier<String>(prefs.getString('searchQuery') ?? ''),
      favorites: ValueNotifier<Set<String>>(
        prefs.getStringList('favorites')?.toSet() ?? <String>{},
      ),
      darkMode: ValueNotifier<bool>(prefs.getBool('darkMode') ?? false),
      colorTheme: ValueNotifier<String>(
        prefs.getString('colorTheme') ?? 'Sandstone',
      ),
      sidebarWidth: ValueNotifier<double>(
        _normalizeSidebarWidth(prefs.getDouble('sidebarWidth') ?? 250),
      ),
      workspace: WorkspaceState.load(prefs),
      prefs: prefs,
    );
  }

  factory ToolState.inMemory() {
    return ToolState._(
      selectedToolId: ValueNotifier<String>('unix_time_converter'),
      searchQuery: ValueNotifier<String>(''),
      favorites: ValueNotifier<Set<String>>(<String>{}),
      darkMode: ValueNotifier<bool>(false),
      colorTheme: ValueNotifier<String>('Sandstone'),
      sidebarWidth: ValueNotifier<double>(250),
      workspace: WorkspaceState.inMemory(),
    );
  }
}

double _normalizeSidebarWidth(double value) {
  return value.clamp(64, 420).toDouble();
}
