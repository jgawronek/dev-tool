/// Classical cipher identification, decoding, and brute force.
///
/// Pure logic with no Flutter dependency, so it is safe to run in an isolate.
library;

import 'dart:math';

/// The single-step ciphers the tool can apply.
enum CipherKind {
  rot13('ROT13'),
  rot47('ROT47'),
  caesar('Caesar'),
  atbash('Atbash'),
  reverse('Reverse'),
  railFence('Rail Fence'),
  bacon('Bacon'),
  morse('Morse'),
  vigenere('Vigenère'),
  xor('XOR');

  const CipherKind(this.label);

  final String label;

  /// Ciphers that need no key or parameter beyond a shift.
  bool get needsShift =>
      this == CipherKind.caesar || this == CipherKind.rot47;

  bool get needsKey => this == CipherKind.vigenere || this == CipherKind.xor;
}

/// One decode attempt and how readable its output looks.
class CipherCandidate {
  const CipherCandidate({
    required this.cipher,
    required this.output,
    required this.score,
  });

  final String cipher;
  final String output;

  /// 0-1; higher means more likely to be real text.
  final double score;

  String get scoreLabel => '${(score * 100).round()}%';
}

/// Options for a chosen decode.
class CipherOptions {
  const CipherOptions({
    this.shift = 13,
    this.key = '',
    this.rails = 3,
    this.baconVariant = 'A/B',
  });

  final int shift;
  final String key;
  final int rails;
  final String baconVariant;
}

/// Applies [kind] to [input] with [options].
String decodeCipher(String input, CipherKind kind, CipherOptions options) {
  return switch (kind) {
    CipherKind.rot13 => _rot13(input),
    CipherKind.rot47 => _rot47(input),
    CipherKind.caesar => _caesar(input, options.shift, decode: true),
    CipherKind.atbash => _atbash(input),
    CipherKind.reverse => input.split('').reversed.join(),
    CipherKind.railFence => _railFenceDecode(input, max(2, options.rails)),
    CipherKind.bacon => _bacon(input, options.baconVariant),
    CipherKind.morse => _morse(input),
    CipherKind.vigenere => _vigenere(input, options.key, decode: true),
    CipherKind.xor => _xor(input, options.key),
  };
}

/// Encodes with [kind]; for the ciphers that are their own inverse this is
/// the same call as [decodeCipher], but the additive ones need the mirrored
/// shift so the tool can be used in either direction.
String encodeCipher(String input, CipherKind kind, CipherOptions options) {
  return switch (kind) {
    CipherKind.caesar => _caesar(input, 26 - (options.shift % 26)),
    CipherKind.vigenere => _vigenere(input, options.key),
    CipherKind.xor => _xor(input, options.key),
    _ => decodeCipher(input, kind, options),
  };
}

/// Tries every single-step cipher and returns the readable hits first.
///
/// This is the tool's answer to CyberChef's "Magic" wand.
List<CipherCandidate> identifyCipher(String input) {
  if (input.trim().isEmpty) return const [];
  final results = <CipherCandidate>[];

  for (final kind in CipherKind.values) {
    final options = CipherOptions(
      shift: 13,
      key: kind == CipherKind.bacon ? 'AB' : 'key',
      rails: 3,
    );
    String output;
    try {
      output = decodeCipher(input, kind, options);
    } catch (_) {
      continue;
    }
    final score = readability(output);
    if (score >= 0.45) {
      results.add(CipherCandidate(cipher: kind.label, output: output, score: score));
    }
  }

  results.sort((a, b) => b.score.compareTo(a.score));
  return results;
}

