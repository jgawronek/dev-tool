import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dev_tool.dart';
import '../registry/tool_registry.dart';
import '../state/tool_state.dart';
import '../state/workspace_state.dart';
import 'app_colors.dart';
import 'tool_views.dart';
import 'widgets.dart';

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({super.key, required this.state});

  final ToolState state;

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  final Map<String, JsonToolSession> _jsonSessions = {};
  Size _canvasSize = const Size(1200, 800);

  WorkspaceState get _workspace => widget.state.workspace;

  @override
  void dispose() {
    for (final session in _jsonSessions.values) {
      session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () {
          _workspace.openTool(
            widget.state.selectedToolId.value,
            forceNew: true,
          );
        },
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
            _workspace.closeFocusedPanel,
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true, shift: true):
            _workspace.duplicateFocusedPanel,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _WorkspaceToolbar(state: widget.state, canvasSize: _canvasSize),
            Expanded(
              child: ValueListenableBuilder<List<ToolInstance>>(
                valueListenable: _workspace.panels,
                builder: (context, panels, _) {
                  _disposeRemovedJsonSessions(panels);
                  return ValueListenableBuilder<String?>(
                    valueListenable: _workspace.focusedPanelId,
                    builder: (context, focusedPanelId, _) {
                      final displayedPanels = _displayedWorkspacePanels(
                        panels,
                        focusedPanelId,
                      );
                      final jsonPair = _jsonComparePair(displayedPanels);
                      final jsonCompare = jsonPair == null
                          ? null
                          : compareJsonSessions(
                              _jsonSessionFor(jsonPair.first.instanceId),
                              _jsonSessionFor(jsonPair.last.instanceId),
                              JsonCompareMode.normalized,
                            );
                      final minimizedPanels = panels
                          .where((panel) => panel.isMinimized)
                          .toList();
                      final canvas = ValueListenableBuilder<Set<String>>(
                        valueListenable: widget.state.favorites,
                        builder: (context, favorites, _) => _WorkspaceCanvas(
                          panels: panels,
                          focusedPanelId: focusedPanelId,
                          jsonPair: jsonPair,
                          jsonCompare: jsonCompare,
                          onSizeChanged: (size) {
                            if (_canvasSize != size) {
                              setState(() => _canvasSize = size);
                            }
                            _workspace.updateCanvasSize(size);
                          },
                          onOpenTool: (id) {
                            widget.state.selectedToolId.value = id;
                            _workspace.openTool(id);
                          },
                          onBuildTool: _buildToolContent,
                          workspace: _workspace,
                          favorites: favorites,
                          onToggleFavorite: widget.state.toggleFavorite,
                        ),
                      );
                      return Column(
                        children: [
                          Expanded(child: canvas),
                          if (minimizedPanels.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                              child: _MinimizedDock(
                                panels: minimizedPanels,
                                onRestore: _workspace.restorePanel,
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            _WorkspaceStatusBar(state: widget.state),
          ],
        ),
      ),
    );
  }

  Widget _buildToolContent(
    BuildContext context,
    ToolInstance instance,
    JsonPanelCompareDetails? compare,
  ) {
    final tool = ToolRegistry.byId(instance.toolId);
    if (tool == null) {
      return const Center(child: Text('Tool unavailable'));
    }
    if (instance.toolId == 'json_format_validate') {
      return buildJsonFormatValidate(
        session: _jsonSessionFor(instance.instanceId),
        compare: compare,
      );
    }
    return KeyedSubtree(
      key: ValueKey(instance.instanceId),
      child: tool.builder(context),
    );
  }

  JsonToolSession _jsonSessionFor(String instanceId) {
    return _jsonSessions.putIfAbsent(instanceId, () {
      final session = JsonToolSession();
      void refreshCompare() {
        if (mounted) setState(() {});
      }

      session.input.addListener(refreshCompare);
      session.output.addListener(refreshCompare);
      return session;
    });
  }

  List<ToolInstance>? _jsonComparePair(List<ToolInstance> panels) {
    final visibleJson =
        panels
            .where(
              (panel) =>
                  !panel.isMinimized && panel.toolId == 'json_format_validate',
            )
            .toList()
          ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    if (visibleJson.length < 2) return null;
    return [visibleJson[1], visibleJson[0]];
  }

  void _disposeRemovedJsonSessions(List<ToolInstance> panels) {
    final activeIds = panels.map((panel) => panel.instanceId).toSet();
    final removed = _jsonSessions.keys
        .where((instanceId) => !activeIds.contains(instanceId))
        .toList();
    for (final instanceId in removed) {
      _jsonSessions.remove(instanceId)?.dispose();
    }
  }
}

class _WorkspaceToolbar extends StatelessWidget {
  const _WorkspaceToolbar({required this.state, required this.canvasSize});

  final ToolState state;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: appColors.statusBar,
      // Compact tap targets so the toggle/buttons fit a slim bar without their
      // default 48px material padding ballooning the toolbar height.
      child: Theme(
        data: Theme.of(context).copyWith(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                'Workspace',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: appColors.editorText,
                ),
              ),
              const SizedBox(width: 12),
              ToolIconButton(
                icon: Icons.view_column_outlined,
                tooltip: 'Tile visible panels',
                onPressed: () => state.workspace.tileVisiblePanels(canvasSize),
              ),
              const SizedBox(width: 16),
              ValueListenableBuilder<bool>(
                valueListenable: state.darkMode,
                builder: (context, darkMode, _) {
                  return Tooltip(
                    message: darkMode
                        ? 'Switch to light mode'
                        : 'Switch to dark mode',
                    child: Switch(
                      value: darkMode,
                      onChanged: (value) => state.darkMode.value = value,
                    ),
                  );
                },
              ),
              ToolIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'Clear workspace',
                onPressed: state.workspace.clearWorkspace,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSideDockedPanel(ToolInstance panel) {
  return panel.dockMode == PanelDockMode.left ||
      panel.dockMode == PanelDockMode.right;
}

List<ToolInstance> _displayedWorkspacePanels(
  List<ToolInstance> panels,
  String? focusedPanelId,
) {
  final visible = panels.where((panel) => !panel.isMinimized).toList();
  final activeLeft = _activeDockPanel(
    visible,
    PanelDockMode.left,
    focusedPanelId,
  );
  final activeRight = _activeDockPanel(
    visible,
    PanelDockMode.right,
    focusedPanelId,
  );

  return visible.where((panel) {
    if (panel.dockMode == PanelDockMode.left) {
      return panel.instanceId == activeLeft?.instanceId;
    }
    if (panel.dockMode == PanelDockMode.right) {
      return panel.instanceId == activeRight?.instanceId;
    }
    return true;
  }).toList()..sort((a, b) => a.zIndex.compareTo(b.zIndex));
}

ToolInstance? _activeDockPanel(
  List<ToolInstance> visible,
  PanelDockMode mode,
  String? focusedPanelId,
) {
  final docked = visible.where((panel) => panel.dockMode == mode).toList();
  if (docked.isEmpty) return null;

  if (focusedPanelId != null) {
    for (final panel in docked) {
      if (panel.instanceId == focusedPanelId) return panel;
    }
  }

  docked.sort((a, b) => b.zIndex.compareTo(a.zIndex));
  return docked.first;
}

List<ToolInstance> _dockTabsForPanel(
  List<ToolInstance> visible,
  ToolInstance panel,
) {
  if (!_isSideDockedPanel(panel)) return const <ToolInstance>[];
  final dockTabs =
      visible
          .where((candidate) => candidate.dockMode == panel.dockMode)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return dockTabs.length < 2 ? const <ToolInstance>[] : dockTabs;
}

class _WorkspaceCanvas extends StatelessWidget {
  const _WorkspaceCanvas({
    required this.panels,
    required this.focusedPanelId,
    required this.jsonPair,
    required this.jsonCompare,
    required this.onSizeChanged,
    required this.onOpenTool,
    required this.onBuildTool,
    required this.workspace,
    required this.favorites,
    required this.onToggleFavorite,
  });

  final List<ToolInstance> panels;
  final String? focusedPanelId;
  final List<ToolInstance>? jsonPair;
  final JsonCompareSummary? jsonCompare;
  final ValueChanged<Size> onSizeChanged;
  final ValueChanged<String> onOpenTool;
  final Widget Function(
    BuildContext context,
    ToolInstance instance,
    JsonPanelCompareDetails? compare,
  )
  onBuildTool;
  final WorkspaceState workspace;
  final Set<String> favorites;
  final ValueChanged<String> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onSizeChanged(size);
        });
        final visible = panels.where((panel) => !panel.isMinimized).toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
        final displayed = _displayedWorkspacePanels(panels, focusedPanelId);
        return Container(
          color: appColors.canvas,
          child: Stack(
            children: [
              if (visible.isEmpty) _EmptyWorkspace(onOpenTool: onOpenTool),
              if (jsonPair != null && jsonCompare != null)
                Positioned(
                  top: 12,
                  left: max(16, size.width / 2 - 210),
                  child: _JsonCompareBar(summary: jsonCompare!),
                ),
              for (final panel in displayed)
                _ToolPanel(
                  key: ValueKey(panel.instanceId),
                  instance: panel,
                  tool: ToolRegistry.byId(panel.toolId),
                  bounds: _resolveBounds(panel, size),
                  focused: panel.instanceId == focusedPanelId,
                  compare: _compareForPanel(panel),
                  dockTabs: _dockTabsForPanel(visible, panel),
                  onFocus: () => workspace.focusPanel(panel.instanceId),
                  onClose: () => workspace.closePanel(panel.instanceId),
                  onMinimize: () => workspace.minimizePanel(panel.instanceId),
                  onDuplicate: () {
                    workspace.focusPanel(panel.instanceId);
                    workspace.duplicateFocusedPanel();
                  },
                  onMove: (delta) => workspace.updateBounds(
                    panel.instanceId,
                    panel.bounds.shift(delta),
                  ),
                  onResize: (corner, delta) => workspace.updateBounds(
                    panel.instanceId,
                    _resizePanelBounds(
                      _resolveBounds(panel, size),
                      corner,
                      delta,
                      size,
                    ),
                  ),
                  onSnapLeft: () => workspace.snapPanel(
                    panel.instanceId,
                    PanelDockMode.left,
                    size,
                  ),
                  onSnapRight: () => workspace.snapPanel(
                    panel.instanceId,
                    PanelDockMode.right,
                    size,
                  ),
                  onMaximize: () => workspace.snapPanel(
                    panel.instanceId,
                    PanelDockMode.maximized,
                    size,
                  ),
                  onSelectDockTab: workspace.focusPanel,
                  isFavorite: favorites.contains(panel.toolId),
                  onToggleFavorite: () => onToggleFavorite(panel.toolId),
                  child: onBuildTool(context, panel, _compareForPanel(panel)),
                ),
            ],
          ),
        );
      },
    );
  }

  JsonPanelCompareDetails? _compareForPanel(ToolInstance panel) {
    final pair = jsonPair;
    final compare = jsonCompare;
    if (pair == null || compare == null || pair.length < 2) return null;
    if (panel.instanceId == pair.first.instanceId) {
      return JsonPanelCompareDetails(
        summary: compare,
        changedLines: compare.leftChangedLines,
      );
    }
    if (panel.instanceId == pair.last.instanceId) {
      return JsonPanelCompareDetails(
        summary: compare,
        changedLines: compare.rightChangedLines,
      );
    }
    return null;
  }

  Rect _resolveBounds(ToolInstance panel, Size size) {
    final sideDocked =
        panel.dockMode == PanelDockMode.left ||
        panel.dockMode == PanelDockMode.right;
    final minWidth = panel.dockMode == PanelDockMode.tiled
        ? WorkspaceState.minTiledPanelWidth
        : sideDocked
        ? panel.bounds.width.clamp(180.0, WorkspaceState.minPanelWidth)
        : WorkspaceState.minPanelWidth;
    final minHeight = panel.dockMode == PanelDockMode.tiled
        ? WorkspaceState.minTiledPanelHeight
        : sideDocked
        ? panel.bounds.height.clamp(48.0, WorkspaceState.minPanelHeight)
        : WorkspaceState.minPanelHeight;
    final maxWidth = max(minWidth, size.width - 24);
    final maxHeight = max(minHeight, size.height - 24);
    final width = panel.bounds.width.clamp(minWidth, maxWidth);
    final height = panel.bounds.height.clamp(minHeight, maxHeight);
    final left = panel.bounds.left.clamp(
      12.0,
      max(12.0, size.width - width - 12),
    );
    final top = panel.bounds.top.clamp(
      12.0,
      max(12.0, size.height - height - 12),
    );
    return Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
  }

  Rect _resizePanelBounds(
    Rect bounds,
    _PanelResizeCorner corner,
    Offset delta,
    Size canvasSize,
  ) {
    const margin = 12.0;
    const minWidth = WorkspaceState.minPanelWidth;
    const minHeight = WorkspaceState.minPanelHeight;
    final maxRight = max(margin + minWidth, canvasSize.width - margin);
    final maxBottom = max(margin + minHeight, canvasSize.height - margin);

    double left = bounds.left;
    double top = bounds.top;
    double width = bounds.width;
    double height = bounds.height;

    switch (corner) {
      case _PanelResizeCorner.topLeft:
        final right = bounds.right;
        final bottom = bounds.bottom;
        left = (bounds.left + delta.dx).clamp(
          margin,
          max(margin, right - minWidth),
        );
        top = (bounds.top + delta.dy).clamp(
          margin,
          max(margin, bottom - minHeight),
        );
        width = right - left;
        height = bottom - top;
      case _PanelResizeCorner.topRight:
        final bottom = bounds.bottom;
        final maxWidth = max(minWidth, maxRight - bounds.left);
        width = (bounds.width + delta.dx).clamp(minWidth, maxWidth);
        top = (bounds.top + delta.dy).clamp(
          margin,
          max(margin, bottom - minHeight),
        );
        height = bottom - top;
      case _PanelResizeCorner.bottomLeft:
        final right = bounds.right;
        final maxHeight = max(minHeight, maxBottom - bounds.top);
        left = (bounds.left + delta.dx).clamp(
          margin,
          max(margin, right - minWidth),
        );
        width = right - left;
        height = (bounds.height + delta.dy).clamp(minHeight, maxHeight);
      case _PanelResizeCorner.bottomRight:
        final maxWidth = max(minWidth, maxRight - bounds.left);
        final maxHeight = max(minHeight, maxBottom - bounds.top);
        width = (bounds.width + delta.dx).clamp(minWidth, maxWidth);
        height = (bounds.height + delta.dy).clamp(minHeight, maxHeight);
    }

    return Rect.fromLTWH(left, top, width, height);
  }
}

