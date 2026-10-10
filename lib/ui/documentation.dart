import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tool_documentation.dart';
import '../models/dev_tool.dart';
import '../registry/tool_registry.dart';
import '../state/tool_state.dart';
import 'app_colors.dart';

/// Receives the native Help menu action without replacing macOS's other menus.
class DocumentationMenuHost extends StatefulWidget {
  const DocumentationMenuHost({
    super.key,
    required this.state,
    required this.child,
  });

  final ToolState state;
  final Widget child;

  @override
  State<DocumentationMenuHost> createState() => _DocumentationMenuHostState();
}

class _DocumentationMenuHostState extends State<DocumentationMenuHost> {
  static const _channel = MethodChannel('devutils/documentation');
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') await _open();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _channel.invokeMethod<void>('ready');
      } on MissingPluginException {
        // The keyboard shortcut also works on platforms without a native menu.
      }
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _open() async {
    if (!mounted || _isOpen) return;
    _isOpen = true;
    try {
      final id = await showDialog<String>(
        context: context,
        builder: (_) => const DocumentationView(),
      );
      if (mounted && id != null) {
        widget.state.selectedToolId.value = id;
        widget.state.workspace.openTool(id);
      }
    } finally {
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyD, meta: true, shift: true):
          _open,
    },
    child: widget.child,
  );
}

class _Guide {
  const _Guide(this.id, this.title, this.category, this.text, {this.tool});

  final String id;
  final String title;
  final String category;
  final String text;
  final DevTool? tool;

  String get searchable => '$title $category $text'.toLowerCase();
}

class DocumentationView extends StatefulWidget {
  const DocumentationView({super.key});

  @override
  State<DocumentationView> createState() => _DocumentationViewState();
}

class _DocumentationViewState extends State<DocumentationView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _articleScroll = ScrollController();
  late final List<_Guide> _guides = [
    _Guide(
      'getting_started',
      'Getting started',
      'Start here',
      toolDocumentation['getting_started']!,
    ),
    _Guide(
      'glossary',
      'Words explained',
      'Start here',
      toolDocumentation['glossary']!,
    ),
    for (final tool in ToolRegistry.tools)
      _Guide(
        tool.id,
        tool.name,
        tool.category,
        toolDocumentation[tool.id] ?? 'This tool does not have a guide yet.',
        tool: tool,
      ),
  ];
  String _selected = 'getting_started';
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _articleScroll.dispose();
    super.dispose();
  }

  void _select(String id) {
    setState(() => _selected = id);
    if (_articleScroll.hasClients) _articleScroll.jumpTo(0);
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
    _searchFocus.requestFocus();
  }

  String _excerpt(_Guide guide) {
    final flat = guide.text.replaceAll('\n', ' ').replaceAll('## ', '');
    final index = flat.toLowerCase().indexOf(_query.toLowerCase());
    final start = index < 0 ? 0 : math.max(0, index - 35);
    final end = math.min(flat.length, start + 130);
    return '${start > 0 ? '…' : ''}${flat.substring(start, end)}${end < flat.length ? '…' : ''}';
  }

  Widget _menu(List<_Guide> matches) {
    final categories = <String>{
      for (final guide in matches) guide.category,
    }.toList();
    categories.sort(
      (a, b) => a == 'Start here'
          ? -1
          : b == 'Start here'
          ? 1
          : a.compareTo(b),
    );
    return Container(
      color: context.appColors.panelHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              _query.isEmpty
                  ? '${ToolRegistry.tools.length} tool guides'
                  : '${matches.length} search results',
              style: TextStyle(
                color: context.appColors.mutedText,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No guides found.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Try a tool name or a word such as JSON, password, or date.',
                        ),
                        TextButton(
                          onPressed: _clearSearch,
                          child: const Text('Clear search'),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      for (final category in categories) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                          child: Text(
                            category,
                            style: TextStyle(
                              color: context.appColors.mutedText,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (final guide in matches.where(
                          (guide) => guide.category == category,
                        ))
                          ListTile(
                            selected: guide.id == _selected,
                            leading: Icon(
                              guide.tool?.icon ?? Icons.menu_book_outlined,
                              size: 18,
                            ),
                            title: Text(
                              guide.title,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: _query.isEmpty
                                ? null
                                : Text(
                                    _excerpt(guide),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                            onTap: () => _select(guide.id),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _article(_Guide guide) {
    final parts = guide.text.split('\n## ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                guide.title,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: context.appColors.editorText,
                ),
              ),
              if (guide.tool != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open tool'),
                  onPressed: () => Navigator.of(context).pop(guide.id),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SelectionArea(
            child: ListView(
              key: ValueKey(guide.id),
              controller: _articleScroll,
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 30),
              children: [
                Text(
                  parts.first,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: context.appColors.editorText,
                  ),
                ),
                for (final part in parts.skip(1)) ...[
                  const SizedBox(height: 22),
                  Semantics(
                    header: true,
                    child: Text(
                      part.substring(0, part.indexOf('\n')),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.appColors.editorText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    part.substring(part.indexOf('\n') + 1),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.65,
                      color: context.appColors.editorText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final terms = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty);
    final matches = _guides
        .where((guide) => terms.every(guide.searchable.contains))
        .toList();
    final guide = _guides.firstWhere((guide) => guide.id == _selected);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: context.appColors.canvas,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(1120, size.width - 48),
        height: math.min(800, size.height - 48),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                _searchFocus.requestFocus,
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Documentation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        focusNode: _searchFocus,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search all guides',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close, size: 17),
                                  onPressed: _clearSearch,
                                ),
                        ),
                        onChanged: (value) =>
                            setState(() => _query = value.trim()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Close documentation',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 700) {
                      return Column(
                        children: [
                          SizedBox(height: 180, child: _menu(matches)),
                          const Divider(height: 1),
                          Expanded(child: _article(guide)),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(width: 280, child: _menu(matches)),
                        const VerticalDivider(width: 1),
                        Expanded(child: _article(guide)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
