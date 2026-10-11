// PlantUML diagram model + parser/generator.
//
// Supports two overlapping styles of PlantUML:
//   * Class diagrams: class / interface / abstract class / enum declarations
//     with visibility-prefixed members.
//   * Architecture/component diagrams: rectangle / component / node / database
//     / etc. elements declared as `keyword "Label" as alias <<stereotype>>`,
//     grouped inside nestable `package { }` (and composite-element) containers.
//
// Both share the same relationship arrows (association, directed association,
// inheritance, realization, composition, aggregation, dependency).
//
// Box positions aren't part of standard PlantUML, so they're round-tripped via
// `'@pos Name x y` comment lines, letting the visual layout survive a text
// edit. Styling the parser doesn't model structurally (skinparam blocks, title,
// hide, ! directives) is preserved verbatim as a preamble so a canvas drag
// doesn't strip a diagram's theme. Stereotype colors declared in a
// `skinparam <element> { ... }` block are additionally captured so the canvas
// can mirror them.

import 'dart:math' as math;

enum UmlTypeKind { classType, interfaceType, abstractType, enumType, node }

extension UmlTypeKindKeyword on UmlTypeKind {
  String get keyword => switch (this) {
    UmlTypeKind.classType => 'class',
    UmlTypeKind.interfaceType => 'interface',
    UmlTypeKind.abstractType => 'abstract class',
    UmlTypeKind.enumType => 'enum',
    UmlTypeKind.node => 'rectangle',
  };

  String get label => switch (this) {
    UmlTypeKind.classType => 'class',
    UmlTypeKind.interfaceType => 'interface',
    UmlTypeKind.abstractType => 'abstract',
    UmlTypeKind.enumType => 'enum',
    UmlTypeKind.node => 'node',
  };
}

enum UmlVisibility { public, private, protected, package, none }

extension UmlVisibilitySymbol on UmlVisibility {
  String get symbol => switch (this) {
    UmlVisibility.public => '+',
    UmlVisibility.private => '-',
    UmlVisibility.protected => '#',
    UmlVisibility.package => '~',
    UmlVisibility.none => '',
  };

  static UmlVisibility fromChar(String char) => switch (char) {
    '+' => UmlVisibility.public,
    '-' => UmlVisibility.private,
    '#' => UmlVisibility.protected,
    '~' => UmlVisibility.package,
    _ => UmlVisibility.none,
  };
}

class UmlMember {
  UmlMember({required this.visibility, required this.text});

  UmlVisibility visibility;
  String text; // signature after the visibility marker, e.g. "name: String"

  bool get isMethod => text.contains('(');

  String toPlantUml() => '${visibility.symbol}$text';

  UmlMember copy() => UmlMember(visibility: visibility, text: text);
}

class UmlType {
  UmlType({
    required this.name,
    this.kind = UmlTypeKind.classType,
    String? label,
    this.stereotype,
    this.nodeKeyword,
    this.groupId,
    this.attachedTo,
    this.attachedSide,
    List<UmlMember>? members,
    this.x = 0,
    this.y = 0,
    this.w,
    this.h,
    this.color,
  }) : label = label ?? name,
       members = members ?? [];

  /// Identifier used to reference this element in relations (the alias).
  String name;
  UmlTypeKind kind;

  /// Human-facing display text. For class types this matches [name]; for
  /// architecture nodes it's the quoted label, distinct from the alias.
  String label;

  /// Stereotype without guillemets, e.g. `business` for `<<business>>`.
  String? stereotype;

  /// Original element keyword for [UmlTypeKind.node] (rectangle, component…),
  /// so it round-trips.
  String? nodeKeyword;

  /// Id of the enclosing [UmlGroup], or null when top-level.
  String? groupId;

  /// For notes only (`nodeKeyword == 'note'`): the alias of the element this
  /// note is anchored to via `note <dir> of <target>`. Null for free notes.
  /// The canvas draws a dashed connector to the target; it round-trips back to
  /// `note <dir> of <target>` syntax.
  String? attachedTo;

  /// For attached notes: which side of the target the note sits on — one of
  /// `top`, `bottom`, `left`, `right`. Drives layout placement and round-trips.
  String? attachedSide;

  List<UmlMember> members;
  double x;
  double y;

  /// Optional user-set box size overrides (from resize handles). Null means
  /// "use the renderer's default size for this kind".
  double? w;
  double? h;

  /// Optional user-set background color (hex, e.g. `#FFE08A`) from the
  /// right-click menu. Null uses the stereotype/theme color.
  String? color;

  bool get isNote => nodeKeyword == 'note';

  List<UmlMember> get fields => members.where((m) => !m.isMethod).toList();
  List<UmlMember> get methods => members.where((m) => m.isMethod).toList();

  UmlType copy() => UmlType(
    name: name,
    kind: kind,
    label: label,
    stereotype: stereotype,
    nodeKeyword: nodeKeyword,
    groupId: groupId,
    attachedTo: attachedTo,
    attachedSide: attachedSide,
    members: members.map((m) => m.copy()).toList(),
    x: x,
    y: y,
    w: w,
    h: h,
    color: color,
  );
}

/// A container element — `package`, or a composite element declared with a
/// trailing `{` (e.g. `rectangle "SaaS platform" as saas { ... }`). Geometry
/// is derived from member positions at layout time, not round-tripped.
class UmlGroup {
  UmlGroup({
    required this.id,
    required this.label,
    this.keyword = 'package',
    this.stereotype,
    this.parentId,
    this.color,
  });

  String id;
  String label;
  String keyword; // 'package' or an element keyword for composite containers
  String? stereotype;
  String? parentId;

  /// Optional user-set background color (hex, e.g. `#FFE08A`) from the
  /// right-click menu. Null uses the stereotype/theme color. Round-trips via a
  /// `'@color <id> <hex>` comment, same as [UmlType.color].
  String? color;

  // Transient layout geometry (recomputed each layout pass).
  double x = 0;
  double y = 0;
  double w = 0;
  double h = 0;

  UmlGroup copy() => UmlGroup(
    id: id,
    label: label,
    keyword: keyword,
    stereotype: stereotype,
    parentId: parentId,
    color: color,
  );
}

/// Captured stereotype styling from a `skinparam <element> { ... }` block.
class UmlStereotypeStyle {
  UmlStereotypeStyle({this.background, this.border, this.font});

  String? background; // raw color token, e.g. '#FAEEDA'
  String? border;
  String? font;

  UmlStereotypeStyle copy() =>
      UmlStereotypeStyle(background: background, border: border, font: font);
}

