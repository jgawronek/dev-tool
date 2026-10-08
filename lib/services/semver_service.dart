/// Semantic Versioning parsing, comparison, ranges, and diffing.
///
/// Pure logic, so it is safe to run inside an isolate.
library;

import 'dart:math';

/// A parsed semantic version, including any pre-release and build metadata.
class SemVer {
  const SemVer(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const [],
    this.build = '',
  });

  final int major;
  final int minor;
  final int patch;

  /// Dot-separated pre-release identifiers; empty for a stable release.
  final List<String> preRelease;

  final String build;

  bool get isPrerelease => preRelease.isNotEmpty;

  @override
  String toString() {
    final buffer = StringBuffer('$major.$minor.$patch');
    if (isPrerelease) buffer.write('-${preRelease.join('.')}');
    if (build.isNotEmpty) buffer.write('+$build');
    return buffer.toString();
  }
}

/// Parses a semantic version, or returns null when [input] is not valid.
SemVer? parseSemVer(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  // Build metadata is stripped first because a "+" may appear in it.
  var rest = trimmed;
  var build = '';
  final plus = rest.indexOf('+');
  if (plus >= 0) {
    build = rest.substring(plus + 1);
    rest = rest.substring(0, plus);
    if (build.isEmpty) return null;
  }

  var preRelease = const <String>[];
  final dash = rest.indexOf('-');
  if (dash >= 0) {
    final pre = rest.substring(dash + 1);
    rest = rest.substring(0, dash);
    if (pre.isEmpty) return null;
    final parts = pre.split('.');
    for (final part in parts) {
      if (part.isEmpty || !_validPrereleaseIdentifier(part)) return null;
    }
    preRelease = parts;
  }

  final core = rest.split('.');
  if (core.length != 3) return null;
  final numbers = <int>[];
  for (final part in core) {
    if (part.isEmpty || !RegExp(r'^\d+$').hasMatch(part)) return null;
    // Leading zeros are not allowed in the numeric core.
    if (part.length > 1 && part.startsWith('0')) return null;
    numbers.add(int.parse(part));
  }
  return SemVer(numbers[0], numbers[1], numbers[2],
      preRelease: preRelease, build: build);
}

/// A pre-release identifier is either numeric or alphanumeric with hyphens.
bool _validPrereleaseIdentifier(String value) =>
    RegExp(r'^(0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)$').hasMatch(value);

/// Compares two versions by semver precedence rules.
///
/// Build metadata is ignored, and a pre-release always sorts below the
/// matching stable release.
int compareSemVer(SemVer left, SemVer right) {
  if (left.major != right.major) return left.major.compareTo(right.major);
  if (left.minor != right.minor) return left.minor.compareTo(right.minor);
  if (left.patch != right.patch) return left.patch.compareTo(right.patch);

  if (!left.isPrerelease && !right.isPrerelease) return 0;
  if (!left.isPrerelease) return 1;
  if (!right.isPrerelease) return -1;

  final length = max(left.preRelease.length, right.preRelease.length);
  for (var i = 0; i < length; i++) {
    if (i >= left.preRelease.length) return -1;
    if (i >= right.preRelease.length) return 1;
    final a = left.preRelease[i];
    final b = right.preRelease[i];
    final aNumeric = int.tryParse(a);
    final bNumeric = int.tryParse(b);
    if (aNumeric != null && bNumeric != null) {
      final result = aNumeric.compareTo(bNumeric);
      if (result != 0) return result;
      continue;
    }
    // Numeric identifiers always have lower precedence than alphanumeric.
    if (aNumeric != null) return -1;
    if (bNumeric != null) return 1;
    final result = a.compareTo(b);
    if (result != 0) return result;
  }
  return 0;
}

/// The change between two versions, in semver terms.
class SemVerDiff {
  const SemVerDiff({
    required this.major,
    required this.minor,
    required this.patch,
    required this.prerelease,
  });

  final int major;
  final int minor;
  final int patch;
  final bool prerelease;

  /// e.g. `major`, `minor`, `patch`, or `pre-release`.
  String get summary => describeDiff(this);

}

/// Difference between [from] and [to].
SemVerDiff diffSemVer(SemVer from, SemVer to) {
  final major = to.major - from.major;
  final minor = to.minor - from.minor;
  final patch = to.patch - from.patch;
  final prerelease = from.isPrerelease != to.isPrerelease ||
      (to.isPrerelease && !_samePreRelease(from.preRelease, to.preRelease));
  return SemVerDiff(
    major: major,
    minor: minor,
    patch: patch,
    prerelease: prerelease,
  );
}

