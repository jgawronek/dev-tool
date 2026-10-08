/// Unix permission math for the chmod calculator.
///
/// Pure logic with no Flutter or `dart:io` dependency, so it is safe to run
/// inside an isolate.
library;

/// One permission class: user, group, or other.
enum ChmodClass {
  user('User', 'u'),
  group('Group', 'g'),
  other('Other', 'o');

  const ChmodClass(this.label, this.letter);

  final String label;
  final String letter;
}

/// The three rwx bits for a single class.
class PermissionBits {
  const PermissionBits({
    required this.read,
    required this.write,
    required this.execute,
  });

  const PermissionBits.none()
    : read = false,
      write = false,
      execute = false;

  const PermissionBits.all()
    : read = true,
      write = true,
      execute = true;

  final bool read;
  final bool write;
  final bool execute;

  PermissionBits copyWith({bool? read, bool? write, bool? execute}) =>
      PermissionBits(
        read: read ?? this.read,
        write: write ?? this.write,
        execute: execute ?? this.execute,
      );

  /// Octal digit 0-7 for this class.
  int get octal {
    var value = 0;
    if (read) value += 4;
    if (write) value += 2;
    if (execute) value += 1;
    return value;
  }

  /// Three-character symbolic form, e.g. `r-x`.
  String get symbolic {
    final buffer = StringBuffer();
    buffer.write(read ? 'r' : '-');
    buffer.write(write ? 'w' : '-');
    buffer.write(execute ? 'x' : '-');
    return buffer.toString();
  }

  PermissionBits inverted() =>
      PermissionBits(read: !read, write: !write, execute: !execute);

  @override
  bool operator ==(Object other) =>
      other is PermissionBits &&
      other.read == read &&
      other.write == write &&
      other.execute == execute;

  @override
  int get hashCode => Object.hash(read, write, execute);
}

/// A complete permission set plus the sticky/setid bits.
class ChmodInfo {
  const ChmodInfo({
    required this.user,
    required this.group,
    required this.other,
    required this.setuid,
    required this.setgid,
    required this.sticky,
    required this.octal,
    required this.symbolic,
  });

  final PermissionBits user;
  final PermissionBits group;
  final PermissionBits other;

  /// `u+s` — applies to files, changes the effective user on execution.
  final bool setuid;

  /// `g+s` — applies to directories, creates files owned by the group.
  final bool setgid;

  /// `+t` — on a directory, restricts deletion/rename to the file owner.
  final bool sticky;

  /// Full octal form, e.g. `4755` or `1777`.
  final String octal;

  /// Symbolic form, e.g. `rwxr-xr-x` or `rwsr-xr-t`.
  final String symbolic;

  ChmodInfo withClass(ChmodClass chmodClass, PermissionBits bits) {
    return switch (chmodClass) {
      ChmodClass.user => _copy(user: bits),
      ChmodClass.group => _copy(group: bits),
      ChmodClass.other => _copy(other: bits),
    };
  }

  ChmodInfo withBits({
    bool? setuid,
    bool? setgid,
    bool? sticky,
  }) {
    return _from(user, group, other,
        setuid: setuid ?? this.setuid,
        setgid: setgid ?? this.setgid,
        sticky: sticky ?? this.sticky);
  }

  ChmodInfo _copy({PermissionBits? user, PermissionBits? group, PermissionBits? other}) {
    return _from(
      user ?? this.user,
      group ?? this.group,
      other ?? this.other,
      setuid: setuid,
      setgid: setgid,
      sticky: sticky,
    );
  }

  ChmodInfo toggle(ChmodClass chmodClass) =>
      withClass(chmodClass, _bitsFor(chmodClass).inverted());

  ChmodInfo setAll(ChmodClass chmodClass, bool value) => withClass(
        chmodClass,
        value
            ? const PermissionBits.all()
            : const PermissionBits.none(),
      );

  PermissionBits _bitsFor(ChmodClass chmodClass) => switch (chmodClass) {
        ChmodClass.user => user,
        ChmodClass.group => group,
        ChmodClass.other => other,
      };

