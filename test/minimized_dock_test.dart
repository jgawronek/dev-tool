import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Reproduces the runtime crash seen after redesigning the minimized dock:
//   'package:flutter/.../framework.dart': Failed assertion:
//   '_dependents.isEmpty': is not true
//
// A chip wraps a Theme-dependent Tooltip around a tappable surface, and the
// tap removes the chip itself from the list (mimicking "restore panel"). If the
// chip's subtree depends on the Theme (InheritedWidget) and is torn down while a
// Tooltip overlay entry is mid-flight, the Theme's InheritedElement deactivates
// with a lingering dependent and the assertion fires.

/// Mirror of the real `_MinimizedChip`: Tooltip → Material → InkWell, reading
/// the Theme in build (the real widget calls `context.appColors`, which is
/// `Theme.of(context)` under the hood).
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRestore});

  final String label;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme; // Theme dependency.
    return Tooltip(
      message: 'Restore $label',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onRestore,
          child: SizedBox(height: 26, width: 120, child: Center(child: Text(label))),
        ),
      ),
    );
  }
}

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  List<String> _items = ['JWT Debugger'];

  @override
  Widget build(BuildContext context) {
    final dock = Wrap(
      children: [
        for (final item in _items)
          _Chip(
            label: item,
            onRestore: () => setState(
              () => _items = _items.where((i) => i != item).toList(),
            ),
          ),
      ],
    );
    // The real workspace only renders the dock (under its own Theme-bearing
    // subtree) when there ARE minimized panels — so restoring the last one
    // removes a Theme boundary in the same frame the tooltip is live.
    return _items.isEmpty
        ? const SizedBox.shrink()
        : Theme(data: ThemeData.dark(), child: dock);
  }
}

void main() {
  testWidgets('tapping a tooltipped chip that removes itself does not assert', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _Host())),
    );

    // Hover and wait for the tooltip overlay to actually appear (Theme-
    // dependent), then tap to restore — removing the chip AND its Theme
    // boundary while the overlay is still live.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('JWT Debugger')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // tooltip now showing
    expect(find.text('Restore JWT Debugger'), findsOneWidget);

    await tester.tap(find.text('JWT Debugger'));
    await tester.pumpAndSettle();

    expect(find.text('JWT Debugger'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