/// Structured view of a note body so the canvas can render PlantUML "creole"
/// markup (pipe tables, `--` dividers, `**bold**`) instead of raw text — and so
/// the size estimate and the renderer agree on geometry.
enum UmlNoteBlockKind { text, table, divider }

class UmlNoteCell {
  UmlNoteCell(this.text, {this.header = false});
  final String text;
  final bool header; // `|=` cell → bold, shaded
}

class UmlNoteBlock {
  UmlNoteBlock.text(this.text) : kind = UmlNoteBlockKind.text, rows = const [];
  UmlNoteBlock.table(this.rows) : kind = UmlNoteBlockKind.table, text = '';
  UmlNoteBlock.divider()
    : kind = UmlNoteBlockKind.divider,
      text = '',
      rows = const [];

  final UmlNoteBlockKind kind;
  final String text; // text blocks: lines joined by '\n'
  final List<List<UmlNoteCell>> rows; // table blocks
}

enum UmlRelationKind {
  association,
  directedAssociation,
  inheritance,
  realization,
  composition,
  aggregation,
  dependency,
}

extension UmlRelationKindLabel on UmlRelationKind {
  String get label => switch (this) {
    UmlRelationKind.association => 'Association',
    UmlRelationKind.directedAssociation => 'Directed',
    UmlRelationKind.inheritance => 'Inheritance',
    UmlRelationKind.realization => 'Realization',
    UmlRelationKind.composition => 'Composition',
    UmlRelationKind.aggregation => 'Aggregation',
    UmlRelationKind.dependency => 'Dependency',
  };

  // PlantUML arrow with the head pointing from `from` to `to`.
  String get arrow => switch (this) {
    UmlRelationKind.association => '--',
    UmlRelationKind.directedAssociation => '-->',
    UmlRelationKind.inheritance => '--|>',
    UmlRelationKind.realization => '..|>',
    UmlRelationKind.composition => '*--',
    UmlRelationKind.aggregation => 'o--',
    UmlRelationKind.dependency => '..>',
  };
}

class UmlRelation {
  UmlRelation({
    required this.from,
    required this.to,
    this.kind = UmlRelationKind.directedAssociation,
    this.label,
  });

  String from;
  String to;
  UmlRelationKind kind;
  String? label;

  String toPlantUml() {
    final suffix = (label != null && label!.isNotEmpty) ? ' : $label' : '';
    return '$from ${kind.arrow} $to$suffix';
  }

  UmlRelation copy() =>
      UmlRelation(from: from, to: to, kind: kind, label: label);
}

class UmlDiagram {
  UmlDiagram({
    List<UmlType>? types,
    List<UmlRelation>? relations,
    List<UmlGroup>? groups,
    List<String>? styleLines,
    Map<String, UmlStereotypeStyle>? stereotypeStyles,
    this.name,
    this.title,
  }) : types = types ?? [],
       relations = relations ?? [],
       groups = groups ?? [],
       styleLines = styleLines ?? [],
       stereotypeStyles = stereotypeStyles ?? {};

  final List<UmlType> types;
  final List<UmlRelation> relations;
  final List<UmlGroup> groups;

  /// Verbatim preamble lines (skinparam, title, hide, ! directives) preserved
  /// across a parse → generate round-trip.
  final List<String> styleLines;

  /// Stereotype → captured colors from a skinparam element block.
  final Map<String, UmlStereotypeStyle> stereotypeStyles;

  /// Name following `@startuml`, if any.
  String? name;

  /// Text from a `title` directive, if any.
  String? title;

  /// Best display heading for the canvas: the explicit title, else the name.
  String? get heading => title ?? name;

  bool get hasGroups => groups.isNotEmpty;

  UmlType? typeByName(String name) {
    for (final type in types) {
      if (type.name == name) return type;
    }
    return null;
  }

  UmlGroup? groupById(String id) {
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  UmlDiagram copy() => UmlDiagram(
    types: types.map((t) => t.copy()).toList(),
    relations: relations.map((r) => r.copy()).toList(),
    groups: groups.map((g) => g.copy()).toList(),
    styleLines: List.of(styleLines),
    stereotypeStyles: {
      for (final entry in stereotypeStyles.entries)
        entry.key: entry.value.copy(),
    },
    name: name,
    title: title,
  );
}

class PlantUmlService {
  PlantUmlService._();

  static const double _layoutGap = 60;

  // Architecture (group) layout metrics. Node sizes mirror the canvas renderer.
  static const double nodeWidth = 168;
  static const double nodeHeight = 64;
  static const double _groupTitleHeight = 26;
  static const double _groupPad = 16;
  static const double _innerGap = 26;
  static const double _bandGap = 40;

  /// Gap between a host element and an attached note. Shared by the footprint
  /// reservation in [_leafFootprint] and the placement in [_placeAttachedNotes]
  /// so the space a note is given always matches where it lands.
  static const double _noteGap = 22;

  // Class-like box geometry. The canvas renderer mirrors these (via
  // [defaultBoxWidth]/[defaultBoxHeight]) so the space layout reserves is the
  // space a box actually draws into — class/interface/enum boxes size to their
  // member rows rather than the compact uniform node box.
  static const double classBoxWidth = 190;
  static const double _classHeaderH = 34;
  static const double _classRowH = 19;
  static const double _classSectionPad = 12; // 6 top + 6 bottom per section
  static const double _classBordersH = 2; // 1px top + 1px bottom inset

  /// Extra spacing between top-level (ungrouped) boxes so relationship arrows
  /// have a visible run between them. Group interiors stay compact ([_innerGap]).
  static const double _topLevelGap = 70;

  /// The width a box defaults to when the user hasn't resized it: compact for
  /// architecture nodes, wider for class-like boxes that hold member text.
  static double defaultBoxWidth(UmlType type) =>
      type.kind == UmlTypeKind.node ? nodeWidth : classBoxWidth;

  /// The height a box defaults to when the user hasn't resized it. Class-like
  /// boxes grow with their field/method (or enum constant) rows; architecture
  /// nodes are a fixed compact height. Mirrors the canvas renderer.
  static double defaultBoxHeight(UmlType type) {
    if (type.kind == UmlTypeKind.node) return nodeHeight;
    if (type.kind == UmlTypeKind.enumType) {
      final n = type.members.length;
      return _classHeaderH +
          (n == 0 ? 0 : _classSectionPad + n * _classRowH) +
          _classBordersH;
    }
    var body = 0.0;
    if (type.fields.isNotEmpty) {
      body += _classSectionPad + type.fields.length * _classRowH;
    }
    if (type.methods.isNotEmpty) {
      body += _classSectionPad + type.methods.length * _classRowH;
    }
    return _classHeaderH + body + _classBordersH;
  }

