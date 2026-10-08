/// Leetspeak conversion in both directions.
///
/// Pure logic with no Flutter dependency, so it is safe to run in an isolate.
library;

/// How aggressively to fold characters back to plain letters.
enum LeetProfile {
  basic('Basic', 'Digits and the two most common symbols'),
  common('Common', 'Adds ! @ and the visual look-alikes'),
  aggressive('Aggressive', 'Every symbol that reads as a letter');

  const LeetProfile(this.label, this.note);

  final String label;
  final String note;

  /// Character map keyed by the leetspeak character.
  Map<String, String> get table {
    final map = <String, String>{'4': 'a', '3': 'e', '1': 'i', '0': 'o'};
    if (this == LeetProfile.basic) return map;

    map.addAll({
      '@': 'a',
      r'$': 's',
      '5': 's',
      '7': 't',
      '!': 'i',
      '|': 'i',
      '2': 'z',
    });
    if (this == LeetProfile.common) return map;

    // Look-alikes and rarer substitutions, applied only in the widest profile
    // because several of them are genuinely ambiguous.
    map.addAll({
      '8': 'b',
      '6': 'g',
      '9': 'g',
      '+': 't',
      '(': 'c',
      '<': 'c',
      '[': 'c',
      ')': 'o',
      ']': 'o',
      'q': 'q',
      '£': 'l',
      '¢': 'c',
      '€': 'e',
      'Ð': 'd',
      'Σ': 'e',
    });
    return map;
  }
}

/// Result of a leetspeak conversion.
class LeetOutcome {
  const LeetOutcome.success({
    required this.output,
    required this.replacements,
    required this.summary,
  }) : error = null;

  const LeetOutcome.failure(this.error)
    : output = '',
      replacements = const {},
      summary = '';

  final String output;

  /// How many characters each leet symbol replaced.
  final Map<String, int> replacements;
  final String summary;
  final String? error;
}

/// Folds [input] back to plain text using [profile].
LeetOutcome decodeLeetSync(String input, LeetProfile profile) {
  if (input.isEmpty) {
    return const LeetOutcome.failure('Enter some text to decode.');
  }
  final table = profile.table;
  final counts = <String, int>{};
  final buffer = StringBuffer();
  for (final unit in input.runes) {
    final char = String.fromCharCode(unit);
    final replacement = table[char];
    if (replacement != null) {
      buffer.write(replacement);
      counts.update(char, (v) => v + 1, ifAbsent: () => 1);
    } else {
      buffer.write(char);
    }
  }
  final total = counts.values.fold(0, (a, b) => a + b);
  return LeetOutcome.success(
    output: buffer.toString(),
    replacements: counts,
    summary: total == 0
        ? 'No leetspeak characters found'
        : '$total character${total == 1 ? '' : 's'} replaced '
            '(${counts.entries.map((e) => '${e.key}->${e.value}').join(', ')})',
  );
}

/// Renders [input] as leetspeak using [profile] and [intensity].
///
/// [intensity] is the percentage of eligible characters to substitute, from 0
/// to 100. Substitutions are spread evenly rather than clustered so the result
/// stays readable.
LeetOutcome encodeLeetSync(
  String input,
  LeetProfile profile,
  double intensity,
) {
  if (input.isEmpty) {
    return const LeetOutcome.failure('Enter some text to encode.');
  }
  final clamped = intensity.clamp(0, 100).toDouble();
  if (clamped == 0) {
    return LeetOutcome.success(
      output: input,
      replacements: const {},
      summary: 'Intensity is 0%, nothing substituted',
    );
  }

  // Candidate substitutions per letter, most recognisable first.
  const table = <String, List<String>>{
    'a': ['4', '@'],
    'b': ['8'],
    'c': ['(', '<', '['],
    'e': ['3'],
    'g': ['6', '9'],
    'i': ['1', '!', '|'],
    'l': ['1', '|', '£'],
    'o': ['0'],
    's': ['5', r'$'],
    't': ['7', '+'],
    'z': ['2'],
  };

  final counts = <String, int>{};
  final eligible = <int>[];
  final source = input.split('');
  for (var i = 0; i < source.length; i++) {
    if (table.containsKey(source[i].toLowerCase())) eligible.add(i);
  }
  if (eligible.isEmpty) {
    return LeetOutcome.success(
      output: input,
      replacements: const {},
      summary: 'No substitutable letters found',
    );
  }

  final target = (eligible.length * clamped / 100).round();
  // Spread the substitutions through the text rather than front-loading them.
  final stride = eligible.length / (target == 0 ? 1 : target);
  final chosen = <int>{};
  for (var k = 0; k < target; k++) {
    chosen.add(eligible[(k * stride).floor().clamp(0, eligible.length - 1)]);
  }

  for (final index in chosen) {
    final original = source[index];
    final options = table[original.toLowerCase()]!;
    final pick = options[chosen.length % options.length];
    source[index] = pick;
    counts.update(pick, (v) => v + 1, ifAbsent: () => 1);
  }

  final output = source.join();
  return LeetOutcome.success(
    output: output,
    replacements: counts,
    summary: '${counts.length} position${counts.length == 1 ? '' : 's'} '
        'substituted across ${eligible.length} eligible letters',
  );
}