import 'package:flutter/material.dart';

import '../app.dart';
import '../models/dev_tool.dart';
import 'widgets.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.tools,
    required this.selectedToolId,
    required this.searchQuery,
    required this.favorites,
    required this.onSelect,
    required this.onSearch,
  });

  final List<DevTool> tools;
  final String selectedToolId;
  final String searchQuery;
  final Set<String> favorites;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onSearch;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _searchController =
      TextEditingController(text: widget.searchQuery);

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
    final appColors = Theme.of(context).extension<AppColors>();
    final categories = <String, List<DevTool>>{};
    for (final tool in widget.tools) {
      categories.putIfAbsent(tool.category, () => []).add(tool);
    }
    final favoriteTools = widget.tools.where((tool) => widget.favorites.contains(tool.id)).toList();
    return Container(
      width: 250,
      color: appColors?.sidebar ?? const Color(0xFFE4E4E4),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: widget.onSearch,
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: widget.searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                const SectionHeader(title: 'Favorites'),
                if (favoriteTools.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('No favorites yet.', style: TextStyle(color: Colors.black54)),
                  )
                else
                  ...favoriteTools.map(
                    (tool) => _SidebarItem(
                      tool: tool,
                      selected: tool.id == widget.selectedToolId,
                      onTap: () => widget.onSelect(tool.id),
                    ),
                  ),
                for (final entry in categories.entries) ...[
                  SectionHeader(title: entry.key),
                  ...entry.value.map(
                    (tool) => _SidebarItem(
                      tool: tool,
                      selected: tool.id == widget.selectedToolId,
                      onTap: () => widget.onSelect(tool.id),
                    ),
                  ),
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
    required this.onTap,
  });

  final DevTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final highlight = selected ? const Color(0xFFD8E3EA) : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Material(
        color: highlight,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: const Color(0xFFE2EBF0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(tool.icon, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tool.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3E5B6A),
                      shape: BoxShape.circle,
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