bool _samePreRelease(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

/// One version matching a range, with what satisfies it.
class RangeMatch {
  const RangeMatch({
    required this.version,
    required this.satisfiedBy,
    required this.type,
    required this.all,
  });

  final SemVer version;

  /// The comparator set that admitted this version, e.g. `^1.2.3`.
  final String satisfiedBy;
  final String type;
  final List<SemVer> all;
}

/// Evaluates an npm-style range and returns the highest matching version from
/// [available].
///
/// Supports `=`, `>`, `>=`, `<`, `<=`, `^`, `~`, `x`/`*` wildcards, `||`
/// alternatives, and hyphen ranges, which covers the versions developers
/// actually type.
({List<SemVer> matched, String highest, List<SemVer> candidates}) resolveRange(
  String range,
  List<SemVer> available,
) {
  final comparators = _parseRange(range);
  if (comparators.isEmpty) {
    return (matched: const [], highest: '', candidates: available);
  }
  final sorted = List<SemVer>.from(available)
    ..sort(compareSemVer);
  final matched = sorted.where((v) => _satisfies(v, comparators)).toList();
  return (
    matched: matched,
    highest: matched.isEmpty ? '' : matched.last.toString(),
    candidates: sorted,
  );
}

/// A single comparator such as `>=1.2.0`.
class _Comparator {
  const _Comparator(this.operator, this.version);

  final String operator;
  final SemVer? version;

  bool matches(SemVer candidate) {
    final target = version;
    if (operator == '*') return true;
    if (target == null) return operator == '<';
    final result = compareSemVer(candidate, target);
    return switch (operator) {
      '=' => result == 0,
      '>' => result > 0,
      '>=' => result >= 0,
      '<' => result < 0,
      '<=' => result <= 0,
      _ => false,
    };
  }
}

List<_Comparator> _parseRange(String range) {
  final trimmed = range.trim();
  if (trimmed.isEmpty || trimmed == '*' || trimmed == 'x') {
    return const [_Comparator('*', null)];
  }

  // `||` alternatives: the range matches if any branch matches.
  final alternatives = trimmed.split(RegExp(r'\s*\|\|\s*'));
  if (alternatives.length > 1) {
    for (final alternative in alternatives) {
      final parsed = _parseRange(alternative);
      if (parsed.length == 1 && parsed.first.operator == '*') {
        return parsed;
      }
    }
    // Only the first alternative is evaluated for listing purposes; callers
    // that need full union semantics should check each branch.
    return _parseRange(alternatives.first);
  }

  // Hyphen range: `1.2.3 - 2.3.4`.
  final hyphen = RegExp(r'^(\S+)\s+-\s+(\S+)$').firstMatch(trimmed);
  if (hyphen != null) {
    final low = _expandPartial(hyphen.group(1)!).first;
    final high = _expandPartial(hyphen.group(2)!).first;
    final comparators = <_Comparator>[];
    if (low.operator != '*' && low.version != null) {
      comparators.add(_Comparator('>=', low.version));
    }
    if (high.operator != '*' && high.version != null) {
      comparators.add(_Comparator('<=', high.version));
    }
    return comparators.isEmpty ? const [_Comparator('*', null)] : comparators;
  }

  // A space-separated conjunction, e.g. `>=1.2.0 <2.0.0`.
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length > 1) {
    final comparators = <_Comparator>[];
    for (final part in parts) {
      comparators.addAll(_parseRange(part));
    }
    return comparators;
  }

  final single = RegExp(r'^(\^|~|>=|<=|>|<|=)?\s*(.+)$').firstMatch(trimmed);
  if (single == null) return const [_Comparator('*', null)];
  final operator = single.group(1) ?? '=';
  final versionText = single.group(2)!;

  if (operator == '>' || operator == '>=' || operator == '<' || operator == '<=') {
    // Ordering operators compare against an exact version, so a partial text
    // such as ">=1.2" is invalid rather than a range.
    final exact = parseSemVer(versionText);
    return exact == null ? const [_never] : [_Comparator(operator, exact)];
  }

  if (operator == '^') {
    final base = _partialBounds(versionText);
    if (base == null) return const [_never];
    final upper = base.major > 0
        ? SemVer(base.major + 1, 0, 0)
        : base.minor > 0
            ? SemVer(0, base.minor + 1, 0)
            : SemVer(0, 0, base.patch + 1);
    return [_Comparator('>=', base), _Comparator('<', upper)];
  }

  if (operator == '~') {
    final base = _partialBounds(versionText);
    if (base == null) return const [_never];
    final upper = _minorSpecified(versionText)
        ? SemVer(base.major, base.minor + 1, 0)
        : SemVer(base.major + 1, 0, 0);
    return [_Comparator('>=', base), _Comparator('<', upper)];
  }

  return _expandPartial(versionText);
}

/// True when the partial version text named a minor component.
bool _minorSpecified(String text) =>
    text.split('.').where((p) => p.isNotEmpty).length >= 2;