  /// Effective box size used by layout: a user-set resize override wins,
  /// otherwise the renderer-matched default for the box's kind/content.
  static double effectiveWidth(UmlType type) => type.w ?? defaultBoxWidth(type);
  static double effectiveHeight(UmlType type) =>
      type.h ?? defaultBoxHeight(type);

  /// Element keywords (besides class-like ones) treated as nodes/containers.
  static const Set<String> _nodeKeywords = {
    'rectangle',
    'component',
    'node',
    'cloud',
    'database',
    'queue',
    'folder',
    'frame',
    'card',
    'actor',
    'usecase',
    'storage',
    'agent',
    'artifact',
    'boundary',
    'control',
    'entity',
    'collections',
    'stack',
    'person',
    'note',
  };

  // Note-body layout metrics, shared by the size estimate here and the canvas
  // renderer so a note's box always fits its rendered content.
  static const double noteCharW = 6.7;
  static const double noteLineH = 16.0;
  static const double noteRowH = 20.0;
  static const double noteCellPadX = 7.0;
  static const double noteDividerH = 11.0;
  static const double notePadL = 11.0;
  static const double notePadR = 18.0; // extra room for the folded corner
  static const double notePadV = 9.0;

  /// Splits a note body (with real newlines) into renderable blocks: pipe
  /// tables (`|= h |` headers, `| c |` cells), `--` dividers, and text runs.
  static List<UmlNoteBlock> parseNoteBody(String body) {
    final blocks = <UmlNoteBlock>[];
    final textRun = <String>[];
    void flushText() {
      if (textRun.isNotEmpty) {
        blocks.add(UmlNoteBlock.text(textRun.join('\n')));
        textRun.clear();
      }
    }

    final lines = body.split('\n');
    var i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      final isTableRow = line.startsWith('|') && line.endsWith('|');
      final isDivider = RegExp(r'^-{2,}$|^={2,}$').hasMatch(line);
      if (isTableRow) {
        flushText();
        final rows = <List<UmlNoteCell>>[];
        while (i < lines.length) {
          final r = lines[i].trim();
          if (!(r.startsWith('|') && r.endsWith('|'))) break;
          rows.add(_parseTableRow(r));
          i++;
        }
        blocks.add(UmlNoteBlock.table(rows));
        continue;
      }
      if (isDivider) {
        flushText();
        blocks.add(UmlNoteBlock.divider());
      } else {
        textRun.add(lines[i]);
      }
      i++;
    }
    flushText();
    return blocks;
  }

  static List<UmlNoteCell> _parseTableRow(String row) {
    // Drop the leading/trailing pipe, then split. A `=`-prefixed cell is a
    // header cell (PlantUML `|= header`).
    final inner = row.substring(1, row.length - 1);
    return inner.split('|').map((raw) {
      var cell = raw.trim();
      final header = cell.startsWith('=');
      if (header) cell = cell.substring(1).trim();
      return UmlNoteCell(_stripCreole(cell), header: header);
    }).toList();
  }

  /// Strips `**bold**` markers for width measurement / plain display.
  static String _stripCreole(String s) => s.replaceAll('**', '');

  /// Estimated rendered size of a note body, matching [parseNoteBody]'s blocks
  /// and the renderer's metrics so the box fits without clipping.
  static (double w, double h) noteContentSize(String body) {
    var maxW = 0.0;
    var h = 0.0;
    for (final block in parseNoteBody(body)) {
      switch (block.kind) {
        case UmlNoteBlockKind.text:
          final lines = block.text.split('\n');
          var widest = 0.0;
          for (final l in lines) {
            final w = _stripCreole(l).length * noteCharW;
            if (w > widest) widest = w;
          }
          if (widest > maxW) maxW = widest;
          h += lines.length * noteLineH;
        case UmlNoteBlockKind.table:
          final cols = <int, double>{};
          for (final r in block.rows) {
            for (var c = 0; c < r.length; c++) {
              final w = r[c].text.length * noteCharW + 2 * noteCellPadX;
              if (w > (cols[c] ?? 0)) cols[c] = w;
            }
          }
          final tableW =
              cols.values.fold(0.0, (a, b) => a + b) + cols.length + 1;
          if (tableW > maxW) maxW = tableW;
          h += block.rows.length * noteRowH + 1;
        case UmlNoteBlockKind.divider:
          h += noteDividerH;
      }
    }
    return (maxW + notePadL + notePadR, h + 2 * notePadV);
  }

