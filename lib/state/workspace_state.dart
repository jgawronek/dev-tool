import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../registry/tool_registry.dart';

/// One open tool tab in the workspace.
class ToolInstance {
  const ToolInstance({
    required this.instanceId,
    required this.toolId,
    required this.title,
    required this.createdAt,
  });

  final String instanceId;
  final String toolId;
  final String title;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return {
      'instanceId': instanceId,
      'toolId': toolId,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Accepts the legacy floating-panel schema (bounds, zIndex, dockMode,
  /// isMinimized) and ignores it, so saved sessions migrate silently to tabs.
  static ToolInstance? fromJson(Map<String, Object?> json) {
    final instanceId = json['instanceId'] as String?;
    final toolId = json['toolId'] as String?;
    if (instanceId == null ||
        toolId == null ||
        ToolRegistry.byId(toolId) == null) {
      return null;
    }
    return ToolInstance(
      instanceId: instanceId,
      toolId: toolId,
      title: json['title'] as String? ?? ToolRegistry.defaultPanelTitle(toolId),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class WorkspaceState {
  WorkspaceState._({
    required this.panels,
    required this.focusedPanelId,
    SharedPreferences? prefs,
  }) : _prefs = prefs {
    _nextInstanceNumber = panels.value.length + 1;
    if (prefs != null) {
      panels.addListener(_persistPanels);
      focusedPanelId.addListener(_persistFocusedPanel);
    }
  }

  final SharedPreferences? _prefs;

  /// Open tools, in tab order.
  final ValueNotifier<List<ToolInstance>> panels;

  /// The active tab's instance id.
  final ValueNotifier<String?> focusedPanelId;

  int _nextInstanceNumber = 1;

  static WorkspaceState load(SharedPreferences prefs) {
    final persisted = prefs.getString('workspacePanels');
    final panels = <ToolInstance>[];
    if (persisted != null && persisted.isNotEmpty) {
      try {
        final decoded = jsonDecode(persisted);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final panel = ToolInstance.fromJson(
                Map<String, Object?>.from(item),
              );
              if (panel != null) panels.add(panel);
            }
          }
        }
      } catch (_) {}
    }
    final focused = prefs.getString('workspaceFocusedPanelId');
    final validFocused = panels.any((panel) => panel.instanceId == focused)
        ? focused
        : (panels.isNotEmpty ? panels.last.instanceId : null);
    return WorkspaceState._(
      panels: ValueNotifier<List<ToolInstance>>(panels),
      focusedPanelId: ValueNotifier<String?>(validFocused),
      prefs: prefs,
    );
  }

  factory WorkspaceState.inMemory() {
    return WorkspaceState._(
      panels: ValueNotifier<List<ToolInstance>>(<ToolInstance>[]),
      focusedPanelId: ValueNotifier<String?>(null),
    );
  }

  ToolInstance? get focusedPanel {
    final focused = focusedPanelId.value;
    if (focused == null) return null;
    return panelById(focused);
  }

  ToolInstance? panelById(String id) {
    for (final panel in panels.value) {
      if (panel.instanceId == id) return panel;
    }
    return null;
  }

  /// Focuses the tab showing [toolId], or opens a new one. [forceNew] always
  /// adds a fresh tab (e.g. a second JSON session to compare against).
  ToolInstance openTool(String toolId, {bool forceNew = false}) {
    if (!forceNew) {
      for (final panel in panels.value) {
        if (panel.toolId == toolId) {
          focusPanel(panel.instanceId);
          return panel;
        }
      }
    }

    final tool = ToolRegistry.byId(toolId);
    if (tool == null) {
      throw ArgumentError.value(toolId, 'toolId', 'Unknown tool');
    }

    final instance = ToolInstance(
      instanceId:
          'tool-${DateTime.now().microsecondsSinceEpoch}-${_nextInstanceNumber++}',
      toolId: tool.id,
      title: ToolRegistry.defaultPanelTitle(tool.id),
      createdAt: DateTime.now(),
    );
    panels.value = [...panels.value, instance];
    focusedPanelId.value = instance.instanceId;
    return instance;
  }

  /// Switches to the tab with [id].
  void focusPanel(String id) {
    if (panelById(id) == null) return;
    focusedPanelId.value = id;
  }

  void closePanel(String id) {
    final current = panels.value;
    final index = current.indexWhere((panel) => panel.instanceId == id);
    if (index < 0) return;
    final nextPanels = [...current]..removeAt(index);
    panels.value = nextPanels;
    if (focusedPanelId.value == id) {
      if (nextPanels.isEmpty) {
        focusedPanelId.value = null;
      } else {
        focusedPanelId.value =
            nextPanels[index.clamp(0, nextPanels.length - 1)].instanceId;
      }
    }
  }

  void closeFocusedPanel() {
    final focused = focusedPanelId.value;
    if (focused != null) closePanel(focused);
  }

  void clearWorkspace() {
    panels.value = <ToolInstance>[];
    focusedPanelId.value = null;
  }

  /// Moves the tab with [id] by [delta] positions (negative = left).
  void movePanel(String id, int delta) {
    final current = [...panels.value];
    final index = current.indexWhere((panel) => panel.instanceId == id);
    if (index < 0) return;
    final target = (index + delta).clamp(0, current.length - 1);
    if (target == index) return;
    final panel = current.removeAt(index);
    current.insert(target, panel);
    panels.value = current;
  }

  /// Selects the tab before/after the active one, wrapping around.
  void selectAdjacent(int delta) {
    final current = panels.value;
    if (current.isEmpty) return;
    final focused = focusedPanelId.value;
    var index = current.indexWhere((panel) => panel.instanceId == focused);
    if (index < 0) index = delta > 0 ? -1 : 0;
    final next = (index + delta) % current.length;
    focusedPanelId.value =
        current[(next + current.length) % current.length].instanceId;
  }

  void _persistPanels() {
    final prefs = _prefs;
    if (prefs == null) return;
    prefs.setString(
      'workspacePanels',
      jsonEncode(panels.value.map((panel) => panel.toJson()).toList()),
    );
  }

  void _persistFocusedPanel() {
    final prefs = _prefs;
    if (prefs == null) return;
    final focused = focusedPanelId.value;
    if (focused == null) {
      prefs.remove('workspaceFocusedPanelId');
    } else {
      prefs.setString('workspaceFocusedPanelId', focused);
    }
  }
}