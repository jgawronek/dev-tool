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
  });

  final String id;
  final String name;
  final IconData icon;
  final ToolViewBuilder builder;
  final bool showDemo;
  final String category;
}