  /// Parses PlantUML text into a diagram. [previous] is used to preserve box
  /// positions for types that still exist (matched by name); new types are
  /// auto-laid-out.
  static UmlDiagram parse(String source, {UmlDiagram? previous}) {
    final diagram = UmlDiagram();
    final positions = <String, ({double x, double y})>{};
    final sizes = <String, ({double w, double h})>{};
    final colors = <String, String>{};

    final lines = source.split('\n');
    final groupStack = <UmlGroup>[];
    UmlType? currentClass;
    var inBlockComment = false;
    var skinDepth = 0; // depth inside a skinparam { } block

    // Multi-line note block state (`note as N` / `note <dir> of T` … `end note`).
    List<String>? noteBody;
    String? noteAlias;
    String? noteAttach;
    String? noteSide;
    String? noteGroup;
    var noteCounter = 0;

    String? parentId() => groupStack.isEmpty ? null : groupStack.last.id;

    String uniqueNoteName() {
      String candidate;
      do {
        candidate = 'note${++noteCounter}';
      } while (diagram.typeByName(candidate) != null);
      return candidate;
    }

    // Build a note element from collected body text, estimating a box size from
    // the content so the canvas renderer and group-bounds layout agree (both
    // read w/h). Body is stored with `\n` escapes so it round-trips and the
    // renderer can expand it back to real line breaks.
    void addNote(
      String? alias,
      String? attach,
      String? side,
      String? group,
      String body,
    ) {
      final (w, h) = noteContentSize(body);
      diagram.types.add(
        UmlType(
          name: alias ?? uniqueNoteName(),
          label: body.replaceAll('\n', r'\n'),
          kind: UmlTypeKind.node,
          nodeKeyword: 'note',
          groupId: group,
          attachedTo: attach,
          attachedSide: attach == null ? null : (side ?? 'bottom'),
          w: w.clamp(120.0, 560.0),
          h: h.clamp(40.0, 4000.0),
        ),
      );
    }

    for (final raw in lines) {
      final line = raw.trim();

      // Collecting a multi-line note body: everything up to `end note` is
      // verbatim content (blank lines included).
      if (noteBody != null) {
        if (RegExp(r'^end\s*note$', caseSensitive: false).hasMatch(line)) {
          addNote(
            noteAlias,
            noteAttach,
            noteSide,
            noteGroup,
            noteBody.join('\n').trim(),
          );
          noteBody = null;
          noteAlias = null;
          noteAttach = null;
          noteSide = null;
          noteGroup = null;
        } else {
          noteBody.add(line);
        }
        continue;
      }

      if (line.isEmpty) continue;

      // Position round-trip comment.
      final posMatch = RegExp(
        r"^'@pos\s+(\S+)\s+(-?[\d.]+)\s+(-?[\d.]+)",
      ).firstMatch(line);
      if (posMatch != null) {
        positions[posMatch.group(1)!] = (
          x: double.tryParse(posMatch.group(2)!) ?? 0,
          y: double.tryParse(posMatch.group(3)!) ?? 0,
        );
        continue;
      }

      // Box size round-trip comment (from resize handles).
      final sizeMatch = RegExp(
        r"^'@size\s+(\S+)\s+([\d.]+)\s+([\d.]+)",
      ).firstMatch(line);
      if (sizeMatch != null) {
        sizes[sizeMatch.group(1)!] = (
          w: double.tryParse(sizeMatch.group(2)!) ?? 0,
          h: double.tryParse(sizeMatch.group(3)!) ?? 0,
        );
        continue;
      }

      // Per-box background color round-trip comment.
      final colorMatch = RegExp(
        r"^'@color\s+(\S+)\s+(#[0-9A-Fa-f]{3,8})",
      ).firstMatch(line);
      if (colorMatch != null) {
        colors[colorMatch.group(1)!] = colorMatch.group(2)!;
        continue;
      }

      // Inside a skinparam { } block: preserve verbatim, harvest colors.
      if (skinDepth > 0) {
        diagram.styleLines.add(line);
        _captureStereotypeColor(diagram, line);
        skinDepth += _braceDelta(line);
        continue;
      }

      if (inBlockComment) {
        if (line.contains("'/")) inBlockComment = false;
        continue;
      }
      if (line.startsWith("/'")) {
        if (!line.contains("'/")) inBlockComment = true;
        continue;
      }
      if (line.startsWith("'")) continue; // single-line comment

      final startMatch = RegExp(r'^@startuml(?:\s+(\S+))?').firstMatch(line);
      if (startMatch != null) {
        diagram.name = startMatch.group(1);
        continue;
      }
      if (line.startsWith('@end')) continue;

      // Styling / directives: preserved verbatim for round-trip.
      if (_isStyleLine(line)) {
        diagram.styleLines.add(line);
        if (line.startsWith('skinparam') && line.endsWith('{')) {
          skinDepth = 1;
        } else if (line.toLowerCase().startsWith('title ')) {
          diagram.title = line.substring(6).trim();
        }
        continue;
      }

      // Inside a class member body.
      if (currentClass != null) {
        if (line.startsWith('}')) {
          currentClass = null;
          continue;
        }
        final member = _parseMember(line);
        if (member != null) currentClass.members.add(member);
        continue;
      }

      // Closing brace for a container (package / composite element).
      if (line == '}' || line.startsWith('}')) {
        if (groupStack.isNotEmpty) groupStack.removeLast();
        continue;
      }

      // Notes. Inline forms are self-contained; block forms open a body that is
      // collected until `end note`.
      final noteInline = RegExp(
        r'^note\s+(?:(top|bottom|left|right)\s+of\s+(\w+)|as\s+(\w+))\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (noteInline != null) {
        addNote(
          noteInline.group(3),
          noteInline.group(2),
          noteInline.group(1), // side (top|bottom|left|right)
          parentId(),
          noteInline.group(4)!.trim(),
        );
        continue;
      }
      final noteOpen = RegExp(
        r'^note\s+(?:(top|bottom|left|right)\s+of\s+(\w+)|as\s+(\w+))\s*$',
        caseSensitive: false,
      ).firstMatch(line);
      if (noteOpen != null) {
        noteBody = <String>[];
        noteAlias = noteOpen.group(3);
        noteAttach = noteOpen.group(2);
        noteSide = noteOpen.group(1)?.toLowerCase();
        noteGroup = parentId();
        continue;
      }

      // Class-like declaration.
      final classMatch = RegExp(
        r'^(abstract\s+class|abstract|class|interface|enum)\s+("[^"]+"|[\w.]+)(?:\s+as\s+(\w+))?\s*(?:<<([^>]*)>>)?\s*(\{)?\s*$',
        caseSensitive: false,
      ).firstMatch(line);
      if (classMatch != null) {
        final keyword = classMatch.group(1)!.toLowerCase();
        final display = _unquote(classMatch.group(2)!);
        final alias = classMatch.group(3);
        final kind = switch (keyword) {
          'interface' => UmlTypeKind.interfaceType,
          'enum' => UmlTypeKind.enumType,
          'abstract' || 'abstract class' => UmlTypeKind.abstractType,
          _ => UmlTypeKind.classType,
        };
        final type = UmlType(
          name: alias ?? display,
          label: display,
          kind: kind,
          stereotype: _blankToNull(classMatch.group(4)),
          groupId: parentId(),
        );
        diagram.types.add(type);
        if (classMatch.group(5) == '{') currentClass = type;
        continue;
      }

      // Node / container declaration: keyword ["Label"|name] [as alias]
      // [<<stereo>>] [{].
      final nodeMatch = RegExp(
        r'^(\w+)\s+(?:"([^"]*)"|([\w.]+))(?:\s+as\s+([\w.]+))?\s*(?:<<([^>]*)>>)?\s*(\{)?\s*$',
      ).firstMatch(line);
      if (nodeMatch != null &&
          (nodeMatch.group(1)!.toLowerCase() == 'package' ||
              _nodeKeywords.contains(nodeMatch.group(1)!.toLowerCase()))) {
        final keyword = nodeMatch.group(1)!.toLowerCase();
        final quoted = nodeMatch.group(2);
        final bare = nodeMatch.group(3);
        final alias = nodeMatch.group(4);
        final stereotype = _blankToNull(nodeMatch.group(5));
        final opensContainer = nodeMatch.group(6) == '{';
        final display = quoted ?? bare ?? '';
        final id = alias ?? bare ?? display;

        if (opensContainer) {
          final group = UmlGroup(
            id: id,
            label: display,
            keyword: keyword,
            stereotype: stereotype,
            parentId: parentId(),
          );
          diagram.groups.add(group);
          groupStack.add(group);
        } else {
          diagram.types.add(
            UmlType(
              name: id,
              label: display,
              kind: UmlTypeKind.node,
              nodeKeyword: keyword == 'package' ? 'rectangle' : keyword,
              stereotype: stereotype,
              groupId: parentId(),
            ),
          );
        }
        continue;
      }

      // Relationship.
      final relation = _parseRelation(line);
      if (relation != null) {
        diagram.relations.add(relation);
        // A bare relation referencing an undeclared element creates a stub so
        // it still renders.
        for (final name in [relation.from, relation.to]) {
          if (diagram.typeByName(name) == null &&
              diagram.groupById(name) == null) {
            diagram.types.add(UmlType(name: name, groupId: parentId()));
          }
        }
      }
    }

    // Apply round-tripped / carried-over size overrides before layout so group
    // bounds account for resized boxes.
    for (final type in diagram.types) {
      final size =
          sizes[type.name] ??
          () {
            final prev = previous?.typeByName(type.name);
            return prev?.w != null && prev?.h != null
                ? (w: prev!.w!, h: prev.h!)
                : null;
          }();
      if (size != null) {
        type.w = size.w;
        type.h = size.h;
      }
      type.color = colors[type.name] ?? previous?.typeByName(type.name)?.color;
    }
    for (final group in diagram.groups) {
      group.color = colors[group.id] ?? previous?.groupById(group.id)?.color;
    }

    _applyLayout(diagram, positions, previous);
    return diagram;
  }

