import 'dart:typed_data';

class TextChange {
  const TextChange(this.value, {required this.added});
  final String value;
  final bool added;
}

/// Order-sensitive comparison that preserves duplicate occurrences.
/// Large changed spans are reported in full to bound memory and CPU work.
List<TextChange> sequenceChanges(List<String> left, List<String> right) {
  var start = 0;
  while (start < left.length &&
      start < right.length &&
      left[start] == right[start]) {
    start++;
  }
  var leftEnd = left.length;
  var rightEnd = right.length;
  while (leftEnd > start &&
      rightEnd > start &&
      left[leftEnd - 1] == right[rightEnd - 1]) {
    leftEnd--;
    rightEnd--;
  }
  final a = left.sublist(start, leftEnd);
  final b = right.sublist(start, rightEnd);
  final changes = <TextChange>[];
  if (a.length * b.length > 1000000) {
    changes.addAll(a.map((v) => TextChange(v, added: false)));
    changes.addAll(b.map((v) => TextChange(v, added: true)));
    return changes;
  }
  final columns = b.length + 1;
  final lengths = Uint32List((a.length + 1) * columns);
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      final down = lengths[(i + 1) * columns + j];
      final next = lengths[i * columns + j + 1];
      lengths[i * columns + j] = a[i] == b[j]
          ? lengths[(i + 1) * columns + j + 1] + 1
          : (down >= next ? down : next);
    }
  }
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      i++;
      j++;
    } else if (i < a.length &&
        (j == b.length ||
            lengths[(i + 1) * columns + j] >= lengths[i * columns + j + 1])) {
      changes.add(TextChange(a[i++], added: false));
    } else {
      changes.add(TextChange(b[j++], added: true));
    }
  }
  return changes;
}
