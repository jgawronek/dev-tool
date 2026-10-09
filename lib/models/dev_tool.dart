import 'package:flutter/material.dart';

typedef ToolViewBuilder = Widget Function(BuildContext context);

class DevTool {
  DevTool({
    required this.id,
    required this.name,
    required this.icon,
    required this.builder,
    this.showDemo = true,
    this.category = 'General',
    this.minSize,
  });

  final String id;
  final String name;
  final IconData icon;
  final ToolViewBuilder builder;
  final bool showDemo;
  final String category;

  /// Smallest panel this tool stays usable in. Null means the workspace-wide
  /// default applies. Tools whose layout stacks fixed controls above expanding
  /// editors declare a larger floor instead of scrolling those controls away.
  final Size? minSize;
}