enum _PanelResizeCorner { topLeft, topRight, bottomLeft, bottomRight }

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    super.key,
    required this.instance,
    required this.tool,
    required this.bounds,
    required this.focused,
    required this.compare,
    required this.dockTabs,
    required this.onFocus,
    required this.onClose,
    required this.onMinimize,
    required this.onDuplicate,
    required this.onMove,
    required this.onResize,
    required this.onSnapLeft,
    required this.onSnapRight,
    required this.onMaximize,
    required this.onSelectDockTab,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.child,
  });

  final ToolInstance instance;
  final DevTool? tool;
  final Rect bounds;
  final bool focused;
  final JsonPanelCompareDetails? compare;
  final List<ToolInstance> dockTabs;
  final VoidCallback onFocus;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onDuplicate;
  final ValueChanged<Offset> onMove;
  final void Function(_PanelResizeCorner corner, Offset delta) onResize;
  final VoidCallback onSnapLeft;
  final VoidCallback onSnapRight;
  final VoidCallback onMaximize;
  final ValueChanged<String> onSelectDockTab;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Positioned(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
      child: GestureDetector(
        onTapDown: (_) => onFocus(),
        child: Material(
          elevation: focused ? 12 : 5,
          shadowColor: appColors.shadow,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              color: appColors.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: focused ? appColors.accent : appColors.border,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    _PanelTitleBar(
                      instance: instance,
                      tool: tool,
                      focused: focused,
                      compare: compare,
                      isFavorite: isFavorite,
                      onToggleFavorite: onToggleFavorite,
                      onMove: onMove,
                      onFocus: onFocus,
                      onClose: onClose,
                      onMinimize: onMinimize,
                      onDuplicate: onDuplicate,
                      onSnapLeft: onSnapLeft,
                      onSnapRight: onSnapRight,
                      onMaximize: onMaximize,
                    ),
                    if (dockTabs.isNotEmpty)
                      _DockTabStrip(
                        tabs: dockTabs,
                        activeId: instance.instanceId,
                        onSelect: onSelectDockTab,
                      ),
                    Expanded(
                      child: Container(
                        color: appColors.panel,
                        padding: const EdgeInsets.all(10),
                        child: child,
                      ),
                    ),
                  ],
                ),
                for (final corner in _PanelResizeCorner.values)
                  _PanelResizeHandle(
                    corner: corner,
                    onResize: (delta) {
                      onFocus();
                      onResize(corner, delta);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockTabStrip extends StatelessWidget {
  const _DockTabStrip({
    required this.tabs,
    required this.activeId,
    required this.onSelect,
  });

  final List<ToolInstance> tabs;
  final String activeId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: appColors.panelElevated,
        border: Border(bottom: BorderSide(color: appColors.border)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final panel = tabs[index];
          final selected = panel.instanceId == activeId;
          final tool = ToolRegistry.byId(panel.toolId);
          return Semantics(
            button: true,
            selected: selected,
            label: 'Show ${panel.title}',
            child: Tooltip(
              message: panel.title,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onSelect(panel.instanceId),
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: selected ? appColors.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected ? appColors.accent : appColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tool?.icon ?? Icons.extension,
                        size: 14,
                        color: selected
                            ? appColors.accent
                            : appColors.mutedText,
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          panel.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? appColors.editorText
                                : appColors.mutedText,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemCount: tabs.length,
      ),
    );
  }
}

class _PanelResizeHandle extends StatelessWidget {
  const _PanelResizeHandle({required this.corner, required this.onResize});

  final _PanelResizeCorner corner;
  final ValueChanged<Offset> onResize;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final isLeft =
        corner == _PanelResizeCorner.topLeft ||
        corner == _PanelResizeCorner.bottomLeft;
    final isTop =
        corner == _PanelResizeCorner.topLeft ||
        corner == _PanelResizeCorner.topRight;
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      child: MouseRegion(
        cursor:
            corner == _PanelResizeCorner.topLeft ||
                corner == _PanelResizeCorner.bottomRight
            ? SystemMouseCursors.resizeUpLeftDownRight
            : SystemMouseCursors.resizeUpRightDownLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => onResize(details.delta),
          child: SizedBox(
            width: 14,
            height: 14,
            child: Align(
              alignment: _alignmentForCorner(corner),
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  border: _borderForCorner(corner, appColors.mutedText),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Alignment _alignmentForCorner(_PanelResizeCorner corner) {
    switch (corner) {
      case _PanelResizeCorner.topLeft:
        return Alignment.topLeft;
      case _PanelResizeCorner.topRight:
        return Alignment.topRight;
      case _PanelResizeCorner.bottomLeft:
        return Alignment.bottomLeft;
      case _PanelResizeCorner.bottomRight:
        return Alignment.bottomRight;
    }
  }

  Border _borderForCorner(_PanelResizeCorner corner, Color color) {
    final side = BorderSide(color: color.withAlpha(150), width: 1.4);
    switch (corner) {
      case _PanelResizeCorner.topLeft:
        return Border(top: side, left: side);
      case _PanelResizeCorner.topRight:
        return Border(top: side, right: side);
      case _PanelResizeCorner.bottomLeft:
        return Border(bottom: side, left: side);
      case _PanelResizeCorner.bottomRight:
        return Border(bottom: side, right: side);
    }
  }
}

class _PanelTitleBar extends StatelessWidget {
  const _PanelTitleBar({
    required this.instance,
    required this.tool,
    required this.focused,
    required this.compare,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onMove,
    required this.onFocus,
    required this.onClose,
    required this.onMinimize,
    required this.onDuplicate,
    required this.onSnapLeft,
    required this.onSnapRight,
    required this.onMaximize,
  });

  final ToolInstance instance;
  final DevTool? tool;
  final bool focused;
  final JsonPanelCompareDetails? compare;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final ValueChanged<Offset> onMove;
  final VoidCallback onFocus;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onDuplicate;
  final VoidCallback onSnapLeft;
  final VoidCallback onSnapRight;
  final VoidCallback onMaximize;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onFocus(),
      onPanUpdate: (details) => onMove(details.delta),
      child: Container(
        height: 30,
        color: focused ? appColors.panelHeader : appColors.panelElevated,
        padding: const EdgeInsets.only(left: 10, right: 4),
        child: Row(
          children: [
            Icon(
              tool?.icon ?? Icons.extension,
              size: 15,
              color: appColors.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                instance.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (compare != null) ...[
              const SizedBox(width: 8),
              _PanelBadge(label: compare!.summary.label),
            ],
            ToolIconButton(
              icon: isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? appColors.warning : null,
              tooltip: isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              onPressed: onToggleFavorite,
            ),
            ToolIconButton(
              icon: Icons.control_point_duplicate,
              tooltip: 'Duplicate panel',
              onPressed: onDuplicate,
            ),
            _MirroredToolIconButton(
              icon: Icons.vertical_split,
              tooltip: 'Snap left',
              onPressed: onSnapLeft,
            ),
            ToolIconButton(
              icon: Icons.vertical_split,
              tooltip: 'Snap right',
              onPressed: onSnapRight,
            ),
            ToolIconButton(
              icon: Icons.crop_square,
              tooltip: 'Maximize',
              onPressed: onMaximize,
            ),
            ToolIconButton(
              icon: Icons.minimize,
              tooltip: 'Minimize',
              onPressed: onMinimize,
            ),
            ToolIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelBadge extends StatelessWidget {
  const _PanelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: appColors.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: appColors.editorText),
      ),
    );
  }
}

class _MirroredToolIconButton extends StatelessWidget {
  const _MirroredToolIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 16,
      icon: Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _JsonCompareBar extends StatelessWidget {
  const _JsonCompareBar({required this.summary});

  final JsonCompareSummary summary;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Material(
      elevation: 8,
      shadowColor: appColors.shadow,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 420,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: appColors.panelElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: appColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.compare_arrows, size: 16, color: appColors.accent),
            const SizedBox(width: 8),
            const Text(
              'Compare',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            const Spacer(),
            Text(summary.label),
          ],
        ),
      ),
    );
  }
}

class _MinimizedDock extends StatelessWidget {
  const _MinimizedDock({required this.panels, required this.onRestore});

  final List<ToolInstance> panels;
  final ValueChanged<String> onRestore;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final panel in panels)
            _MinimizedChip(
              icon: ToolRegistry.byId(panel.toolId)?.icon,
              label: panel.title,
              onRestore: () => onRestore(panel.instanceId),
            ),
        ],
      ),
    );
  }
}