  /// One-line summary of what the mode means.
  String toReport() {
    final buffer = StringBuffer()
      ..writeln('Octal      $octal')
      ..writeln('Symbolic   $symbolic')
      ..writeln('User       ${user.octal}  ${user.symbolic}')
      ..writeln('Group      ${group.octal}  ${group.symbolic}')
      ..writeln('Other      ${other.octal}  ${other.symbolic}');
    if (setuid) buffer.writeln('Setuid     u+s  set-user-ID on execution');
    if (setgid) buffer.writeln('Setgid     g+s  group ownership / exec group');
    if (sticky) buffer.writeln('Sticky     +t   restricted delete/rename');
    return buffer.toString().trimRight();
  }

  static ChmodInfo _from(
    PermissionBits user,
    PermissionBits group,
    PermissionBits other, {
    required bool setuid,
    required bool setgid,
    required bool sticky,
  }) {
    final base = '${user.octal}${group.octal}${other.octal}';
    // The special bits form one leading octal digit (4/2/1), omitted entirely
    // when none are set.
    final special = (setuid ? 4 : 0) + (setgid ? 2 : 0) + (sticky ? 1 : 0);
    final octal = special == 0 ? base : '$special$base';
    final symbolic =
        '${_symbolicWith(user, setuid ? 's' : null, false)}'
        '${_symbolicWith(group, setgid ? 's' : null, false)}'
        '${_symbolicWith(other, null, sticky)}';
    return ChmodInfo(
      user: user,
      group: group,
      other: other,
      setuid: setuid,
      setgid: setgid,
      sticky: sticky,
      octal: octal,
      symbolic: symbolic,
    );
  }

  /// Builds the symbolic text for one class.
  ///
  /// `s` replaces the execute bit when setuid/setgid is set, and `S` when it
  /// is set without execute. Sticky likewise shows `t` or `T`.
  static String _symbolicWith(PermissionBits bits, String? special, bool sticky) {
    final buffer = StringBuffer();
    buffer.write(bits.read ? 'r' : '-');
    buffer.write(bits.write ? 'w' : '-');
    if (special != null) {
      buffer.write(bits.execute ? special : special.toUpperCase());
    } else if (sticky) {
      buffer.write(bits.execute ? 't' : 'T');
    } else {
      buffer.write(bits.execute ? 'x' : '-');
    }
    return buffer.toString();
  }
}

/// Result of a chmod parse or calculation.
class ChmodOutcome {
  const ChmodOutcome.success(this.info) : error = null;
  const ChmodOutcome.failure(this.error) : info = null;

  final ChmodInfo? info;
  final String? error;
}

/// Parses either an octal mode (`755`, `4755`) or symbolic (`rwxr-xr-x`).
///
/// Returns null when the input is not a recognised mode.
ChmodOutcome? parseChmod(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  if (RegExp(r'^[0-7]{3,4}$').hasMatch(trimmed)) {
    return ChmodOutcome.success(_fromOctal(trimmed));
  }

  // `S`/`T` are the uppercase forms `ls -l` shows for setuid/sticky without
  // the execute bit, so they must be accepted here too.
  final symbolic = RegExp(r'^[rwxXstugoST-]{9}$').hasMatch(trimmed);
  if (symbolic) {
    return ChmodOutcome.success(_fromSymbolic(trimmed));
  }

  // A single class form such as "755" is handled above; "a+rwx" style input
  // is accepted too, since that is what people paste from documentation.
  if (RegExp(r'^[ugoa]*[+=-][rwxXst]*$').hasMatch(trimmed) &&
      trimmed.length > 1) {
    return ChmodOutcome.success(_applyRelative(trimmed));
  }
  return null;
}

/// Builds the info for three octal digits plus optional special bits.
ChmodInfo chmodFromTriplets(
  int user,
  int group,
  int other, {
  bool setuid = false,
  bool setgid = false,
  bool sticky = false,
}) {
  return ChmodInfo._from(
    _bits(user),
    _bits(group),
    _bits(other),
    setuid: setuid,
    setgid: setgid,
    sticky: sticky,
  );
}

ChmodInfo _fromOctal(String value) {
  var digits = value;
  var setuid = false;
  var setgid = false;
  var sticky = false;

  if (digits.length == 4) {
    switch (digits[0]) {
      case '4':
        setuid = true;
      case '6':
        setuid = true;
        setgid = true;
      case '7':
        setuid = true;
        setgid = true;
        sticky = true;
      case '2':
        setgid = true;
      case '3':
        setgid = true;
        sticky = true;
      case '1':
        sticky = true;
      default:
        throw FormatException('Unknown special-bit prefix "${digits[0]}"');
    }
    digits = digits.substring(1);
  }
  return chmodFromTriplets(
    int.parse(digits[0]),
    int.parse(digits[1]),
    int.parse(digits[2]),
    setuid: setuid,
    setgid: setgid,
    sticky: sticky,
  );
}