/// Brute-forces the classic CTF ciphers, best reads first.
///
/// Covers all 25 Caesar shifts, ROT47, all 26 single-letter Vigenere keys, and
/// every single-byte repeating XOR key.
List<CipherCandidate> bruteForceCipher(String input, {int maxResults = 25}) {
  if (input.trim().isEmpty) return const [];
  final results = <CipherCandidate>[];

  void consider(String cipher, String output, {double penalty = 0}) {
    final score = readability(output) - penalty;
    if (readability(output) >= 0.35) {
      results.add(CipherCandidate(cipher: cipher, output: output, score: score));
    }
  }

  for (var shift = 1; shift < 26; shift++) {
    consider('Caesar shift $shift', _caesar(input, shift, decode: true));
  }
  consider('ROT47', _rot47(input));

  // A single-letter Vigenere key is arithmetically identical to a Caesar
  // shift, so searching two-letter keys adds coverage instead of duplicating
  // the results above.
  if (input.isNotEmpty) {
    for (var first = 0; first < 26; first++) {
      for (var second = 0; second < 26; second++) {
        final key = String.fromCharCode(97 + first) + String.fromCharCode(97 + second);
        // A two-letter key is a strictly more complex explanation than a
        // single Caesar shift, so it loses ties; unigram scoring cannot
        // separate them reliably on short samples.
        consider(
          'Vigenere key "$key"',
          _vigenere(input, key, decode: true),
          penalty: 0.01,
        );
      }
    }
  }

  if (input.length > 1) {
    for (var key = 1; key < 256; key++) {
      consider('XOR 0x${key.toRadixString(16).padLeft(2, '0')}', _xor(input, String.fromCharCode(key)));
    }
  }

  results.sort((a, b) => b.score.compareTo(a.score));
  return results.take(maxResults).toList();
}

/// Scores how much [text] reads like English prose, from 0 to 1.
///
/// Combines a printable ratio, letter-frequency closeness, a common-word
/// bonus, and a penalty for long printable-but-meaningless runs.
double readability(String text) {
  if (text.isEmpty) return 0;
  final sample = text.length > 4000 ? text.substring(0, 4000) : text;
  final codeUnits = sample.codeUnits;

  var printable = 0;
  var letters = 0;
  var letterCounts = List<int>.filled(26, 0);
  for (final unit in codeUnits) {
    if ((unit >= 0x20 && unit < 0x7f) || unit == 0x0a || unit == 0x0d || unit == 0x09) {
      printable++;
    }
    final lower = _toLowerAscii(unit);
    if (lower != null) {
      letters++;
      letterCounts[lower - 97]++;
    }
  }
  if (printable / sample.length < 0.85) return 0;

  // No letters at all is not prose, but short symbol-only strings such as a
  // decoded flag fragment still deserve a small non-zero score.
  if (letters == 0) return 0.15;

  // Chi-squared distance from English letter frequencies, normalised per
  // letter so short samples are not penalised for having few counts.
  var chi = 0.0;
  for (var i = 0; i < 26; i++) {
    final expected = _englishFrequency[i] / 100 * letters;
    final difference = letterCounts[i] - expected;
    chi += difference * difference / max(expected, 0.5);
  }
  final averageChi = chi / 26;
  // English prose lands near an average deviation of 2-8; random text is
  // far higher, so a reciprocal curve separates them cleanly.
  final frequencyScore = 1 / (1 + averageChi / 12);

  final lowerText = ' $_lowerAscii(sample) ';
  var wordHits = 0;
  for (final word in _commonWords) {
    var index = lowerText.indexOf(word);
    while (index >= 0) {
      wordHits++;
      index = lowerText.indexOf(word, index + word.length);
    }
  }
  // One common word in a short sample is a strong signal, so this saturates
  // quickly rather than scaling with length.
  final wordScore = (wordHits / 2).clamp(0.0, 1.0);

  // Reward the presence of spaces and commas, which monoalphabetic ciphers
  // leave intact but base64/hex noise lacks.
  var spacing = 0;
  for (final unit in codeUnits) {
    if (unit == 0x20 || unit == 0x2c || unit == 0x2e || unit == 0x0a) spacing++;
  }
  final spacingScore = (spacing / sample.length / 0.15).clamp(0.0, 1.0);

  // Monoalphabetic ciphers leave spacing intact, so decoded prose always has
  // spaces and commas while base64/hex noise never does. Gating on that
  // keeps short random letter strings from scoring like English.
  final structure = 0.3 + 0.7 * spacingScore;
  final base = frequencyScore * 0.40 +
      wordScore * 0.30 +
      (letters / sample.length).clamp(0.0, 1.0) * 0.30;
  return (base * structure).clamp(0.0, 1.0);
}

