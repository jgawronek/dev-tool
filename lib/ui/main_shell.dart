import 'package:flutter/material.dart';

import '../models/dev_tool.dart';
import '../registry/tool_registry.dart';
import '../state/tool_state.dart';
import 'sidebar.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.state});

  final ToolState state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: state.searchQuery,
      builder: (context, query, _) {
        final tools = ToolRegistry.tools;
        final filtered = tools
            .where(
              (tool) => tool.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();

        return ValueListenableBuilder<String>(
          valueListenable: state.selectedToolId,
          builder: (context, selectedId, _) {
            return ValueListenableBuilder<Set<String>>(
              valueListenable: state.favorites,
              builder: (context, favorites, _) {
                DevTool? selectedTool;
                for (final tool in filtered) {
                  if (tool.id == selectedId) {
                    selectedTool = tool;
                    break;
                  }
                }
                if (selectedTool == null && filtered.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    state.selectedToolId.value = filtered.first.id;
                  });
                  selectedTool = filtered.first;
                }

                return Scaffold(
                  body: Row(
                    children: [
                      Sidebar(
                        tools: filtered,
                        selectedToolId: selectedTool?.id ?? '',
                        searchQuery: query,
                        favorites: favorites,
                        onSelect: (id) => state.selectedToolId.value = id,
                        onSearch: (value) => state.searchQuery.value = value,
                      ),
                      const VerticalDivider(width: 1, color: Color(0xFFCCCCCC)),
                      Expanded(
                        child: Column(
                          children: [
                            _ToolHeader(
                              tool: selectedTool,
                              isFavorite:
                                  selectedTool != null &&
                                  favorites.contains(selectedTool.id),
                              onToggleFavorite: selectedTool == null
                                  ? null
                                  : () =>
                                        state.toggleFavorite(selectedTool!.id),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: selectedTool == null
                                    ? const Center(
                                        child: Text(
                                          'No tools match your search.',
                                        ),
                                      )
                                    : selectedTool.builder(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ToolHeader extends StatelessWidget {
  const _ToolHeader({
    required this.tool,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final DevTool? tool;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (tool == null) {
      return const SizedBox(height: 56);
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEF2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(tool!.icon, size: 16, color: const Color(0xFF3E5B6A)),
          ),
          const SizedBox(width: 10),
          Text(tool!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(isFavorite ? Icons.star : Icons.star_border),
            onPressed: onToggleFavorite,
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            visualDensity: VisualDensity.compact,
            splashRadius: 16,
          ),
          const Spacer(),
          if (tool!.showDemo)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE9EEF2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFC7D4DD)),
              ),
              child: const Text('Demo', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
