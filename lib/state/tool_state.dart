import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ToolState {
  ToolState._({
    required this.selectedToolId,
    required this.searchQuery,
    required this.favorites,
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
    }
  }

  final SharedPreferences? _prefs;

  final ValueNotifier<String> selectedToolId;
  final ValueNotifier<String> searchQuery;
  final ValueNotifier<Set<String>> favorites;

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
      prefs: prefs,
    );
  }

  factory ToolState.inMemory() {
    return ToolState._(
      selectedToolId: ValueNotifier<String>('unix_time_converter'),
      searchQuery: ValueNotifier<String>(''),
      favorites: ValueNotifier<Set<String>>(<String>{}),
    );
  }
}