String _rot13(String input) {
  final buffer = StringBuffer();
  for (final unit in input.codeUnits) {
    if (unit >= 65 && unit <= 90) {
      buffer.writeCharCode((unit - 65 + 13) % 26 + 65);
    } else if (unit >= 97 && unit <= 122) {
      buffer.writeCharCode((unit - 97 + 13) % 26 + 97);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// ROT47 covers printable ASCII 33-126, which is why it reaches digits and
/// punctuation that ROT13 leaves alone.
String _rot47(String input) {
  final buffer = StringBuffer();
  for (final unit in input.codeUnits) {
    if (unit >= 33 && unit <= 126) {
      buffer.writeCharCode(((unit - 33 + 47) % 94) + 33);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

String _caesar(String input, int shift, {bool decode = false}) {
  final normalized = shift % 26;
  // Decoding reverses the shift, so a -3 encode is a +3 decode.
  final delta = decode ? -normalized : normalized;
  final buffer = StringBuffer();
  for (final unit in input.codeUnits) {
    if (unit >= 65 && unit <= 90) {
      buffer.writeCharCode((unit - 65 + delta) % 26 + 65);
    } else if (unit >= 97 && unit <= 122) {
      buffer.writeCharCode((unit - 97 + delta) % 26 + 97);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

String _atbash(String input) {
  final buffer = StringBuffer();
  for (final unit in input.codeUnits) {
    if (unit >= 65 && unit <= 90) {
      buffer.writeCharCode(90 - (unit - 65));
    } else if (unit >= 97 && unit <= 122) {
      buffer.writeCharCode(122 - (unit - 97));
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// Standard zigzag rail-fence decryption.
///
/// Splits the ciphertext back into per-rail queues using the zigzag pattern,
/// then walks the pattern again pulling one character from each rail in turn.
String _railFenceDecode(String input, int railCount) {
  if (input.length < 2 || railCount < 2) return input;
  final pattern = _railPattern(input.length, railCount);
  final counts = List<int>.filled(railCount, 0);
  for (final rail in pattern) {
    counts[rail]++;
  }
  final queues = <String>[];
  var offset = 0;
  for (var rail = 0; rail < railCount; rail++) {
    queues.add(input.substring(offset, offset + counts[rail]));
    offset += counts[rail];
  }
  final cursors = List<int>.filled(railCount, 0);
  final buffer = StringBuffer();
  for (final rail in pattern) {
    buffer.write(queues[rail][cursors[rail]]);
    cursors[rail]++;
  }
  return buffer.toString();
}

List<int> _railPattern(int length, int rails) {
  final pattern = List<int>.filled(length, 0);
  var rail = 0;
  var direction = 1;
  for (var i = 0; i < length; i++) {
    pattern[i] = rail;
    if (rail == 0) direction = 1;
    if (rail == rails - 1) direction = -1;
    rail += direction;
  }
  return pattern;
}

/// Bacon's biliteral cipher.
///
/// `A` is 0 and `B` is 1. In the classic 24-letter variant `C` stands for
/// I/J and `D` for U/V; the 26-letter variant drops those so `C`/`D` decode
/// normally.
String _bacon(String input, String variant) {
  final upper = input.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (upper.isEmpty) {
    throw const FormatException('Bacon needs only A/B letters.');
  }
  final classic = variant == 'Classic 24';
  final buffer = StringBuffer();
  for (var i = 0; i + 5 <= upper.length; i += 5) {
    final group = upper.substring(i, i + 5);
    var value = 0;
    for (var j = 0; j < 5; j++) {
      final char = group[j];
      final bit = switch (char) {
        'A' || '0' => 0,
        'B' || '1' => 1,
        'C' => classic ? 0 : null,
        'D' => classic ? 1 : null,
        _ => throw FormatException('Invalid Bacon character "$char".'),
      };
      if (bit == null) {
        throw FormatException(
          'Letter "$char" needs the Classic 24 variant.',
        );
      }
      value = (value << 1) | bit;
    }
    buffer.write(value <= 25 ? String.fromCharCode(65 + value) : '?');
  }
  final result = buffer.toString();
  if (result.isEmpty) {
    throw const FormatException('Need at least five Bacon letters.');
  }
  return result;
}

const _morseTable = <String, String>{
  '.-': 'A', '-...': 'B', '-.-.': 'C', '-..': 'D', '.': 'E',
  '..-.': 'F', '--.': 'G', '....': 'H', '..': 'I', '.---': 'J',
  '-.-': 'K', '.-..': 'L', '--': 'M', '-.': 'N', '---': 'O',
  '.--.': 'P', '--.-': 'Q', '.-.': 'R', '...': 'S', '-': 'T',
  '..-': 'U', '...-': 'V', '.--': 'W', '-..-': 'X', '-.--': 'Y',
  '--..': 'Z', '.----': '1', '..---': '2', '...--': '3', '....-': '4',
  '.....': '5', '-....': '6', '--...': '7', '---..': '8', '----.': '9',
  '-----': '0', '.-.-.-': '.', '--..--': ',', '..--..': '?',
  '.----.': "'", '-.-.--': '!', '-..-.': '/', '-.--.': '(',
  '-.--.-': ')', '.-...': '&', '---...': ':', '-.-.-.': ';',
  '-...-': '=', '.-.-.': '+', '-....-': '-', '..--.-': '_',
  '...-..-': r'$', '.--.-.': '@', '........': '<SOS>',
};

/// Decodes Morse, also accepting "|" or "/" as a word separator.
String _morse(String input) {
  final normalized = input.trim().toUpperCase();
  if (normalized.isEmpty) {
    throw const FormatException('Enter Morse code.');
  }
  final buffer = StringBuffer();
  // `/`, `|` and a run of spaces all separate words and yield a space; the
  // dot/dash tokens themselves are always whitespace-delimited.
  final pattern = RegExp(r'\s*([A-Z0-9.\-/]+)\s*(?:(/|\|)\s*)?');
  for (final match in pattern.allMatches(normalized)) {
    final token = match.group(1)!;
    final separator = match.group(2);
    if (token == '<>' || token == '=+') {
      buffer.write(' ');
    } else {
      final letter = _morseTable[token];
      if (letter == null) {
        throw FormatException('Unknown Morse sequence "$token".');
      }
      buffer.write(letter);
    }
    if (separator != null) buffer.write(' ');
  }
  final result = buffer.toString();
  if (result.isEmpty) {
    throw const FormatException('No Morse sequences found.');
  }
  return result;
}

String _vigenere(String input, String key, {bool decode = false}) {
  final keyLetters = _lettersOnly(key);
  if (keyLetters.isEmpty) {
    throw const FormatException('Vigenere needs a key.');
  }
  final buffer = StringBuffer();
  var index = 0;
  for (final unit in input.codeUnits) {
    final shift = keyLetters[index % keyLetters.length];
    final delta = decode ? -shift : shift;
    if (unit >= 65 && unit <= 90) {
      buffer.writeCharCode((unit - 65 + delta) % 26 + 65);
      index++;
    } else if (unit >= 97 && unit <= 122) {
      buffer.writeCharCode((unit - 97 + delta) % 26 + 97);
      index++;
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// Repeating-key XOR; the key is interpreted as raw code units, which lets a
/// single-byte key be typed as a character and a hex key be typed as-is.
String _xor(String input, String key) {
  if (key.isEmpty) {
    throw const FormatException('XOR needs a key.');
  }
  final keyUnits = key.codeUnits;
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    buffer.writeCharCode(input.codeUnitAt(i) ^ keyUnits[i % keyUnits.length]);
  }
  return buffer.toString();
}

List<int> _lettersOnly(String text) {
  final out = <int>[];
  for (final unit in text.toLowerCase().codeUnits) {
    if (unit >= 97 && unit <= 122) {
      out.add(unit - 97);
    }
  }
  return out;
}

int? _toLowerAscii(int unit) {
  if (unit >= 65 && unit <= 90) return unit + 32;
  if (unit >= 97 && unit <= 122) return unit;
  return null;
}

String _lowerAscii(String text) {
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    final lower = _toLowerAscii(unit);
    buffer.writeCharCode(lower ?? unit);
  }
  return buffer.toString();
}

/// Relative letter frequencies for English prose, in percent.
const _englishFrequency = [
  8.167, 1.492, 2.782, 4.253, 12.702, 2.228, 2.015, 6.094, 6.966,
  0.153, 0.772, 4.025, 2.406, 6.749, 7.507, 1.929, 0.095, 5.987,
  6.327, 9.056, 2.758, 0.978, 2.360, 0.150, 1.974, 0.074,
];

const _commonWords = [
  ' the ', ' and ', ' that ', ' have ', ' for ', ' not ', ' with ',
  ' you ', ' this ', ' but ', ' are ', ' was ', ' flag', 'ctf', ' key',
];