ChmodInfo _fromSymbolic(String value) {
  final parts = value.split('');
  var setuid = false;
  var setgid = false;
  var sticky = false;

  var info = chmodFromTriplets(0, 0, 0);
  for (final entry in [
    [ChmodClass.user, parts.sublist(0, 3)],
    [ChmodClass.group, parts.sublist(3, 6)],
    [ChmodClass.other, parts.sublist(6, 9)],
  ]) {
    final chmodClass = entry[0] as ChmodClass;
    final chars = entry[1] as List<String>;
    var read = false, write = false, execute = false;
    var specialChar = '';
    for (final char in chars) {
      switch (char) {
        case 'r':
          read = true;
        case 'w':
          write = true;
        case 'x':
          execute = true;
        case 'X':
          // Capital X means execute only for directories; the calculator
          // treats it as execute so the mode is complete either way.
          execute = true;
        case 's':
          specialChar = 's';
          execute = true;
        case 'S':
          // Setuid without the execute bit; `s` is replaced by `S`.
          specialChar = 's';
        case 't':
          specialChar = 't';
          execute = true;
        case 'T':
          // Sticky without the execute bit; `t` is replaced by `T`.
          specialChar = 't';
        default:
          break;
      }
    }
    info = info.withClass(
      chmodClass,
      PermissionBits(read: read, write: write, execute: execute),
    );
    if (specialChar == 's') {
      if (chmodClass == ChmodClass.user) setuid = true;
      if (chmodClass == ChmodClass.group) setgid = true;
    }
    if (specialChar == 't') sticky = true;
  }
  return info.withBits(setuid: setuid, setgid: setgid, sticky: sticky);
}

/// Applies a relative form such as `a+x`, `u-w`, or `go=rwx` to a base mode.
ChmodInfo _applyRelative(String value) {
  final match = RegExp(r'^([ugoa]*)([+=-])([rwxXst]*)$').firstMatch(value);
  if (match == null) {
    throw FormatException('Not a relative mode: $value');
  }
  final who = match.group(1)!;
  final operator = match.group(2)!;
  final what = match.group(3)!;

  final targets = <ChmodClass>[
    for (final chmodClass in ChmodClass.values)
      if (who.contains(chmodClass.letter) || who.contains('a')) chmodClass,
  ];
  if (targets.isEmpty) {
    throw FormatException('No target class in "$value"');
  }

  var info = chmodFromTriplets(0, 0, 0);
  for (final chmodClass in targets) {
    final existing = info._bitsFor(chmodClass);
    final bits = PermissionBits(
      read: _resolve(existing.read, 'r', operator),
      write: _resolve(existing.write, 'w', operator),
      execute: _resolve(existing.execute, 'xX', operator),
    );
    info = info.withClass(chmodClass, bits);
  }
  if (what.contains('s')) {
    if (targets.contains(ChmodClass.user)) {
      info = info.withBits(setuid: operator != '-');
    }
    if (targets.contains(ChmodClass.group)) {
      info = info.withBits(setgid: operator != '-');
    }
  }
  if (what.contains('t')) {
    info = info.withBits(sticky: operator != '-');
  }
  return info;
}

bool _resolve(bool current, String letter, String operator) {
  if (operator == '=') return whatContains(letter);
  if (operator == '+') return true;
  return false;
}

bool whatContains(String letter) => letter == 'r' || letter == 'w' || letter == 'xX';

PermissionBits _bits(int octal) => PermissionBits(
      read: octal & 4 != 0,
      write: octal & 2 != 0,
      execute: octal & 1 != 0,
    );

/// Common starting points offered as quick presets.
const commonModes = <String, String>{
  '755': 'rwxr-xr-x  typical script or directory',
  '644': 'rw-r--r--  typical file',
  '600': 'rw-------  private file',
  '700': 'rwx------  private executable',
  '777': 'rwxrwxrwx  world-writable',
  '775': 'rwxrwxr-x  shared directory',
  '666': 'rw-rw-rw-  world-writable file',
  '400': 'r--------  read-only',
  '1777': 'rwxrwxrwt  sticky world-writable dir',
  '4755': 'rwsr-xr-x  setuid root binary',
  '2755': 'rwxr-sr-x  setgid',
};