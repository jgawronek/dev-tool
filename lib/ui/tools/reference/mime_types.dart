/// MIME types reference tool view.
library;

import 'package:flutter/material.dart';
import '../../../data/mime_types.dart';
import '../../../ui/app_colors.dart';
import '../common/shared.dart';

class _MimeTypesView extends StatefulWidget {
  const _MimeTypesView();

  @override
  State<_MimeTypesView> createState() => _MimeTypesViewState();
}

class _MimeTypesViewState extends State<_MimeTypesView> {
  final TextEditingController _search = TextEditingController();
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MimeTypeEntry> _filteredEntries() {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return List<MimeTypeEntry>.from(mimeTypeEntries);
    }
    return mimeTypeEntries.where((entry) {
      return entry.name.toLowerCase().contains(query) ||
          entry.mimeType.toLowerCase().contains(query) ||
          entry.extension.toLowerCase().contains(query) ||
          entry.details.toLowerCase().contains(query);
    }).toList();
  }

  int _compareEntries(MimeTypeEntry a, MimeTypeEntry b, int column) {
    String left;
    String right;
    switch (column) {
      case 1:
        left = a.mimeType;
        right = b.mimeType;
        break;
      case 2:
        left = a.extension;
        right = b.extension;
        break;
      case 3:
        left = a.details;
        right = b.details;
        break;
      case 0:
      default:
        left = a.name;
        right = b.name;
        break;
    }
    return left.toLowerCase().compareTo(right.toLowerCase());
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final entries = _filteredEntries();
    entries.sort((a, b) {
      final result = _compareEntries(a, b, _sortColumnIndex);
      return _sortAscending ? result : -result;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search name, type, extension, details...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${entries.length} entries',
              style: mutedToolTextStyle(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: toolSurfaceDecoration(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    sortAscending: _sortAscending,
                    sortColumnIndex: _sortColumnIndex,
                    headingRowColor: WidgetStateProperty.all(
                      appColors.panelHeader,
                    ),
                    columnSpacing: 24,
                    columns: [
                      DataColumn(label: const Text('Name'), onSort: _onSort),
                      DataColumn(
                        label: const Text('MIME Type / Internet Media Type'),
                        onSort: _onSort,
                      ),
                      DataColumn(
                        label: const Text('File Extension'),
                        onSort: _onSort,
                      ),
                      DataColumn(
                        label: const Text('More Details'),
                        onSort: _onSort,
                      ),
                    ],
                    rows: entries
                        .map(
                          (entry) => DataRow(
                            cells: [
                              DataCell(Text(entry.name)),
                              DataCell(SelectableText(entry.mimeType)),
                              DataCell(Text(entry.extension)),
                              DataCell(Text(entry.details)),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget buildMimeTypes() {
  return const _MimeTypesView();
}
