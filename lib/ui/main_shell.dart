import 'package:flutter/material.dart';

import '../registry/tool_registry.dart';
import '../state/tool_state.dart';
import 'app_colors.dart';
import 'sidebar.dart';
import 'workspace.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.state});

  final ToolState state;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return ValueListenableBuilder<String>(
      valueListenable: state.searchQuery,
      builder: (context, query, _) {
        final filtered = ToolRegistry.tools
            .where(
              (tool) => tool.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();

        return ValueListenableBuilder<Set<String>>(
          valueListenable: state.favorites,
          builder: (context, favorites, _) {
            return ValueListenableBuilder<String?>(
              valueListenable: state.workspace.focusedPanelId,
              builder: (context, focusedPanelId, _) {
                final focusedPanel = focusedPanelId == null
                    ? null
                    : state.workspace.panelById(focusedPanelId);
                final selectedToolId =
                    focusedPanel?.toolId ?? state.selectedToolId.value;

                return ValueListenableBuilder<double>(
                  valueListenable: state.sidebarWidth,
                  builder: (context, sidebarWidth, _) {
                    return Scaffold(
                      body: Row(
                        children: [
                          Sidebar(
                            width: sidebarWidth,
                            tools: filtered,
                            selectedToolId: selectedToolId,
                            searchQuery: query,
                            favorites: favorites,
                            onSelect: (id) {
                              state.selectedToolId.value = id;
                              state.workspace.openTool(id);
                            },
                            onSearch: (value) =>
                                state.searchQuery.value = value,
                          ),
                          _SidebarResizeHandle(
                            key: const ValueKey('sidebar-resize-handle'),
                            color: appColors.border,
                            hoverColor: appColors.accent,
                            onDrag: (delta) {
                              state.sidebarWidth.value =
                                  (state.sidebarWidth.value + delta.dx)
                                      .clamp(64, 420)
                                      .toDouble();
                            },
                          ),
                          Expanded(child: WorkspaceView(state: state)),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SidebarResizeHandle extends StatefulWidget {
  const _SidebarResizeHandle({
    super.key,
    required this.color,
    required this.hoverColor,
    required this.onDrag,
  });

  final Color color;
  final Color hoverColor;
  final ValueChanged<Offset> onDrag;

  @override
  State<_SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<_SidebarResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => widget.onDrag(details.delta),
        child: Container(
          width: 7,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: _hovered ? 2 : 1,
            color: _hovered ? widget.hoverColor : widget.color,
          ),
        ),
      ),
    );
  }
}