/// A slim taskbar pill for a single minimized panel. Click to restore.
class _MinimizedChip extends StatelessWidget {
  const _MinimizedChip({
    required this.icon,
    required this.label,
    required this.onRestore,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Tooltip(
      message: 'Restore $label',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: appColors.statusBar,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onRestore,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: appColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: appColors.mutedText),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({required this.onOpenTool});

  final ValueChanged<String> onOpenTool;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final starters = [
      'json_format_validate',
      'jwt_debugger',
      'base64_string_encode_decode',
      'text_diff_checker',
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize, size: 34, color: appColors.accent),
            const SizedBox(height: 12),
            const Text(
              'Open a tool from the sidebar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Panels can be duplicated, tiled, snapped, and compared without leaving the workspace.',
              textAlign: TextAlign.center,
              style: TextStyle(color: appColors.mutedText),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final id in starters)
                  ActionChip(
                    avatar: Icon(ToolRegistry.byId(id)?.icon, size: 16),
                    label: Text(ToolRegistry.defaultPanelTitle(id)),
                    onPressed: () => onOpenTool(id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceStatusBar extends StatelessWidget {
  const _WorkspaceStatusBar({required this.state});

  final ToolState state;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: appColors.statusBar,
      child: ValueListenableBuilder<List<ToolInstance>>(
        valueListenable: state.workspace.panels,
        builder: (context, panels, _) {
          return ValueListenableBuilder<String?>(
            valueListenable: state.workspace.focusedPanelId,
            builder: (context, focusedPanelId, _) {
              final focused = focusedPanelId == null
                  ? null
                  : state.workspace.panelById(focusedPanelId);
              final visibleCount = panels
                  .where((panel) => !panel.isMinimized)
                  .length;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final showShortcuts = constraints.maxWidth >= 760;
                  return Row(
                    children: [
                      Flexible(
                        child: Text(
                          focused?.title ?? 'No panel focused',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: appColors.mutedText,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '$visibleCount open',
                        style: TextStyle(
                          color: appColors.mutedText,
                          fontSize: 11.5,
                        ),
                      ),
                      if (showShortcuts) ...[
                        const Spacer(),
                        Text(
                          'Cmd+N New Panel  •  Cmd+Shift+D Duplicate  •  Cmd+W Close',
                          style: TextStyle(
                            color: appColors.mutedText,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
