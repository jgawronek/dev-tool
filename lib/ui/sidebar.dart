import 'package:flutter/material.dart';

import '../models/dev_tool.dart';
import 'app_colors.dart';
import 'widgets.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.tools,
    required this.selectedToolId,
    required this.searchQuery,
    required this.favorites,
    required this.width,
    required this.onSelect,
    required this.onSearch,
  });

  final List<DevTool> tools;
  final String selectedToolId;
  final String searchQuery;
  final Set<String> favorites;
  final double width;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onSearch;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _searchController = TextEditingController(
    text: widget.searchQuery,
  );

  @override
  void didUpdateWidget(covariant Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        _searchController.text != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final compact = widget.width < 150;
    final categories = <String, List<DevTool>>{};
    for (final tool in widget.tools) {
      categories.putIfAbsent(tool.category, () => []).add(tool);
    }
    final favoriteTools = widget.tools
        .where((tool) => widget.favorites.contains(tool.id))
        .toList();
    return Container(
      width: widget.width,
      color: appColors.sidebar,
      child: Column(
        children: [
          if (compact)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Tooltip(
                message: 'Expand sidebar to search',
                child: Icon(Icons.search, size: 20, color: appColors.mutedText),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: TextField(
                controller: _searchController,
                onChanged: widget.onSearch,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Search tools',
                  hintStyle: const TextStyle(fontSize: 12.5),
                  // Tighten the field vertically (the global input padding is
                  // roomier than a sidebar search needs).
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 0,
                  ),
                  suffixIcon: widget.searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 0,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            widget.onSearch('');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 8,
                vertical: 4,
              ),
              children: [
                if (compact)
                  ...widget.tools.map(
                    (tool) => _SidebarItem(
                      tool: tool,
                      selected: tool.id == widget.selectedToolId,
                      compact: true,
                      onTap: () => widget.onSelect(tool.id),
                    ),
                  )
                else ...[
                  const SectionHeader(title: 'Favorites'),
                  if (favoriteTools.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'No favorites yet.',
                        style: TextStyle(color: appColors.mutedText),
                      ),
                    )
                  else
                    ...favoriteTools.map(
                      (tool) => _SidebarItem(
                        tool: tool,
                        selected: tool.id == widget.selectedToolId,
                        compact: false,
                        onTap: () => widget.onSelect(tool.id),
                      ),
                    ),
                  for (final entry in categories.entries) ...[
                    SectionHeader(title: entry.key),
                    ...entry.value.map(
                      (tool) => _SidebarItem(
                        tool: tool,
                        selected: tool.id == widget.selectedToolId,
                        compact: false,
                        onTap: () => widget.onSelect(tool.id),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.tool,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final DevTool tool;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final highlight = selected ? appColors.selected : Colors.transparent;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 0.5),
      child: Tooltip(
        message: compact ? tool.name : '',
        waitDuration: const Duration(milliseconds: 350),
        child: Semantics(
          label: tool.name,
          button: true,
          selected: selected,
          child: Material(
            color: highlight,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              hoverColor: appColors.hover,
              child: Container(
                height: compact ? 34 : null,
                padding: compact
                    ? const EdgeInsets.symmetric(horizontal: 6, vertical: 5)
                    : const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: compact
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            tool.icon,
                            size: 20,
                            color: selected
                                ? appColors.accent
                                : appColors.editorText,
                          ),
                          if (selected)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                width: 3,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: appColors.accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(
                            tool.icon,
                            size: 16,
                            color: appColors.editorText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tool.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: appColors.editorText,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (selected)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: appColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