  static bool _isStyleLine(String line) {
    final lower = line.toLowerCase();
    return lower.startsWith('skinparam') ||
        lower.startsWith('!') ||
        lower.startsWith('hide') ||
        lower.startsWith('show') ||
        lower.startsWith('title') ||
        lower.startsWith('header') ||
        lower.startsWith('footer') ||
        lower.startsWith('scale') ||
        lower.startsWith('left to right direction') ||
        lower.startsWith('top to bottom direction');
  }

  static int _braceDelta(String line) {
    var delta = 0;
    for (final unit in line.codeUnits) {
      if (unit == 0x7B) delta++; // {
      if (unit == 0x7D) delta--; // }
    }
    return delta;
  }

  static void _captureStereotypeColor(UmlDiagram diagram, String line) {
    final match = RegExp(
      r'(BackgroundColor|BorderColor|FontColor)\s*<<\s*(\w+)\s*>>\s*(#[0-9A-Fa-f]{3,8}|\w+)',
    ).firstMatch(line);
    if (match == null) return;
    final kind = match.group(1)!;
    final stereotype = match.group(2)!;
    final color = match.group(3)!;
    final style = diagram.stereotypeStyles.putIfAbsent(
      stereotype,
      UmlStereotypeStyle.new,
    );
    switch (kind) {
      case 'BackgroundColor':
        style.background = color;
      case 'BorderColor':
        style.border = color;
      case 'FontColor':
        style.font = color;
    }
  }

  static UmlMember? _parseMember(String line) {
    var text = line;
    var visibility = UmlVisibility.none;
    if (text.isNotEmpty && '+-#~'.contains(text[0])) {
      visibility = UmlVisibilitySymbol.fromChar(text[0]);
      text = text.substring(1).trim();
    }
    if (text.isEmpty) return null;
    if (text == '}' || text == '{') return null;
    return UmlMember(visibility: visibility, text: text);
  }

  static UmlRelation? _parseRelation(String line) {
    // Strip an optional ": label" first.
    String? label;
    var body = line;
    final colon = body.indexOf(' : ');
    if (colon != -1) {
      label = body.substring(colon + 3).trim();
      body = body.substring(0, colon).trim();
    }
    // Drop multiplicity quotes adjacent to the arrow: A "1" --> "*" B.
    final multiplicity = RegExp(r'\s"[^"]*"\s');
    body = body.replaceAll(multiplicity, ' ');

    final match = RegExp(
      r'^("[^"]+"|[\w.]+)\s+([-.<>|*o]{2,})\s+("[^"]+"|[\w.]+)$',
    ).firstMatch(body.trim());
    if (match == null) return null;

    var left = _unquote(match.group(1)!);
    final arrow = match.group(2)!;
    var right = _unquote(match.group(3)!);

    final headOnLeft = arrow.startsWith('<') || arrow.startsWith('<|');
    final dotted = arrow.contains('.');
    final hasOpenArrow = arrow.contains('>') || arrow.contains('<');
    final hasTriangle = arrow.contains('|');
    final hasDiamondFilled = arrow.contains('*');
    final hasDiamondHollow = arrow.contains('o');

    UmlRelationKind kind;
    if (hasTriangle) {
      kind = dotted ? UmlRelationKind.realization : UmlRelationKind.inheritance;
    } else if (hasDiamondFilled) {
      kind = UmlRelationKind.composition;
    } else if (hasDiamondHollow) {
      kind = UmlRelationKind.aggregation;
    } else if (dotted) {
      kind = UmlRelationKind.dependency;
    } else if (hasOpenArrow) {
      kind = UmlRelationKind.directedAssociation;
    } else {
      kind = UmlRelationKind.association;
    }

    // Normalize so the arrowhead points from `from` to `to`.
    if (headOnLeft) {
      final tmp = left;
      left = right;
      right = tmp;
    }
    return UmlRelation(from: left, to: right, kind: kind, label: label);
  }

  // ---- Layout ----------------------------------------------------------

  static void _applyLayout(
    UmlDiagram diagram,
    Map<String, ({double x, double y})> positions,
    UmlDiagram? previous,
  ) {
    // Reuse explicit (@pos) or carried-over positions where available.
    var allPlaced = true;
    final placed = <String>{};
    for (final type in diagram.types) {
      final fromComment = positions[type.name];
      final fromPrevious = previous?.typeByName(type.name);
      if (fromComment != null) {
        type.x = fromComment.x;
        type.y = fromComment.y;
        placed.add(type.name);
      } else if (fromPrevious != null) {
        type.x = fromPrevious.x;
        type.y = fromPrevious.y;
        placed.add(type.name);
      } else {
        allPlaced = false;
      }
    }

    if (!allPlaced) {
      if (diagram.hasGroups) {
        _autoLayoutGrouped(diagram);
      } else {
        _autoLayoutGrid(diagram);
      }
    }
    // Anchor `note <side> of X` notes beside their target (unless the user has
    // dragged the note, i.e. it carries a saved position).
    _placeAttachedNotes(diagram, placed);
    if (diagram.hasGroups) {
      // Derive/refresh group boxes from final node + note positions.
      _computeGroupBounds(diagram);
    }
  }

