import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A sample callback belongs to one mounted tool instance, not to its registry
/// entry. Null callbacks keep supported actions visible while disabled.
class ToolSampleCommand {
  const ToolSampleCommand(this.onPressed);

  final VoidCallback? onPressed;
}

class ToolSampleHost extends StatefulWidget {
  const ToolSampleHost({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    ValueListenable<ToolSampleCommand?> sample,
  )
  builder;

  @override
  State<ToolSampleHost> createState() => _ToolSampleHostState();
}

class _ToolSampleHostState extends State<ToolSampleHost> {
  final _controller = _SampleController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SampleScope(
    controller: _controller,
    child: Builder(builder: (context) => widget.builder(context, _controller)),
  );
}

/// Wrap a tool's content to expose its sample action in the page heading.
class ToolSampleAction extends StatefulWidget {
  const ToolSampleAction({
    super.key,
    required this.onPressed,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  State<ToolSampleAction> createState() => _ToolSampleActionState();
}

class _ToolSampleActionState extends State<ToolSampleAction> {
  _SampleController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context
        .dependOnInheritedWidgetOfExactType<_SampleScope>()
        ?.controller;
    if (_controller != controller) {
      _controller?.remove(this);
      _controller = controller;
    }
    _controller?.register(this, widget.onPressed);
  }

  @override
  void didUpdateWidget(ToolSampleAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller?.register(this, widget.onPressed);
  }

  @override
  void dispose() {
    _controller?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SampleScope extends InheritedWidget {
  const _SampleScope({required this.controller, required super.child});

  final _SampleController controller;

  @override
  bool updateShouldNotify(_SampleScope oldWidget) =>
      controller != oldWidget.controller;
}

class _SampleController extends ValueNotifier<ToolSampleCommand?> {
  _SampleController() : super(null);

  Object? _owner;
  ToolSampleCommand? _pending;
  bool _scheduled = false;
  bool _disposed = false;

  void register(Object owner, VoidCallback? callback) {
    if (_disposed) return;
    assert(_owner == null || identical(_owner, owner));
    _owner = owner;
    _pending = ToolSampleCommand(callback);
    _scheduleUpdate();
  }

  void remove(Object owner) {
    if (_disposed || !identical(_owner, owner)) return;
    _owner = null;
    _pending = null;
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    if (_scheduled) return;
    _scheduled = true;
    // Registration happens while descendants build; notify the heading only
    // after that frame, coalescing updates and never rebuilding an ancestor
    // during build or disposal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed) return;
      if ((value == null) != (_pending == null) ||
          value?.onPressed != _pending?.onPressed) {
        value = _pending;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
