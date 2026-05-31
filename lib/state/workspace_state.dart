import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../registry/tool_registry.dart';

enum PanelDockMode { floating, left, right, maximized, tiled }

class ToolInstance {
  const ToolInstance({
    required this.instanceId,
    required this.toolId,
    required this.title,
    required this.bounds,
    required this.dockMode,
    required this.zIndex,
    required this.isMinimized,
    required this.createdAt,
  });

  final String instanceId;
  final String toolId;
  final String title;
  final Rect bounds;
  final PanelDockMode dockMode;
  final int zIndex;
  final bool isMinimized;
  final DateTime createdAt;

  ToolInstance copyWith({
    String? title,
    Rect? bounds,
    PanelDockMode? dockMode,
    int? zIndex,
    bool? isMinimized,
  }) {
    return ToolInstance(
      instanceId: instanceId,
      toolId: toolId,
      title: title ?? this.title,
      bounds: bounds ?? this.bounds,
      dockMode: dockMode ?? this.dockMode,
      zIndex: zIndex ?? this.zIndex,
      isMinimized: isMinimized ?? this.isMinimized,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'instanceId': instanceId,
      'toolId': toolId,
      'title': title,
      'left': bounds.left,
      'top': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
      'dockMode': dockMode.name,
      'zIndex': zIndex,
      'isMinimized': isMinimized,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static ToolInstance? fromJson(Map<String, Object?> json) {
    final instanceId = json['instanceId'] as String?;
    final toolId = json['toolId'] as String?;
    if (instanceId == null ||
        toolId == null ||
        ToolRegistry.byId(toolId) == null) {
      return null;
    }
    final dockModeName =
        json['dockMode'] as String? ?? PanelDockMode.floating.name;
    final dockMode = PanelDockMode.values.firstWhere(
      (value) => value.name == dockModeName,
      orElse: () => PanelDockMode.floating,
    );
    final left = _number(json['left'], 32);
    final top = _number(json['top'], 32);
    final width = _number(json['width'], 760);
    final height = _number(json['height'], 560);
    return ToolInstance(
      instanceId: instanceId,
      toolId: toolId,
      title: json['title'] as String? ?? ToolRegistry.defaultPanelTitle(toolId),
      bounds: Rect.fromLTWH(left, top, width, height),
      dockMode: dockMode,
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 1,
      isMinimized: json['isMinimized'] == true,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static double _number(Object? value, double fallback) {
    return value is num ? value.toDouble() : fallback;
  }
}

class WorkspaceState {
  WorkspaceState._({
    required this.panels,
    required this.focusedPanelId,
    SharedPreferences? prefs,
  }) : _prefs = prefs {
    _nextZIndex = panels.value.fold<int>(
      0,
      (max, panel) => panel.zIndex > max ? panel.zIndex : max,
    );
    _nextInstanceNumber = panels.value.length + 1;
    if (prefs != null) {
      panels.addListener(_persistPanels);
      focusedPanelId.addListener(_persistFocusedPanel);
    }
  }

  static const double minPanelWidth = 480;
  static const double minPanelHeight = 280;
  static const double minTiledPanelWidth = 280;
  static const double minTiledPanelHeight = 220;
  static const double defaultPanelWidth = 760;
  static const double defaultPanelHeight = 580;

  final SharedPreferences? _prefs;
  final ValueNotifier<List<ToolInstance>> panels;
  final ValueNotifier<String?> focusedPanelId;

  int _nextInstanceNumber = 1;
  int _nextZIndex = 0;
  Size? _lastCanvasSize;

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
        : null;
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
    for (final panel in panels.value) {
      if (panel.instanceId == focused) return panel;
    }
    return null;
  }

  ToolInstance? panelById(String id) {
    for (final panel in panels.value) {
      if (panel.instanceId == id) return panel;
    }
    return null;
  }

  ToolInstance openTool(String toolId, {bool forceNew = false}) {
    if (!forceNew) {
      for (final panel in panels.value) {
        if (panel.toolId == toolId) {
          if (panel.isMinimized) {
            restorePanel(panel.instanceId);
          } else {
            focusPanel(panel.instanceId);
          }
          return panelById(panel.instanceId) ?? panel;
        }
      }
    }

    final tool = ToolRegistry.byId(toolId);
    if (tool == null) {
      throw ArgumentError.value(toolId, 'toolId', 'Unknown tool');
    }

    final offset = (panels.value.length % 6) * 34.0;
    // Size new panels to a fraction of the current canvas so there's always
    // room to drag them in both axes (a panel as tall as the canvas can only
    // slide horizontally). Falls back to the default size before the canvas
    // has been measured.
    final canvas = _lastCanvasSize;
    var width = defaultPanelWidth;
    var height = defaultPanelHeight;
    if (canvas != null && canvas.width > 0 && canvas.height > 0) {
      final fitWidth = canvas.width * 0.82;
      final fitHeight = canvas.height * 0.72;
      width = (fitWidth < defaultPanelWidth ? fitWidth : defaultPanelWidth)
          .clamp(minPanelWidth, defaultPanelWidth)
          .toDouble();
      height = (fitHeight < defaultPanelHeight ? fitHeight : defaultPanelHeight)
          .clamp(minPanelHeight, defaultPanelHeight)
          .toDouble();
    }
    final instance = ToolInstance(
      instanceId:
          'tool-${DateTime.now().microsecondsSinceEpoch}-${_nextInstanceNumber++}',
      toolId: tool.id,
      title: ToolRegistry.defaultPanelTitle(tool.id),
      bounds: Rect.fromLTWH(28 + offset, 28 + offset, width, height),
      dockMode: PanelDockMode.floating,
      zIndex: ++_nextZIndex,
      isMinimized: false,
      createdAt: DateTime.now(),
    );
    panels.value = [...panels.value, instance];
    focusedPanelId.value = instance.instanceId;
    return instance;
  }

  ToolInstance? duplicateFocusedPanel() {
    final source = focusedPanel;
    if (source == null) return null;
    final duplicate = ToolInstance(
      instanceId:
          'tool-${DateTime.now().microsecondsSinceEpoch}-${_nextInstanceNumber++}',
      toolId: source.toolId,
      title: source.title,
      bounds: source.bounds.shift(const Offset(28, 28)),
      dockMode: PanelDockMode.floating,
      zIndex: ++_nextZIndex,
      isMinimized: false,
      createdAt: DateTime.now(),
    );
    panels.value = [...panels.value, duplicate];
    focusedPanelId.value = duplicate.instanceId;
    return duplicate;
  }

  void focusPanel(String id) {
    final current = panelById(id);
    if (current == null) return;
    final updated = current.copyWith(zIndex: ++_nextZIndex, isMinimized: false);
    final nextPanels = [
      for (final panel in panels.value)
        if (panel.instanceId == id) updated else panel,
    ];
    panels.value = current.isMinimized
        ? _reflowDockedPanelsIfPossible(nextPanels)
        : nextPanels;
    focusedPanelId.value = id;
  }

  void closePanel(String id) {
    final current = panelById(id);
    final nextPanels = _reflowDockedPanelsIfPossible(
      panels.value.where((panel) => panel.instanceId != id).toList(),
    );
    panels.value = nextPanels;
    if (focusedPanelId.value == id) {
      focusedPanelId.value = _nextFocusCandidate(
        nextPanels,
        preferredDockMode: current?.dockMode,
      );
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

  void minimizePanel(String id) {
    final current = panelById(id);
    final nextPanels = [
      for (final panel in panels.value)
        if (panel.instanceId == id)
          panel.copyWith(isMinimized: true)
        else
          panel,
    ];
    panels.value = _reflowDockedPanelsIfPossible(nextPanels);
    if (focusedPanelId.value == id) {
      focusedPanelId.value = _nextFocusCandidate(
        nextPanels,
        preferredDockMode: current?.dockMode,
      );
    }
  }

  void restorePanel(String id) {
    final current = panelById(id);
    if (current == null) return;
    final updated = current.copyWith(zIndex: ++_nextZIndex, isMinimized: false);
    final nextPanels = [
      for (final panel in panels.value)
        if (panel.instanceId == id) updated else panel,
    ];
    panels.value = _reflowDockedPanelsIfPossible(nextPanels);
    focusedPanelId.value = id;
  }

  void updateBounds(String id, Rect bounds) {
    final current = panelById(id);
    if (current == null) return;
    final normalized = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.width.clamp(minPanelWidth, double.infinity),
      bounds.height.clamp(minPanelHeight, double.infinity),
    );
    final nextPanels = [
      for (final panel in panels.value)
        if (panel.instanceId == id)
          panel.copyWith(bounds: normalized, dockMode: PanelDockMode.floating)
        else
          panel,
    ];
    panels.value = _isSideDocked(current)
        ? _reflowDockedPanelsIfPossible(nextPanels)
        : nextPanels;
  }

  void snapPanel(String id, PanelDockMode mode, Size canvasSize) {
    _lastCanvasSize = canvasSize;
    final current = panelById(id);
    if (current == null) return;
    final padding = 14.0;
    final top = padding;
    final height = (canvasSize.height - padding * 2).clamp(
      minPanelHeight,
      double.infinity,
    );
    final halfWidth = ((canvasSize.width - padding * 3) / 2).clamp(
      minPanelWidth,
      double.infinity,
    );
    Rect bounds;
    switch (mode) {
      case PanelDockMode.left:
        bounds = Rect.fromLTWH(padding, top, halfWidth, height);
      case PanelDockMode.right:
        bounds = Rect.fromLTWH(
          canvasSize.width - halfWidth - padding,
          top,
          halfWidth,
          height,
        );
      case PanelDockMode.maximized:
        bounds = Rect.fromLTWH(
          padding,
          top,
          (canvasSize.width - padding * 2).clamp(
            minPanelWidth,
            double.infinity,
          ),
          height,
        );
      case PanelDockMode.floating:
        bounds = current.bounds;
      case PanelDockMode.tiled:
        bounds = current.bounds;
    }
    final updated = current.copyWith(
      bounds: bounds,
      dockMode: mode,
      zIndex: ++_nextZIndex,
      isMinimized: false,
    );
    final nextPanels = [
      for (final panel in panels.value)
        if (panel.instanceId == id) updated else panel,
    ];
    panels.value = _reflowDockedPanels(nextPanels, canvasSize);
    focusedPanelId.value = id;
  }

  void tileVisiblePanels(Size canvasSize) {
    _lastCanvasSize = canvasSize;
    final visible = panels.value.where((panel) => !panel.isMinimized).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (visible.isEmpty) return;
    if (visible.length == 1) {
      snapPanel(visible.first.instanceId, PanelDockMode.maximized, canvasSize);
      return;
    }

    const padding = 14.0;
    const gap = 10.0;
    final availableWidth = (canvasSize.width - padding * 2).clamp(
      minTiledPanelWidth,
      double.infinity,
    );
    final availableHeight = (canvasSize.height - padding * 2).clamp(
      minTiledPanelHeight,
      double.infinity,
    );
    final layout = _bestTileLayout(
      visible.length,
      availableWidth.toDouble(),
      availableHeight.toDouble(),
      gap,
    );
    final columns = layout.columns;
    final rows = layout.rows;
    final cellWidth = (availableWidth - gap * (columns - 1)) / columns;
    final cellHeight = (availableHeight - gap * (rows - 1)) / rows;
    final tiledBounds = <String, Rect>{};

    for (var i = 0; i < visible.length; i++) {
      final row = i ~/ columns;
      final column = i % columns;
      final left = padding + column * (cellWidth + gap);
      final top = padding + row * (cellHeight + gap);
      tiledBounds[visible[i].instanceId] = Rect.fromLTWH(
        left,
        top,
        cellWidth,
        cellHeight,
      );
    }

    panels.value = [
      for (final panel in panels.value)
        if (tiledBounds.containsKey(panel.instanceId))
          panel.copyWith(
            bounds: tiledBounds[panel.instanceId],
            dockMode: PanelDockMode.tiled,
          )
        else
          panel,
    ];
    focusedPanelId.value ??= visible.last.instanceId;
  }

  void updateCanvasSize(Size canvasSize) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;
    final previous = _lastCanvasSize;
    _lastCanvasSize = canvasSize;
    if (previous == canvasSize) return;
    panels.value = _reflowDockedPanels(panels.value, canvasSize);
  }

  ({int columns, int rows}) _bestTileLayout(
    int count,
    double width,
    double height,
    double gap,
  ) {
    var bestColumns = 1;
    var bestRows = count;
    var bestScore = double.infinity;
    const targetAspect = 1.35;

    for (var columns = 1; columns <= count; columns++) {
      final rows = (count / columns).ceil();
      final cellWidth = (width - gap * (columns - 1)) / columns;
      final cellHeight = (height - gap * (rows - 1)) / rows;
      if (cellWidth <= 0 || cellHeight <= 0) continue;

      final aspectScore = ((cellWidth / cellHeight) - targetAspect).abs();
      final widthPenalty = cellWidth < minTiledPanelWidth
          ? (minTiledPanelWidth - cellWidth) / minTiledPanelWidth
          : 0.0;
      final heightPenalty = cellHeight < minTiledPanelHeight
          ? (minTiledPanelHeight - cellHeight) / minTiledPanelHeight
          : 0.0;
      final emptyCells = columns * rows - count;
      final score =
          aspectScore + widthPenalty * 3 + heightPenalty * 3 + emptyCells * .15;

      if (score < bestScore) {
        bestScore = score;
        bestColumns = columns;
        bestRows = rows;
      }
    }

    return (columns: bestColumns, rows: bestRows);
  }

  bool _isSideDocked(ToolInstance panel) {
    return panel.dockMode == PanelDockMode.left ||
        panel.dockMode == PanelDockMode.right;
  }

  List<ToolInstance> _reflowDockedPanelsIfPossible(List<ToolInstance> source) {
    final canvasSize = _lastCanvasSize;
    return canvasSize == null
        ? source
        : _reflowDockedPanels(source, canvasSize);
  }

  List<ToolInstance> _reflowDockedPanels(
    List<ToolInstance> source,
    Size canvasSize,
  ) {
    final leftPanels = _visibleDockedPanels(source, PanelDockMode.left);
    final rightPanels = _visibleDockedPanels(source, PanelDockMode.right);
    if (leftPanels.isEmpty && rightPanels.isEmpty) return source;

    final boundsById = <String, Rect>{};
    _assignDockGroupBounds(
      panels: leftPanels,
      mode: PanelDockMode.left,
      canvasSize: canvasSize,
      boundsById: boundsById,
    );
    _assignDockGroupBounds(
      panels: rightPanels,
      mode: PanelDockMode.right,
      canvasSize: canvasSize,
      boundsById: boundsById,
    );

    return [
      for (final panel in source)
        if (boundsById.containsKey(panel.instanceId))
          panel.copyWith(bounds: boundsById[panel.instanceId])
        else
          panel,
    ];
  }

  List<ToolInstance> _visibleDockedPanels(
    List<ToolInstance> source,
    PanelDockMode mode,
  ) {
    return source
        .where((panel) => !panel.isMinimized && panel.dockMode == mode)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  void _assignDockGroupBounds({
    required List<ToolInstance> panels,
    required PanelDockMode mode,
    required Size canvasSize,
    required Map<String, Rect> boundsById,
  }) {
    if (panels.isEmpty) return;

    const padding = 14.0;
    final columnWidth = ((canvasSize.width - padding * 3) / 2)
        .clamp(minPanelWidth, double.infinity)
        .toDouble();
    final left = mode == PanelDockMode.left
        ? padding
        : canvasSize.width - columnWidth - padding;
    final height = (canvasSize.height - padding * 2)
        .clamp(minPanelHeight, double.infinity)
        .toDouble();
    final bounds = Rect.fromLTWH(left, padding, columnWidth, height);

    for (final panel in panels) {
      boundsById[panel.instanceId] = bounds;
    }
  }

  String? _nextFocusCandidate(
    List<ToolInstance> source, {
    PanelDockMode? preferredDockMode,
  }) {
    final visible = source.where((panel) => !panel.isMinimized).toList();
    if (visible.isEmpty) return null;

    if (preferredDockMode == PanelDockMode.left ||
        preferredDockMode == PanelDockMode.right) {
      final dockMatches = visible
          .where((panel) => panel.dockMode == preferredDockMode)
          .toList();
      if (dockMatches.isNotEmpty) {
        dockMatches.sort((a, b) => b.zIndex.compareTo(a.zIndex));
        return dockMatches.first.instanceId;
      }
    }

    visible.sort((a, b) => b.zIndex.compareTo(a.zIndex));
    return visible.first.instanceId;
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