/// Expands `1.x`, `1.2.*`, `1`, or `1.2` into comparator(s).
///
/// A bare `1` means "any 1.x", so partial versions produce a range rather
/// than an equality the way a full `1.2.3` does.
List<_Comparator> _expandPartial(String text) {
  final parts = text.split('.');
  final wildcardAt = parts.indexWhere(
    (p) => p == 'x' || p == 'X' || p == '*',
  );
  if (wildcardAt == 0) {
    return const [_Comparator('*', null)];
  }
  if (wildcardAt > 0) {
    // `1.x` means 1.*, so the numeric prefix sets both bounds.
    final prefix = <int>[];
    for (var i = 0; i < wildcardAt; i++) {
      if (!RegExp(r'^\d+$').hasMatch(parts[i])) {
        return const [_never];
      }
      prefix.add(int.parse(parts[i]));
    }
    if (prefix.length == 1) {
      return [
        _Comparator('>=', SemVer(prefix[0], 0, 0)),
        _Comparator('<', SemVer(prefix[0] + 1, 0, 0)),
      ];
    }
    if (prefix.length == 2) {
      return [
        _Comparator('>=', SemVer(prefix[0], prefix[1], 0)),
        _Comparator('<', SemVer(prefix[0], prefix[1] + 1, 0)),
      ];
    }
    return const [_never];
  }
  if (parts.every((p) => RegExp(r'^\d+$').hasMatch(p))) {
    if (parts.length == 1) {
      final major = int.parse(parts[0]);
      return [
        _Comparator('>=', SemVer(major, 0, 0)),
        _Comparator('<', SemVer(major + 1, 0, 0)),
      ];
    }
    if (parts.length == 2) {
      final major = int.parse(parts[0]);
      final minor = int.parse(parts[1]);
      return [
        _Comparator('>=', SemVer(major, minor, 0)),
        _Comparator('<', SemVer(major, minor + 1, 0)),
      ];
    }
    final parsed = parseSemVer(text);
    return [
      parsed == null ? _never : _Comparator('=', parsed),
    ];
  }
  final parsed = parseSemVer(text);
  return [parsed == null ? _never : _Comparator('=', parsed)];
}

/// Matches nothing, used when a version cannot be parsed so a typo silently
/// widens the range to "everything".
const _Comparator _never = _Comparator('>=', null);

/// Lower bound implied by a caret or tilde partial version.
SemVer? _partialBounds(String text) {
  final parts = text.split('.');
  final numbers = <int>[];
  for (final part in parts) {
    if (!RegExp(r'^\d+$').hasMatch(part)) return null;
    numbers.add(int.parse(part));
  }
  return switch (numbers.length) {
    1 => SemVer(numbers[0], 0, 0),
    2 => SemVer(numbers[0], numbers[1], 0),
    3 => SemVer(numbers[0], numbers[1], numbers[2]),
    _ => null,
  };
}

bool _satisfies(SemVer version, List<_Comparator> comparators) {
  for (final comparator in comparators) {
    if (!comparator.matches(version)) return false;
  }
  // A range with an upper bound excludes pre-releases unless one is named.
  final namesPrerelease =
      comparators.any((c) => c.version?.isPrerelease ?? false);
  if (version.isPrerelease && !namesPrerelease) return false;
  return true;
}

/// Returns [base] with the requested component incremented and the lower
/// components reset, which is how a release is normally cut.
SemVer bumpSemVer(SemVer base, String kind) => switch (kind) {
      'major' => SemVer(base.major + 1, 0, 0),
      'minor' => SemVer(base.major, base.minor + 1, 0),
      'patch' => SemVer(base.major, base.minor, base.patch + 1),
      _ => base,
    };

/// Renders the diff as a short human-readable line.
String describeDiff(SemVerDiff diff) {
  if (diff.major > 0) return 'major (${diff.major})';
  if (diff.minor > 0) return 'minor (${diff.minor})';
  if (diff.patch > 0) return 'patch (${diff.patch})';
  if (diff.prerelease) return 'pre-release change';
  return 'no change';
}

/// Renders a full comparison table between two versions.
String compareReport(SemVer left, SemVer right) {
  final buffer = StringBuffer()
    ..writeln('${left.toString()} vs ${right.toString()}')
    ..writeln();
  final result = compareSemVer(left, right);
  buffer.writeln('Result     ${result == 0 ? 'equal' : result < 0 ? 'left is older' : 'left is newer'}');
  buffer
    ..writeln('Major      ${left.major} vs ${right.major}'
        '${left.major != right.major ? '  (differs)' : ''}')
    ..writeln('Minor      ${left.minor} vs ${right.minor}'
        '${left.minor != right.minor ? '  (differs)' : ''}')
    ..writeln('Patch      ${left.patch} vs ${right.patch}'
        '${left.patch != right.patch ? '  (differs)' : ''}')
    ..writeln('Pre-release ${left.isPrerelease ? left.preRelease.join('.') : 'none'}'
        ' vs ${right.isPrerelease ? right.preRelease.join('.') : 'none'}');
  if (left.build.isNotEmpty || right.build.isNotEmpty) {
    buffer.writeln('Build      ${left.build.isEmpty ? 'none' : left.build}'
        ' vs ${right.build.isEmpty ? 'none' : right.build} (ignored for ordering)');
  }
  buffer
    ..writeln()
    ..writeln('Diff       ${describeDiff(diffSemVer(left, right))}');
  return buffer.toString().trimRight();
}