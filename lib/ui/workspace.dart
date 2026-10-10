import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dev_tool.dart';
import '../registry/tool_registry.dart';
import '../state/tool_state.dart';
import '../state/workspace_state.dart';
import 'app_colors.dart';
import 'tool_views.dart';
import 'tool_sample_action.dart';
import 'widgets.dart';

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({super.key, required this.state});

  final ToolState state;

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  final Map<String, JsonToolSession> _jsonSessions = {};

  WorkspaceState get _workspace => widget.state.workspace;

  @override
  void dispose() {
    for (final session in _jsonSessions.values) {
      session.dispose();
    }
    super.dispose();
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

  void _disposeRemovedJsonSessions(List<ToolInstance> panels) {
    final activeIds = panels.map((panel) => panel.instanceId).toSet();
    final removed = _jsonSessions.keys
        .where((instanceId) => !activeIds.contains(instanceId))
        .toList();
    for (final instanceId in removed) {
      _jsonSessions.remove(instanceId)?.dispose();
    }
  }

  /// The other open JSON tab to compare against, when at least two exist.
  List<ToolInstance> _jsonComparePair(List<ToolInstance> panels) {
    final visible = panels
        .where((panel) => panel.toolId == 'json_format_validate')
        .toList();
    return visible.length < 2 ? const [] : visible;
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
    final content = instance.toolId == 'json_format_validate'
        ? buildJsonFormatValidate(
            session: _jsonSessionFor(instance.instanceId),
            compare: compare,
          )
        : tool.builder(context);
    return KeyedSubtree(key: ValueKey(instance.instanceId), child: content);
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () {
        _workspace.openTool(
          _workspace.panelById(_workspace.focusedPanelId.value ?? '')?.toolId ??
              widget.state.selectedToolId.value,
          forceNew: true,
        );
      },
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
          _workspace.closeFocusedPanel,
      const SingleActivator(
        LogicalKeyboardKey.bracketLeft,
        meta: true,
        shift: true,
      ): () =>
          _workspace.selectAdjacent(-1),
      const SingleActivator(
        LogicalKeyboardKey.bracketRight,
        meta: true,
        shift: true,
      ): () =>
          _workspace.selectAdjacent(1),
    };
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    for (var i = 0; i < digits.length; i++) {
      final index = i;
      bindings[SingleActivator(digits[i], meta: true)] = () {
        final tabs = _workspace.panels.value;
        if (index < tabs.length) {
          _workspace.focusPanel(tabs[index].instanceId);
        }
      };
    }
    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _WorkspaceTabBar(state: widget.state),
            Expanded(
              child: ValueListenableBuilder<List<ToolInstance>>(
                valueListenable: _workspace.panels,
                builder: (context, panels, _) {
                  _disposeRemovedJsonSessions(panels);
                  return ValueListenableBuilder<String?>(
                    valueListenable: _workspace.focusedPanelId,
                    builder: (context, focusedPanelId, _) {
                      if (panels.isEmpty) {
                        return _EmptyWorkspace(
                          onOpenTool: (id) {
                            widget.state.selectedToolId.value = id;
                            _workspace.openTool(id);
                          },
                        );
                      }
                      final active =
                          _workspace.panelById(focusedPanelId ?? '') ??
                          panels.last;
                      final jsonPair = _jsonComparePair(panels);
                      final isActiveJson =
                          active.toolId == 'json_format_validate';
                      final jsonCompare = isActiveJson && jsonPair.length >= 2
                          ? compareJsonSessions(
                              _jsonSessionFor(jsonPair.first.instanceId),
                              _jsonSessionFor(jsonPair.last.instanceId),
                              JsonCompareMode.normalized,
                            )
                          : null;
                      JsonPanelCompareDetails? compare;
                      if (isActiveJson &&
                          jsonPair.length >= 2 &&
                          jsonCompare != null) {
                        if (active.instanceId == jsonPair.first.instanceId) {
                          compare = JsonPanelCompareDetails(
                            summary: jsonCompare,
                            changedLines: jsonCompare.leftChangedLines,
                          );
                        } else if (active.instanceId ==
                            jsonPair.last.instanceId) {
                          compare = JsonPanelCompareDetails(
                            summary: jsonCompare,
                            changedLines: jsonCompare.rightChangedLines,
                          );
                        }
                      }
                      final tool = ToolRegistry.byId(active.toolId);
                      return ToolSampleHost(
                        key: ValueKey(active.instanceId),
                        builder: (context, sample) => Column(
                          children: [
                            if (tool != null)
                              _ToolHeader(
                                tool: tool,
                                instance: active,
                                state: widget.state,
                                sample: sample,
                              ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  24,
                                ),
                                child: _buildToolContent(
                                  context,
                                  active,
                                  compare,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTabBar extends StatelessWidget {
  const _WorkspaceTabBar({required this.state});

  final ToolState state;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: appColors.statusBar,
        border: Border(bottom: BorderSide(color: appColors.border)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<List<ToolInstance>>(
                valueListenable: state.workspace.panels,
                builder: (context, panels, _) {
                  return ValueListenableBuilder<String?>(
                    valueListenable: state.workspace.focusedPanelId,
                    builder: (context, focusedId, _) {
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < panels.length; i++)
                            _ToolTab(
                              key: ValueKey(panels[i].instanceId),
                              instance: panels[i],
                              index: i,
                              tabs: panels,
                              isActive: panels[i].instanceId == focusedId,
                              onSelect: () => state.workspace.focusPanel(
                                panels[i].instanceId,
                              ),
                              onClose: () => state.workspace.closePanel(
                                panels[i].instanceId,
                              ),
                              onCloseAll: state.workspace.clearWorkspace,
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'New tab for current tool (⌘N)',
              onPressed: () => state.workspace.openTool(
                state.workspace
                        .panelById(state.workspace.focusedPanelId.value ?? '')
                        ?.toolId ??
                    state.selectedToolId.value,
                forceNew: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolTab extends StatelessWidget {
  const _ToolTab({
    super.key,
    required this.instance,
    required this.index,
    required this.tabs,
    required this.isActive,
    required this.onSelect,
    required this.onClose,
    required this.onCloseAll,
  });

  final ToolInstance instance;
  final int index;
  final List<ToolInstance> tabs;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final VoidCallback onCloseAll;

  String get _label {
    final sameTool = tabs.where((t) => t.toolId == instance.toolId).toList();
    if (sameTool.length < 2) return instance.title;
    final ordinal = sameTool.indexOf(instance) + 1;
    return '${instance.title} $ordinal';
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final tool = ToolRegistry.byId(instance.toolId);
    final subtitle = tool?.subtitle ?? '';
    return Tooltip(
      message: subtitle.isEmpty ? _label : '$_label — $subtitle',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTertiaryTapUp: (_) => onClose(),
        onSecondaryTapUp: (details) async {
          final overlay =
              Overlay.of(context).context.findRenderObject() as RenderBox;
          final action = await showMenu<String>(
            context: context,
            position: RelativeRect.fromRect(
              Rect.fromLTWH(
                details.globalPosition.dx,
                details.globalPosition.dy,
                1,
                1,
              ),
              Offset.zero & overlay.size,
            ),
            items: const [
              PopupMenuItem(value: 'close', child: Text('Close tab')),
              PopupMenuItem(value: 'all', child: Text('Close all tabs')),
            ],
          );
          if (action == 'close') onClose();
          if (action == 'all') onCloseAll();
        },
        child: Material(
          color: Colors.transparent,

          child: InkWell(
            onTap: onSelect,
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? appColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                color: Colors.transparent,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tool != null) ...[
                    Icon(
                      tool.icon,
                      size: 13,
                      color: isActive ? appColors.accent : appColors.mutedText,
                    ),
                    const SizedBox(width: 6),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      _label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: appColors.editorText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _TabCloseButton(tooltip: 'Close $_label', onClose: onClose),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabCloseButton extends StatelessWidget {
  const _TabCloseButton({required this.tooltip, required this.onClose});

  final String tooltip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: IconButton(
        icon: Icon(Icons.close, size: 12, color: appColors.mutedText),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        splashRadius: 10,
        onPressed: onClose,
      ),
    );
  }
}

class _ToolHeader extends StatelessWidget {
  const _ToolHeader({
    required this.tool,
    required this.instance,
    required this.state,
    required this.sample,
  });

  final DevTool tool;
  final ToolInstance instance;
  final ToolState state;
  final ValueListenable<ToolSampleCommand?> sample;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: state.favorites,
                      builder: (context, favorites, _) {
                        final isFavorite = favorites.contains(tool.id);
                        return Semantics(
                          container: true,
                          toggled: isFavorite,
                          child: IconButton(
                            icon: Icon(
                              isFavorite ? Icons.star : Icons.star_border,
                              size: 20,
                              color: isFavorite
                                  ? appColors.accent
                                  : appColors.mutedText,
                            ),
                            tooltip: isFavorite
                                ? 'Remove from favorites'
                                : 'Add to favorites',
                            onPressed: () => state.toggleFavorite(tool.id),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      },
                    ),
                    Text(
                      instance.title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: appColors.editorText,
                      ),
                    ),
                    _OfflinePill(isOffline: tool.isOffline),
                  ],
                ),
              ),
              ValueListenableBuilder<ToolSampleCommand?>(
                valueListenable: sample,
                builder: (context, command, _) => command == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(left: 12, top: 1),
                        child: ToolButton(
                          label: 'Load sample',
                          icon: Icons.description_outlined,
                          onPressed: command.onPressed,
                        ),
                      ),
              ),
            ],
          ),
          if (tool.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              tool.subtitle,
              style: TextStyle(fontSize: 13, color: appColors.mutedText),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfflinePill extends StatelessWidget {
  const _OfflinePill({required this.isOffline});

  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final color = isOffline ? appColors.success : appColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: appColors.panelHeader,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOffline ? Icons.circle : Icons.wifi_tethering,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isOffline ? 'Offline tool' : 'Network',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: appColors.mutedText,
            ),
          ),
        ],
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
              'Open tools stay as tabs. Switch with ⌘1–9 or ⌘⇧[ and ⌘⇧].',
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
