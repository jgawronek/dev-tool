import 'package:flutter/widgets.dart';

import 'tool_state.dart';

class ToolStateScope extends InheritedWidget {
  const ToolStateScope({super.key, required this.state, required super.child});

  final ToolState state;

  static ToolState? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ToolStateScope>()?.state;
  }

  @override
  bool updateShouldNotify(ToolStateScope oldWidget) {
    return oldWidget.state != state;
  }
}