  /// Full, position-discarding layout used by the canvas "Tidy" action: every
  /// element is re-placed from scratch (grouped band flow for architecture
  /// diagrams, a grid otherwise), attached notes are reseated beside their
  /// hosts, and group boxes are recomputed to wrap their contents.
  static void autoLayout(UmlDiagram diagram) {
    if (diagram.hasGroups) {
      _autoLayoutGrouped(diagram);
    } else {
      _autoLayoutGrid(diagram);
    }
    _placeAttachedNotes(diagram, const <String>{});
    if (diagram.hasGroups) _computeGroupBounds(diagram);
  }

  /// Geometry for one leaf element together with its attached notes: the outer
  /// footprint to reserve, where the host sits inside it, and each note's
  /// offset from the host's top-left. One source of truth so grid reservation
  /// ([_layoutLeafGrid]) and note placement ([_placeAttachedNotes]) never drift.
  static _LeafFootprint _leafFootprint(UmlDiagram diagram, UmlType host) {
    final hw = effectiveWidth(host);
    final hh = effectiveHeight(host);
    final offsets = <String, (double, double)>{};
    // Host occupies (0,0)..(hw,hh); notes extend the bounding box outward.
    var minX = 0.0, minY = 0.0, maxX = hw, maxY = hh;

    List<UmlType> onSide(String side) => diagram.types
        .where(
          (n) =>
              n.isNote &&
              n.attachedTo == host.name &&
              (n.attachedSide ?? 'bottom') == side,
        )
        .toList();

    // Vertical sides: notes stack away from the host, centered on its x-axis.
    var below = _noteGap;
    for (final n in onSide('bottom')) {
      final nw = effectiveWidth(n), nh = effectiveHeight(n);
      final dx = (hw - nw) / 2, dy = hh + below;
      offsets[n.name] = (dx, dy);
      below += nh + _noteGap;
      minX = _min(minX, dx);
      maxX = _max(maxX, dx + nw);
      maxY = _max(maxY, dy + nh);
    }
    var above = _noteGap;
    for (final n in onSide('top')) {
      final nw = effectiveWidth(n), nh = effectiveHeight(n);
      final dx = (hw - nw) / 2, dy = -above - nh;
      offsets[n.name] = (dx, dy);
      above += nh + _noteGap;
      minX = _min(minX, dx);
      maxX = _max(maxX, dx + nw);
      minY = _min(minY, dy);
    }

    // Horizontal sides: notes form a vertical block centered on the host.
    void layoutHorizontal(List<UmlType> notes, bool left) {
      if (notes.isEmpty) return;
      final blockH =
          notes.fold(0.0, (a, n) => a + effectiveHeight(n)) +
          (notes.length - 1) * _noteGap;
      var cy = (hh - blockH) / 2;
      for (final n in notes) {
        final nw = effectiveWidth(n), nh = effectiveHeight(n);
        final dx = left ? -_noteGap - nw : hw + _noteGap;
        offsets[n.name] = (dx, cy);
        cy += nh + _noteGap;
        minX = _min(minX, dx);
        maxX = _max(maxX, dx + nw);
        minY = _min(minY, cy - nh - _noteGap);
        maxY = _max(maxY, cy - _noteGap);
      }
    }

    layoutHorizontal(onSide('left'), true);
    layoutHorizontal(onSide('right'), false);

    return _LeafFootprint(
      width: maxX - minX,
      height: maxY - minY,
      hostDx: -minX,
      hostDy: -minY,
      noteOffsets: offsets,
    );
  }

  /// Positions each `note <side> of <target>` note adjacent to its target,
  /// reusing the exact offsets [_leafFootprint] reserved space for so notes
  /// land inside their host's footprint instead of colliding with neighbors.
  /// Notes the user has dragged (a carried/explicit position in [placed]) are
  /// left alone.
  static void _placeAttachedNotes(UmlDiagram diagram, Set<String> placed) {
    for (final host in diagram.types) {
      if (host.isNote) continue;
      final fp = _leafFootprint(diagram, host);
      if (fp.noteOffsets.isEmpty) continue;
      fp.noteOffsets.forEach((noteName, off) {
        if (placed.contains(noteName)) return;
        final note = diagram.typeByName(noteName);
        if (note == null) return;
        note.x = host.x + off.$1;
        note.y = host.y + off.$2;
      });
    }
  }

  static void _autoLayoutGrid(UmlDiagram diagram) {
    final leaves = diagram.types.where((t) => t.attachedTo == null).toList();
    // Top-level boxes get a wider gap so relationship arrows are visible.
    _layoutLeafGrid(diagram, leaves, _layoutGap, _layoutGap, gap: _topLevelGap);
  }

  static void _autoLayoutGrouped(UmlDiagram diagram) {
    final roots = diagram.groups.where((g) => g.parentId == null).toList();

    // Measure each root by laying it out at the origin; its descendants are
    // positioned absolutely, so we translate the whole subtree into place next.
    final sizes = <String, (double, double)>{};
    for (final group in roots) {
      sizes[group.id] = _placeGroup(diagram, group.id, 0, 0);
    }

    // Shelf-pack the root bands into a balanced grid rather than one tall
    // column, so note-heavy packages don't force an unwieldy aspect ratio.
    final targetWidth = _targetRowWidth([for (final g in roots) sizes[g.id]!]);
    var x = _layoutGap;
    var y = _layoutGap;
    var rowMaxH = 0.0;
    for (final group in roots) {
      final (gw, gh) = sizes[group.id]!;
      if (x > _layoutGap && (x - _layoutGap) + gw > targetWidth) {
        x = _layoutGap;
        y += rowMaxH + _bandGap;
        rowMaxH = 0;
      }
      _translateGroup(diagram, group.id, x, y); // group sits at (0,0) → (x,y)
      x += gw + _bandGap;
      rowMaxH = _max(rowMaxH, gh);
    }

    // Ungrouped leaf nodes laid out in a grid below every band (attached notes
    // are placed beside their target afterwards, so skip them here).
    var bottom = _layoutGap;
    for (final group in roots) {
      bottom = _max(bottom, group.y + group.h);
    }
    final loose = diagram.types
        .where((t) => t.groupId == null && t.attachedTo == null)
        .toList();
    if (loose.isNotEmpty) {
      _layoutLeafGrid(
        diagram,
        loose,
        _layoutGap,
        bottom + _bandGap,
        gap: _topLevelGap,
      );
    }
  }

