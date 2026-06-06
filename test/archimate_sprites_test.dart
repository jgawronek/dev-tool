import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies every vendored ArchiMate sprite loads and renders through
// flutter_svg without throwing — these are Inkscape SVGs with group transforms,
// so confirm the parser handles them and the tint applies.
const _sprites = [
  'application-component',
  'application-service',
  'application-interface',
  'application-data-object',
  'application-function',
  'business-actor',
  'business-process',
  'business-service',
  'business-role',
  'business-object',
  'technology-node',
  'technology-device',
  'technology-service',
  'technology-artifact',
  'motivation-requirement',
  'motivation-goal',
];

void main() {
  testWidgets('all vendored ArchiMate sprites parse and render tinted', (
    tester,
  ) async {
    for (final name in _sprites) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SvgPicture.asset(
                'assets/archimate/$name.svg',
                width: 15,
                height: 15,
                colorFilter: const ColorFilter.mode(
                  Colors.black,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      );
      // Let the async asset load + SVG parse complete.
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$name.svg failed to render',
      );
      expect(find.byType(SvgPicture), findsOneWidget);
    }
  });
}
