import 'package:flutter_test/flutter_test.dart';
import 'package:dev_tool/services/text_diff_service.dart';

void main() {
  test('detects ordering and duplicate changes', () {
    final reordered = sequenceChanges(['a', 'b'], ['b', 'a']);
    expect(reordered.map((c) => '${c.added}:${c.value}'), ['false:a', 'true:a']);
    final repeated = sequenceChanges(['a', 'a'], ['a']);
    expect(repeated.single.value, 'a');
    expect(repeated.single.added, isFalse);
    expect(sequenceChanges(['a'], ['a']), isEmpty);
    expect(sequenceChanges([], ['🙂']).single.added, isTrue);
  });
  test('bounds large changed spans without dropping changes', () {
    final changes = sequenceChanges(List.filled(2000, 'a'), List.filled(2000, 'b'));
    expect(changes.length, 4000);
    expect(changes.where((c) => c.added).length, 2000);
  });
}