  /// A landscape-leaning row width target: never narrower than the widest
  /// group, otherwise ~√(total area) scaled toward a wider-than-tall canvas.
  static double _targetRowWidth(List<(double, double)> sizes) {
    if (sizes.isEmpty) return 0;
    var area = 0.0;
    var widest = 0.0;
    for (final (w, h) in sizes) {
      area += w * h;
      widest = _max(widest, w);
    }
    return _max(widest, math.sqrt(area) * 1.4);
  }

  /// Moves group [groupId] and every descendant (sub-groups and member types)
  /// by (dx, dy). Used to relocate a measured-at-origin band into its slot.
  static void _translateGroup(
    UmlDiagram diagram,
    String groupId,
    double dx,
    double dy,
  ) {
    final group = diagram.groupById(groupId)!;
    group.x += dx;
    group.y += dy;
    for (final t in diagram.types.where((t) => t.groupId == groupId)) {
      t.x += dx;
      t.y += dy;
    }
    for (final sub in diagram.groups.where((g) => g.parentId == groupId)) {
      _translateGroup(diagram, sub.id, dx, dy);
    }
  }

  /// Places group [groupId]'s box with its top-left at (bx, by), recursively
  /// positioning descendants. Returns the group's outer (width, height) so the
  /// caller's flow advances past the whole box — title and padding included.
  static (double, double) _placeGroup(
    UmlDiagram diagram,
    String groupId,
    double bx,
    double by,
  ) {
    final contentX = bx + _groupPad;
    final contentTop = by + _groupTitleHeight;
    var y = contentTop;
    var maxRight = contentX;

    final subGroups = diagram.groups.where((g) => g.parentId == groupId);
    var placedSub = false;
    for (final sub in subGroups) {
      placedSub = true;
      final size = _placeGroup(diagram, sub.id, contentX, y);
      maxRight = _max(maxRight, contentX + size.$1);
      y += size.$2 + _innerGap;
    }

    final leaves = diagram.types
        .where((t) => t.groupId == groupId && t.attachedTo == null)
        .toList();
    if (leaves.isNotEmpty) {
      final size = _layoutLeafGrid(diagram, leaves, contentX, y);
      maxRight = _max(maxRight, contentX + size.$1);
      y += size.$2;
    } else if (!placedSub) {
      // Empty container: reserve a minimal body.
      maxRight = _max(maxRight, contentX + nodeWidth);
      y += nodeHeight;
    } else {
      y -= _innerGap; // trim trailing gap after last subgroup
    }

    final group = diagram.groupById(groupId)!;
    group.x = bx;
    group.y = by;
    group.w = (maxRight - bx) + _groupPad;
    group.h = (y - by) + _groupPad;
    return (group.w, group.h);
  }

  /// Lays [leaves] out on a grid whose columns/rows are sized to the widest /
  /// tallest *footprint* — host box plus its attached notes — so neither the
  /// hosts nor their notes overlap their neighbors. Returns the grid's total
  /// (width, height). Hosts are offset inside their cell to leave room for
  /// notes that hang above/left of the box; the notes themselves are seated by
  /// [_placeAttachedNotes] using the same offsets.
  static (double, double) _layoutLeafGrid(
    UmlDiagram diagram,
    List<UmlType> leaves,
    double ox,
    double oy, {
    double gap = _innerGap,
  }) {
    if (leaves.isEmpty) return (0, 0);
    final footprints = [for (final l in leaves) _leafFootprint(diagram, l)];
    final cols = _sqrtCeil(leaves.length);
    final rows = (leaves.length / cols).ceil();

    final colWidth = List.filled(cols, 0.0);
    final rowHeight = List.filled(rows, 0.0);
    for (var i = 0; i < leaves.length; i++) {
      final c = i % cols, r = i ~/ cols;
      colWidth[c] = _max(colWidth[c], footprints[i].width);
      rowHeight[r] = _max(rowHeight[r], footprints[i].height);
    }
    final colX = List.filled(cols, 0.0);
    for (var c = 1; c < cols; c++) {
      colX[c] = colX[c - 1] + colWidth[c - 1] + gap;
    }
    final rowY = List.filled(rows, 0.0);
    for (var r = 1; r < rows; r++) {
      rowY[r] = rowY[r - 1] + rowHeight[r - 1] + gap;
    }

    for (var i = 0; i < leaves.length; i++) {
      final c = i % cols, r = i ~/ cols;
      leaves[i].x = ox + colX[c] + footprints[i].hostDx;
      leaves[i].y = oy + rowY[r] + footprints[i].hostDy;
    }

    final width = colX[cols - 1] + colWidth[cols - 1];
    final height = rowY[rows - 1] + rowHeight[rows - 1];
    return (width, height);
  }

  /// Recomputes every group's bounding box from its current node positions.
  /// Call after a node moves so containers track their contents.
  static void relayoutGroups(UmlDiagram diagram) =>
      _computeGroupBounds(diagram);

  /// Recomputes every group's bounding box from its (already-positioned)
  /// descendants — works whether positions came from layout or @pos.
  static void _computeGroupBounds(UmlDiagram diagram) {
    // Deepest groups first so parents enclose resized children.
    final ordered = List<UmlGroup>.of(diagram.groups)
      ..sort((a, b) => _depth(diagram, b).compareTo(_depth(diagram, a)));
    for (final group in ordered) {
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = -double.infinity;
      var maxY = -double.infinity;

      for (final t in diagram.types.where((t) => t.groupId == group.id)) {
        minX = _min(minX, t.x);
        minY = _min(minY, t.y);
        maxX = _max(maxX, t.x + effectiveWidth(t));
        maxY = _max(maxY, t.y + effectiveHeight(t));
      }
      for (final sub in diagram.groups.where((g) => g.parentId == group.id)) {
        minX = _min(minX, sub.x);
        minY = _min(minY, sub.y);
        maxX = _max(maxX, sub.x + sub.w);
        maxY = _max(maxY, sub.y + sub.h);
      }

      if (minX == double.infinity) {
        // Empty group: keep a small placeholder box at its current origin.
        group.w = nodeWidth + 2 * _groupPad;
        group.h = _groupTitleHeight + nodeHeight + _groupPad;
        continue;
      }
      group.x = minX - _groupPad;
      group.y = minY - _groupTitleHeight;
      group.w = (maxX - minX) + 2 * _groupPad;
      group.h = (maxY - minY) + _groupTitleHeight + _groupPad;
    }
  }

