import 'package:flutter/material.dart' show Size, TextField;
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/date_difference_service.dart';

import '../helpers/tool_harness.dart';

void main() {
  test('normalizes offsets and computes elapsed microseconds', () {
    final result = dateDifference(
      '2024-03-08T09:00:00.000001Z',
      '2024-03-09T10:30:00.000002+01:00',
    );
    expect(result.error, isNull);
    expect(result.report, contains('1 days, 0 hours, 30 minutes'));
    expect(result.report, contains('1 microseconds'));
    expect(result.report, contains('End is after start'));
  });

  test('reports reverse direction and identical instants', () {
    expect(
      dateDifference('2024-01-02T00:00:00Z', '2024-01-01T00:00:00Z').report,
      contains('End is before start'),
    );
    expect(
      dateDifference(
        '2024-01-01T00:00:00Z',
        '2023-12-31T19:00:00-05:00',
      ).report,
      contains('Same instant'),
    );
  });

  test('requires explicit time zones and valid dates', () {
    expect(
      dateDifference('', '2024-01-01T00:00:00Z').error,
      contains('both dates'),
    );
    expect(
      dateDifference('2024-01-01T00:00:00', '2024-01-02T00:00:00Z').error,
      contains('timezone'),
    );
    expect(
      dateDifference('not-a-dateZ', '2024-01-01T00:00:00Z').error,
      contains('Invalid ISO'),
    );
  });

  testWidgets('calculator updates output when end date changes', (
    tester,
  ) async {
    final h = ToolHarness(tester);
    await h.open('date_difference', surface: const Size(1450, 950));
    await tester.enterText(
      find.widgetWithText(TextField, 'Start (ISO 8601 + zone)'),
      '2024-01-01T00:00:00Z',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'End (ISO 8601 + zone)'),
      '2024-01-02T00:00:00Z',
    );
    await h.settle();
    expect(h.text('Elapsed time and UTC instants'), contains('1 days'));
    await tester.enterText(
      find.widgetWithText(TextField, 'End (ISO 8601 + zone)'),
      'invalid',
    );
    await h.settle();
    expect(h.text('Elapsed time and UTC instants'), isEmpty);
    expect(find.textContaining('timezone'), findsWidgets);
  });
}