  static int _depth(UmlDiagram diagram, UmlGroup group) {
    var depth = 0;
    var current = group.parentId;
    while (current != null) {
      depth++;
      current = diagram.groupById(current)?.parentId;
    }
    return depth;
  }

  static double _max(double a, double b) => a > b ? a : b;
  static double _min(double a, double b) => a < b ? a : b;
  static int _sqrtCeil(int n) {
    var i = 1;
    while (i * i < n) {
      i++;
    }
    return i;
  }

  static String _unquote(String value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  static String? _blankToNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ---- Generation ------------------------------------------------------

  /// Generates PlantUML text from the diagram, embedding box positions as
  /// `'@pos` comments so layout round-trips. Preserved [styleLines] and group
  /// nesting are re-emitted so a diagram's theme survives an edit.
  static String generate(UmlDiagram diagram, {bool includePositions = true}) {
    final buffer = StringBuffer('@startuml');
    if (diagram.name != null && diagram.name!.isNotEmpty) {
      buffer.write(' ${diagram.name}');
    }
    buffer.writeln();

    for (final line in diagram.styleLines) {
      buffer.writeln(line);
    }
    if (diagram.styleLines.isNotEmpty) buffer.writeln();

    // Top-level groups (recursively) then ungrouped types.
    for (final group in diagram.groups.where((g) => g.parentId == null)) {
      _writeGroup(buffer, diagram, group, 0);
    }
    for (final type in diagram.types.where((t) => t.groupId == null)) {
      _writeType(buffer, type, 0);
    }

    if (diagram.relations.isNotEmpty &&
        (diagram.types.isNotEmpty || diagram.groups.isNotEmpty)) {
      buffer.writeln();
    }
    for (final relation in diagram.relations) {
      buffer.writeln(relation.toPlantUml());
    }

    if (includePositions &&
        (diagram.types.isNotEmpty || diagram.groups.isNotEmpty)) {
      buffer.writeln();
      for (final type in diagram.types) {
        buffer.writeln(
          "'@pos ${type.name} ${type.x.toStringAsFixed(0)} ${type.y.toStringAsFixed(0)}",
        );
        if (type.w != null && type.h != null) {
          buffer.writeln(
            "'@size ${type.name} ${type.w!.toStringAsFixed(0)} ${type.h!.toStringAsFixed(0)}",
          );
        }
        if (type.color != null) {
          buffer.writeln("'@color ${type.name} ${type.color}");
        }
      }
      // Group geometry is derived, but a user-set background color round-trips.
      for (final group in diagram.groups) {
        if (group.color != null) {
          buffer.writeln("'@color ${group.id} ${group.color}");
        }
      }
    }
    buffer.write('@enduml');
    return buffer.toString();
  }

  static void _writeGroup(
    StringBuffer buffer,
    UmlDiagram diagram,
    UmlGroup group,
    int indent,
  ) {
    final pad = '  ' * indent;
    final stereotype = group.stereotype != null
        ? ' <<${group.stereotype}>>'
        : '';
    final aliasPart = group.keyword == 'package' && group.id == group.label
        ? ''
        : ' as ${group.id}';
    buffer.writeln(
      '$pad${group.keyword} "${group.label}"$aliasPart$stereotype {',
    );
    for (final sub in diagram.groups.where((g) => g.parentId == group.id)) {
      _writeGroup(buffer, diagram, sub, indent + 1);
    }
    for (final type in diagram.types.where((t) => t.groupId == group.id)) {
      _writeType(buffer, type, indent + 1);
    }
    buffer.writeln('$pad}');
  }

  static void _writeType(StringBuffer buffer, UmlType type, int indent) {
    final pad = '  ' * indent;
    // Notes round-trip as multi-line blocks: `note <anchor>` … `end note`. The
    // block form avoids quote-escaping issues and preserves line breaks.
    if (type.isNote) {
      final anchor = type.attachedTo != null
          ? '${type.attachedSide ?? 'bottom'} of ${type.attachedTo}'
          : 'as ${type.name}';
      buffer.writeln('${pad}note $anchor');
      for (final bodyLine in type.label.replaceAll(r'\n', '\n').split('\n')) {
        buffer.writeln('$pad  $bodyLine');
      }
      buffer.writeln('${pad}end note');
      return;
    }
    if (type.kind == UmlTypeKind.node) {
      final keyword = type.nodeKeyword ?? 'rectangle';
      final stereotype = type.stereotype != null
          ? ' <<${type.stereotype}>>'
          : '';
      final aliasPart = type.name == type.label ? '' : ' as ${type.name}';
      buffer.writeln('$pad$keyword "${type.label}"$aliasPart$stereotype');
      return;
    }

    final nameToken = _needsQuotes(type.label) ? '"${type.label}"' : type.label;
    final aliasPart = type.name == type.label ? '' : ' as ${type.name}';
    final stereotype = type.stereotype != null ? ' <<${type.stereotype}>>' : '';
    buffer.write('$pad${type.kind.keyword} $nameToken$aliasPart$stereotype');
    if (type.members.isEmpty) {
      buffer.writeln(' {');
      buffer.writeln('$pad}');
    } else {
      buffer.writeln(' {');
      for (final member in type.members) {
        buffer.writeln('$pad  ${member.toPlantUml()}');
      }
      buffer.writeln('$pad}');
    }
  }

  static bool _needsQuotes(String name) =>
      name.contains(' ') || !RegExp(r'^[\w.]+$').hasMatch(name);
}

/// Layout geometry for a host element and its attached notes, produced by
/// [PlantUmlService._leafFootprint]. [width]/[height] is the outer box to
/// reserve in a grid; [hostDx]/[hostDy] is where the host sits inside it (non-
/// zero when notes hang above or to the left); [noteOffsets] maps each note's
/// name to its top-left offset from the host's top-left.
class _LeafFootprint {
  _LeafFootprint({
    required this.width,
    required this.height,
    required this.hostDx,
    required this.hostDy,
    required this.noteOffsets,
  });

  final double width;
  final double height;
  final double hostDx;
  final double hostDy;
  final Map<String, (double, double)> noteOffsets;
}
