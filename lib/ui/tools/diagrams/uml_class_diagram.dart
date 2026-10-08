/// PlantUML class diagram tool view.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/re_highlight.dart';
import '../../../services/diagram_export_service.dart';
import '../../../services/file_dialog_service.dart';
import '../../../services/plantuml_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

// Box geometry is owned by PlantUmlService so the layout engine reserves the
// exact space the canvas draws into. These keep the renderer's call sites.
const double _umlBoxWidth = PlantUmlService.classBoxWidth;

double _umlBoxHeight(UmlType type) => PlantUmlService.defaultBoxHeight(type);

// A lightweight PlantUML grammar for the source editor: element/diagram
// keywords, single-line (`'…`) and block (`/'…'/`) comments, quoted labels,
// `<<stereotype>>` markers, and `#hex` colors. Deliberately shallow — enough to
// make structure scannable without a full PlantUML parser.
final Mode _plantUmlHighlightMode = Mode(
  refs: {},
  caseInsensitive: true,
  keywords: {
    'keyword':
        '@startuml @enduml @startmindmap @endmindmap class interface abstract '
        'enum entity object package namespace node rectangle component cloud '
        'database queue folder frame card actor usecase storage agent artifact '
        'boundary control collections stack person circle note as of extends '
        'implements participant activate deactivate skinparam title header '
        'footer legend endlegend hide show scale together split left right top '
        'bottom direction',
  },
  contains: [
    Mode(className: 'comment', begin: r"/'", end: r"'/"),
    Mode(className: 'comment', begin: r"'", end: r'$'),
    Mode(className: 'string', begin: '"', end: '"'),
    Mode(className: 'meta', begin: '<<', end: '>>'),
    Mode(className: 'number', begin: r'#[0-9A-Fa-f]{3,8}'),
  ],
);

/// Syntax-highlight theme for the PlantUML source editor, themed to the app's
/// palette so it reads on both light and dark editor backgrounds.
CodeHighlightTheme plantUmlCodeTheme(AppColors c) {
  TextStyle style(Color color, {bool bold = false, bool italic = false}) =>
      TextStyle(
        color: color,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      );
  return CodeHighlightTheme(
    languages: {
      'plantuml': CodeHighlightThemeMode(mode: _plantUmlHighlightMode),
    },
    theme: {
      'root': style(c.editorText),
      'keyword': style(c.accent, bold: true),
      'comment': style(c.mutedText, italic: true),
      'string': style(c.success),
      'meta': style(c.warning),
      'number': style(c.warning),
    },
  );
}

/// Margin reserved around a selected box so its resize handles sit inside the
/// hit-testable area (handles are centred on the border and would otherwise
/// spill outside the box's bounds and become unclickable).
const double _umlHandleInset = 11;

/// Rendered size of a type box, kept in lockstep with what the box actually
/// paints so resize handles and relation anchors line up.
///
/// Width: a user-set [UmlType.w] override wins for every kind. Height: nodes
/// and notes honor [UmlType.h]; class-like boxes are always content-height —
/// their body renders to its member rows regardless of any stored height, so
/// honoring [UmlType.h] would make the box, its handles and its arrow anchors
/// disagree (arrows would point off the box). Class boxes are width-resizable.
Size _umlBoxSize(UmlType type) {
  final isNode = type.kind == UmlTypeKind.node;
  final defaultW = isNode ? PlantUmlService.nodeWidth : _umlBoxWidth;
  final defaultH = isNode ? PlantUmlService.nodeHeight : _umlBoxHeight(type);
  return Size(type.w ?? defaultW, isNode ? (type.h ?? defaultH) : defaultH);
}

// Canvas background presets selectable from the toolbar.
const List<String> _umlCanvasStyles = ['App', 'Paper', 'Dark', 'Sketch'];

Color _umlCanvasBackground(String style, AppColors appColors) =>
    switch (style) {
      'Paper' => const Color(0xFFF6F5EF),
      'Dark' => const Color(0xFF12151A),
      'Sketch' => const Color(0xFF1E2024),
      _ => appColors.canvas,
    };

// Node color skins selectable from the toolbar. `Auto`/`ArchiMate`/`Monochrome`
// are semantic; the rest are qualitative palettes cycled across the diagram.
const List<String> _umlNodeSkins = [
  'Auto',
  'ArchiMate',
  'Pastel',
  'Mode 10',
  'Mode 20',
  'Gemstone',
  'Meadow',
  'Monochrome',
];

/// Qualitative palettes (categorical color sets) cycled per node. Same palette
/// drives the toolbar selector and the boxes, so the swatch matches the canvas.
const Map<String, List<int>> _umlPalettes = {
  'Pastel': [
    0xFFCDE7F0,
    0xFFF3D9E3,
    0xFFD9EFD6,
    0xFFF6E7C9,
    0xFFE2DCF2,
    0xFFD7F0EC,
  ],
  // Muted "modern" categorical 10.
  'Mode 10': [
    0xFF5DA271,
    0xFF5B8FB9,
    0xFFE3A72F,
    0xFF8CD0B3,
    0xFF9080B0,
    0xFFCC5C5C,
    0xFF3C6E78,
    0xFFDB8FBE,
    0xFFC9733C,
    0xFF8C6D5C,
  ],
  // The 10 hues above paired with lighter tints — 20 distinct fills.
  'Mode 20': [
    0xFF5DA271,
    0xFFAFD3B9,
    0xFF5B8FB9,
    0xFFB3CDE3,
    0xFFE3A72F,
    0xFFF0D79A,
    0xFF8CD0B3,
    0xFFC4E8D8,
    0xFF9080B0,
    0xFFC9C0DC,
    0xFFCC5C5C,
    0xFFE6ABAB,
    0xFF3C6E78,
    0xFF9DBBC0,
    0xFFDB8FBE,
    0xFFEFC9DE,
    0xFFC9733C,
    0xFFE6B292,
    0xFF8C6D5C,
    0xFFC4B0A3,
  ],
  // Jewel tones.
  'Gemstone': [
    0xFFAEA8E0,
    0xFF7E50A0,
    0xFF8FE0CE,
    0xFF4FB39B,
    0xFFE09A2E,
    0xFFB0562B,
    0xFFAA9CA9,
    0xFF6F506C,
    0xFF5E7C82,
    0xFF4F7B67,
  ],
  // Warm coral → green meadow gradient set.
  'Meadow': [
    0xFFE8775B,
    0xFFECAA8D,
    0xFF8FBCA1,
    0xFFC0D9C5,
    0xFFA99C50,
    0xFFE9CF73,
    0xFFBBD25B,
    0xFFEFF1A1,
    0xFF5D602F,
    0xFF8F926F,
  ],
};

/// Resolved fill/border/text colors for a stereotype. [skin] of `Auto` honors
/// the diagram's own skinparam colors (falling back to a theme accent tint);
/// any other skin applies a fixed palette, overriding the file so the selector
/// visibly restyles the diagram. [identity] (the box/group name) is the cycle
/// key for qualitative palettes when a node has no stereotype, so class
/// diagrams get varied colors instead of one flat fill.
({Color background, Color border, Color font}) _stereotypeColors(
  UmlDiagram diagram,
  String? stereotype,
  AppColors appColors,
  String skin, {
  String identity = '',
}) {
  if (skin != 'Auto') {
    return _skinStereotypeColors(skin, stereotype, appColors, identity);
  }
  final style = stereotype == null
      ? null
      : diagram.stereotypeStyles[stereotype];
  final bg = _parseUmlColor(style?.background);
  final border = _parseUmlColor(style?.border);
  final font = _parseUmlColor(style?.font);
  if (bg == null && border == null && font == null) {
    // No declared colors: distinguish stereotypes with a soft accent tint, or
    // fall back to the neutral panel for un-stereotyped nodes.
    if (stereotype == null) {
      return (
        background: appColors.panel,
        border: appColors.border,
        font: appColors.editorText,
      );
    }
    final accent = appColors.accent;
    return (
      background: Color.alphaBlend(accent.withAlpha(28), appColors.panel),
      border: accent.withAlpha(150),
      font: appColors.editorText,
    );
  }
  return (
    background: bg ?? appColors.panel,
    border: border ?? appColors.border,
    font: font ?? appColors.editorText,
  );
}

/// Palette colors for a [skin], used when the skin selector overrides the
/// diagram's own colors. ArchiMate keys on stereotype meaning; qualitative
/// palettes cycle on the stereotype when present, else [identity] (the node
/// name) so every box in a stereotype-less diagram still gets its own color.
({Color background, Color border, Color font}) _skinStereotypeColors(
  String skin,
  String? stereotype,
  AppColors appColors,
  String identity,
) {
  if (skin == 'Monochrome') {
    return (
      background: appColors.panel,
      border: appColors.border,
      font: appColors.editorText,
    );
  }

  // ArchiMate layer colors (and sensible names beyond the canonical layers).
  if (skin == 'ArchiMate') {
    const archimate = <String, int>{
      'business': 0xFFFFF6CC,
      'application': 0xFFC9E7FF,
      'technology': 0xFFD6F0CC,
      'external': 0xFFECECE6,
      'motivation': 0xFFE6D5F5,
      'strategy': 0xFFF5E1C0,
      'implementation': 0xFFFFE0CC,
      'physical': 0xFFD9F2EC,
      'data': 0xFFFFF6CC,
    };
    final bg = Color(archimate[(stereotype ?? '').toLowerCase()] ?? 0xFFEDEDE8);
    return (
      background: bg,
      border: Color.alphaBlend(const Color(0x33000000), bg),
      font: const Color(0xFF1F2328),
    );
  }

  // Qualitative palette: stable pick from the cycle key. A multiplicative
  // string hash spreads similar names across the palette (a plain code-unit
  // sum clusters anagrams onto the same color).
  final palette = _umlPalettes[skin] ?? _umlPalettes['Pastel']!;
  final key = (stereotype?.isNotEmpty ?? false) ? stereotype! : identity;
  final hash = key.toLowerCase().codeUnits.fold<int>(
    7,
    (a, c) => (a * 31 + c) & 0x7fffffff,
  );
  final bg = Color(palette[hash % palette.length]);
  // Darker fills (jewel/strong tones) need light text; tints take dark text.
  final font = bg.computeLuminance() > 0.5
      ? const Color(0xFF1F2328)
      : Colors.white;
  return (
    background: bg,
    border: Color.alphaBlend(const Color(0x40000000), bg),
    font: font,
  );
}

/// Parses a PlantUML color token (`#RGB`, `#RRGGBB`, `#AARRGGBB`) into a Color.
/// Named colors (e.g. `LightBlue`) aren't resolved and return null.
Color? _parseUmlColor(String? token) {
  if (token == null || !token.startsWith('#')) return null;
  var hex = token.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(value);
}

/// Renders PlantUML label escapes (`\n`, `\t`) as real whitespace for display.
/// The stored label keeps the escapes so it round-trips back to valid source.
String _umlDisplayText(String label) =>
    label.replaceAll(r'\n', '\n').replaceAll(r'\t', '  ');

/// A small corner glyph approximating PlantUML/ArchiMate element icons, chosen
/// by stereotype first, then the element keyword.
IconData _umlNodeIcon(UmlType type) {
  switch (type.stereotype?.toLowerCase()) {
    case 'business':
      return Icons.business_center_outlined;
    case 'application':
      return Icons.widgets_outlined;
    case 'technology':
      return Icons.dns_outlined;
    case 'external':
      return Icons.cloud_outlined;
    case 'motivation':
      return Icons.flag_outlined;
  }
  switch (type.nodeKeyword) {
    case 'database':
      return Icons.storage_outlined;
    case 'queue':
      return Icons.view_stream_outlined;
    case 'component':
      return Icons.widgets_outlined;
    case 'actor':
    case 'person':
      return Icons.person_outline;
    case 'cloud':
      return Icons.cloud_outlined;
    case 'node':
      return Icons.dns_outlined;
    case 'folder':
      return Icons.folder_outlined;
    case 'usecase':
      return Icons.adjust_outlined;
    case 'artifact':
      return Icons.description_outlined;
    default:
      return Icons.crop_square;
  }
}

/// Maps a normalized `<<stereotype>>` to a vendored ArchiMate sprite (see
/// `assets/archimate/`). Both the full layer-qualified names
/// (`application-component`) and the common bare names (`component`) resolve;
/// bare names default to their most common ArchiMate layer.
const Map<String, String> _archimateSprites = {
  // Application layer.
  'application-component': 'application-component',
  'component': 'application-component',
  'application-service': 'application-service',
  'application-interface': 'application-interface',
  'interface': 'application-interface',
  'application-function': 'application-function',
  'function': 'application-function',
  'application-data-object': 'application-data-object',
  'application-dataobject': 'application-data-object',
  'data-object': 'application-data-object',
  'dataobject': 'application-data-object',
  // Business layer.
  'business-actor': 'business-actor',
  'actor': 'business-actor',
  'business-process': 'business-process',
  'process': 'business-process',
  'business-service': 'business-service',
  'service': 'application-service', // ambiguous bare name → application layer
  'business-role': 'business-role',
  'role': 'business-role',
  'business-object': 'business-object',
  'object': 'business-object',
  // Technology layer.
  'technology-node': 'technology-node',
  'node': 'technology-node',
  'technology-device': 'technology-device',
  'device': 'technology-device',
  'technology-service': 'technology-service',
  'technology-artifact': 'technology-artifact',
  'artifact': 'technology-artifact',
  // Motivation layer.
  'motivation-requirement': 'motivation-requirement',
  'requirement': 'motivation-requirement',
  'motivation-goal': 'motivation-goal',
  'goal': 'motivation-goal',
};

/// Asset path for a node's ArchiMate sprite, or null if its stereotype doesn't
/// name an ArchiMate element. Stereotypes are normalized so `Application
/// Component`, `application_component` and `application-component` all match.
String? _archimateSpriteFor(UmlType type) {
  final stereotype = type.stereotype;
  if (stereotype == null || stereotype.isEmpty) return null;
  final key = stereotype.toLowerCase().trim().replaceAll(
    RegExp(r'[\s_]+'),
    '-',
  );
  final name = _archimateSprites[key];
  return name == null ? null : 'assets/archimate/$name.svg';
}

/// The top-right element glyph for a node: an ArchiMate sprite (tinted to the
/// node's font color) when the stereotype maps to one, otherwise the Material
/// keyword glyph.
class _NodeGlyph extends StatelessWidget {
  const _NodeGlyph({required this.type, required this.color});

  final UmlType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sprite = _archimateSpriteFor(type);
    if (sprite != null) {
      return SvgPicture.asset(
        sprite,
        width: 15,
        height: 15,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        // Fall back to the Material glyph if the asset fails to load/parse.
        placeholderBuilder: (_) =>
            Icon(_umlNodeIcon(type), size: 13, color: color),
      );
    }
    return Icon(_umlNodeIcon(type), size: 13, color: color);
  }
}

Widget buildUmlClassDiagram() {
  return const _UmlClassDiagramView();
}

class _UmlClassDiagramView extends StatefulWidget {
  const _UmlClassDiagramView();

  @override
  State<_UmlClassDiagramView> createState() => _UmlClassDiagramViewState();
}

class _UmlClassDiagramViewState extends State<_UmlClassDiagramView> {
  final TextEditingController _source = TextEditingController();
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'uml-canvas');
  final GlobalKey _diagramCaptureKey = GlobalKey();
  final ValueNotifier<int?> _highlightLine = ValueNotifier<int?>(null);
  late final String _canvasDropId =
      'uml-canvas-drop-${identityHashCode(this).toRadixString(16)}';
  late UmlDiagram _diagram;
  String? _selected;
  String? _selectedGroup;
  String? _editing; // name of the box being renamed inline on the canvas
  Offset _pan = Offset.zero;
  double _scale = 1.0;
  Size _canvasViewport = Size.zero;
  String _bgStyle = 'App';
  String _nodeSkin = 'Auto';
  Timer? _debounce;

  // Snap-to-grid: when on, dragging/resizing/placing elements aligns to a grid
  // and a grid overlay is drawn. The raw fields hold the un-snapped position
  // during a drag so slow drags still accumulate toward the next grid line.
  bool _snapToGrid = false;
  static const double _gridStep = 20.0;
  Offset? _dragRaw; // active box drag, raw absolute position
  Offset? _groupRaw; // active group drag, raw absolute anchor

  double _snapVal(double v) => (v / _gridStep).round() * _gridStep;
  double _maybeSnap(double v) => _snapToGrid ? _snapVal(v) : v;

  static const String _sample = '''
@startuml
class User {
  +id: int
  +name: String
  -password: String
  +login(pw: String): bool
}
interface Repository {
  +save(item)
  +findById(id): Item
}
abstract class Entity {
  +id: int
}
enum Role {
  ADMIN
  MEMBER
  GUEST
}
class Order {
  +total: double
}
User --> Order : places
User ..|> Repository
User --|> Entity
Order *-- LineItem
User --> Role : has
@enduml''';

  @override
  void initState() {
    super.initState();
    _diagram = PlantUmlService.parse(_sample);
    _source.text = PlantUmlService.generate(_diagram);
    _scheduleFit();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _canvasFocus.dispose();
    _highlightLine.dispose();
    _source.dispose();
    super.dispose();
  }

  // Finds the 0-based source line that declares [name], so selecting a box on
  // the canvas can reveal its definition in the editor.
  int? _sourceLineForType(String name) {
    final label = _diagram.typeByName(name)?.label;
    final lines = _source.text.split('\n');
    final aliasPat = RegExp(r'\bas\s+' + RegExp.escape(name) + r'\b');
    int? labelLine;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trimLeft();
      if (l.startsWith("'")) continue; // comments incl. @pos
      if (aliasPat.hasMatch(l)) return i;
      if (labelLine == null && label != null && l.contains('"$label"')) {
        labelLine = i;
      }
    }
    if (labelLine != null) return labelLine;
    final namePat = RegExp(r'\b' + RegExp.escape(name) + r'\b');
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trimLeft();
      if (l.startsWith("'")) continue;
      if (namePat.hasMatch(l)) return i;
    }
    return null;
  }

  int? _sourceLineForGroup(String id) {
    final group = _diagram.groupById(id);
    final lines = _source.text.split('\n');
    final aliasPat = RegExp(r'\bas\s+' + RegExp.escape(id) + r'\b');
    int? labelLine;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trimLeft();
      if (l.startsWith("'")) continue;
      if (!l.contains('{')) continue;
      if (aliasPat.hasMatch(l)) return i;
      if (labelLine == null &&
          group != null &&
          l.contains('"${group.label}"')) {
        labelLine = i;
      }
    }
    if (labelLine != null) return labelLine;
    final namePat = RegExp(r'\b' + RegExp.escape(id) + r'\b');
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trimLeft();
      if (l.startsWith("'")) continue;
      if (l.contains('{') && namePat.hasMatch(l)) return i;
    }
    return null;
  }

  void _selectType(String? name) {
    final changed = name != _selected || _selectedGroup != null;
    if (!_canvasFocus.hasFocus) _canvasFocus.requestFocus();
    setState(() {
      _selected = name;
      _selectedGroup = null;
    });
    // Only drive the editor when the selection actually changes — re-clicking
    // the same node must not repeatedly poke the editor's focus/scroll state.
    if (name != null && changed) {
      final line = _sourceLineForType(name);
      if (line != null) _highlightLine.value = line;
    }
  }

  void _selectGroup(String? id) {
    final changed = id != _selectedGroup || _selected != null;
    if (!_canvasFocus.hasFocus) _canvasFocus.requestFocus();
    setState(() {
      _selected = null;
      _selectedGroup = id;
    });
    if (id != null && changed) {
      final line = _sourceLineForGroup(id);
      if (line != null) _highlightLine.value = line;
    }
  }

  // User edited the source: reparse (debounced), preserving box positions for
  // types that still exist.
  void _onSourceChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final next = PlantUmlService.parse(_source.text, previous: _diagram);
      setState(() {
        _diagram = next;
        if (_selected != null && next.typeByName(_selected!) == null) {
          _selected = null;
        }
        if (_selectedGroup != null && next.groupById(_selectedGroup!) == null) {
          _selectedGroup = null;
        }
      });
    });
  }

  // Rewrite the source from the current diagram (after a spatial/structural
  // canvas edit). Does not fire the editor's onChanged, so no reparse loop.
  void _syncSource() {
    _source.text = PlantUmlService.generate(_diagram);
  }

  String _uniqueName(String base) {
    if (_diagram.typeByName(base) == null) return base;
    var i = 2;
    while (_diagram.typeByName('$base$i') != null) {
      i++;
    }
    return '$base$i';
  }

  void _addClass() {
    // Drop the new class at the centre of the current view so it's visible and
    // immediately reachable (not off-screen below everything).
    final center = _canvasViewport == Size.zero
        ? const Offset(80, 80)
        : (Offset(_canvasViewport.width / 2, _canvasViewport.height / 2) -
                  _pan) /
              _scale;
    final type = UmlType(
      name: _uniqueName('NewClass'),
      x: _maybeSnap((center.dx - _umlBoxWidth / 2).clamp(0, double.infinity)),
      y: _maybeSnap((center.dy - 40).clamp(0, double.infinity)),
      members: [
        UmlMember(visibility: UmlVisibility.public, text: 'field: Type'),
      ],
    );
    setState(() {
      _diagram.types.add(type);
      _selected = type.name;
      _selectedGroup = null;
      _editing = type.name; // open the inline name editor right away
      _syncSource();
    });
  }

  void _beginEdit(String name) {
    setState(() {
      _selected = name;
      _selectedGroup = null;
      _editing = name;
    });
  }

  void _endEdit() {
    if (_editing != null) setState(() => _editing = null);
  }

  // Commit an inline rename from the canvas. For architecture nodes only the
  // display label changes (the alias/relations are preserved); for class-like
  // types the identifier changes, so relations referencing it are updated too.
  void _renameType(String oldName, String text) {
    final trimmed = text.trim();
    final type = _diagram.typeByName(oldName);
    setState(() {
      _editing = null;
      if (type == null || trimmed.isEmpty) return;
      if (type.kind == UmlTypeKind.node) {
        type.label = trimmed;
      } else {
        if (trimmed != oldName && _diagram.typeByName(trimmed) == null) {
          for (final r in _diagram.relations) {
            if (r.from == oldName) r.from = trimmed;
            if (r.to == oldName) r.to = trimmed;
          }
          type.name = trimmed;
        }
        type.label = trimmed;
      }
      _selected = type.name;
      _selectedGroup = null;
      _syncSource();
    });
  }

  // Palette of elements offered by the right-click "Add" menu.
  // (label, kind, nodeKeyword, stereotype, icon)
  static const List<(String, UmlTypeKind, String?, String?, IconData)>
  _palette = [
    ('Class', UmlTypeKind.classType, null, null, Icons.data_object),
    ('Interface', UmlTypeKind.interfaceType, null, null, Icons.share_outlined),
    ('Rectangle', UmlTypeKind.node, 'rectangle', null, Icons.crop_square),
    ('Component', UmlTypeKind.node, 'component', null, Icons.widgets_outlined),
    ('Server', UmlTypeKind.node, 'node', null, Icons.dns_outlined),
    ('Database', UmlTypeKind.node, 'database', null, Icons.storage_outlined),
    ('Queue', UmlTypeKind.node, 'queue', null, Icons.view_stream_outlined),
    ('Cloud', UmlTypeKind.node, 'cloud', null, Icons.cloud_outlined),
    ('Actor', UmlTypeKind.node, 'actor', null, Icons.person_outline),
    ('API service', UmlTypeKind.node, 'rectangle', 'api', Icons.api_outlined),
    ('External', UmlTypeKind.node, 'rectangle', 'external', Icons.public),
    ('Note', UmlTypeKind.node, 'note', null, Icons.sticky_note_2_outlined),
  ];

  void _addElement({
    required UmlTypeKind kind,
    String? nodeKeyword,
    String? stereotype,
    required String baseName,
    required Offset at,
  }) {
    final boxWidth = kind == UmlTypeKind.node
        ? PlantUmlService.nodeWidth
        : _umlBoxWidth;
    final name = _uniqueName(baseName.replaceAll(' ', ''));
    final type = UmlType(
      name: name,
      label: name,
      kind: kind,
      nodeKeyword: nodeKeyword,
      stereotype: stereotype,
      members: kind == UmlTypeKind.node
          ? <UmlMember>[]
          : [UmlMember(visibility: UmlVisibility.public, text: 'field: Type')],
      x: _maybeSnap((at.dx - boxWidth / 2).clamp(0, double.infinity)),
      y: _maybeSnap((at.dy - 40).clamp(0, double.infinity)),
    );
    setState(() {
      _diagram.types.add(type);
      _selected = name;
      _selectedGroup = null;
      _editing = name;
      _syncSource();
    });
  }

  // Right-click on empty canvas: choose an element to create at that point.
  Future<void> _showCanvasMenu(Offset globalPos, Offset localPos) async {
    final at = (localPos - _pan) / _scale;
    final appColors = context.appColors;
    final choice = await showMenu<int>(
      context: context,
      color: appColors.panelElevated,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx,
        globalPos.dy,
      ),
      items: [
        PopupMenuItem<int>(
          enabled: false,
          height: 30,
          child: Text(
            'Add element',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: appColors.mutedText,
            ),
          ),
        ),
        for (var i = 0; i < _palette.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 36,
            child: Row(
              children: [
                Icon(_palette[i].$5, size: 16, color: appColors.mutedText),
                const SizedBox(width: 10),
                Text(_palette[i].$1),
              ],
            ),
          ),
      ],
    );
    if (choice == null || !mounted) return;
    final e = _palette[choice];
    _addElement(
      kind: e.$2,
      nodeKeyword: e.$3,
      stereotype: e.$4,
      baseName: 'New${e.$1.replaceAll(' ', '')}',
      at: at,
    );
  }

  // Right-click on a box: rename or delete it.
  Future<void> _showNodeMenu(String name, Offset globalPos) async {
    setState(() {
      _selected = name;
      _selectedGroup = null;
    });
    final appColors = context.appColors;
    final type = _diagram.typeByName(name);
    final currentGroup = type?.groupId;
    // Existing packages the box could move into (excluding the one it's in).
    final packages = _diagram.groups
        .where((g) => g.keyword == 'package' && g.id != currentGroup)
        .toList();
    final action = await showMenu<String>(
      context: context,
      color: appColors.panelElevated,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx,
        globalPos.dy,
      ),
      items: [
        _nodeMenuItem('rename', Icons.edit_outlined, 'Rename'),
        _nodeMenuItem('color', Icons.palette_outlined, 'Background color…'),
        const PopupMenuDivider(),
        _nodeMenuItem(
          'wrap',
          Icons.create_new_folder_outlined,
          'Wrap in package',
        ),
        if (packages.isNotEmpty)
          _nodeMenuItem(
            'move',
            Icons.drive_file_move_outlined,
            'Move to package…',
          ),
        if (currentGroup != null)
          _nodeMenuItem(
            'remove',
            Icons.folder_off_outlined,
            'Remove from package',
          ),
        const PopupMenuDivider(),
        _nodeMenuItem('delete', Icons.delete_outline, 'Delete'),
      ],
    );
    if (!mounted) return;
    if (action == 'rename') {
      _beginEdit(name);
    } else if (action == 'color') {
      await _pickColor(name);
    } else if (action == 'wrap') {
      _wrapInPackage(name);
    } else if (action == 'move') {
      await _showMoveToPackageMenu(name, globalPos, packages);
    } else if (action == 'remove') {
      _removeFromPackage(name);
    } else if (action == 'delete') {
      _deleteSelected();
    }
  }

  PopupMenuItem<String> _nodeMenuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: SizedBox(
        width: 180,
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 10),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Future<void> _showGroupMenu(String id, Offset globalPos) async {
    setState(() {
      _selected = null;
      _selectedGroup = id;
    });
    final appColors = context.appColors;
    final action = await showMenu<String>(
      context: context,
      color: appColors.panelElevated,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx,
        globalPos.dy,
      ),
      items: [
        _nodeMenuItem('rename', Icons.edit_outlined, 'Rename…'),
        _nodeMenuItem('color', Icons.palette_outlined, 'Background color…'),
        const PopupMenuDivider(),
        _nodeMenuItem(
          'ungroup',
          Icons.call_split_outlined,
          'Move contents out',
        ),
      ],
    );
    if (!mounted) return;
    if (action == 'rename') {
      await _renameGroupDialog(id);
    } else if (action == 'color') {
      await _pickGroupColor(id);
    } else if (action == 'ungroup') {
      _ungroupGroup(id);
    }
  }

  void _ungroupGroup(String id) {
    final group = _diagram.groupById(id);
    if (group == null) return;
    final parentId = group.parentId;
    setState(() {
      for (final t in _diagram.types) {
        if (t.groupId == id) t.groupId = parentId;
      }
      for (final child in _diagram.groups) {
        if (child.parentId == id) child.parentId = parentId;
      }
      _diagram.groups.removeWhere((g) => g.id == id);
      _selectedGroup = null;
      if (_diagram.hasGroups) PlantUmlService.relayoutGroups(_diagram);
      _syncSource();
    });
  }

  // A package id must be unique across both groups and types, because both
  // share the identifier namespace in the generated source.
  String _uniqueGroupId(String base) {
    bool taken(String id) =>
        _diagram.groupById(id) != null || _diagram.typeByName(id) != null;
    if (!taken(base)) return base;
    var i = 2;
    while (taken('$base$i')) {
      i++;
    }
    return '$base$i';
  }

  // Wrap a single box in a brand-new package. The package nests inside whatever
  // group the box was already in, so existing containment is preserved.
  void _wrapInPackage(String name) {
    final type = _diagram.typeByName(name);
    if (type == null) return;
    final id = _uniqueGroupId('Package');
    setState(() {
      _diagram.groups.add(
        UmlGroup(id: id, label: id, keyword: 'package', parentId: type.groupId),
      );
      type.groupId = id;
      PlantUmlService.relayoutGroups(_diagram);
      _selected = null;
      _selectedGroup = id;
      _syncSource();
    });
    // Prompt for a name straight away — groups have no inline canvas editor.
    _renameGroupDialog(id);
  }

  void _renameGroup(String id, String text) {
    final group = _diagram.groupById(id);
    final trimmed = text.trim();
    if (group == null || trimmed.isEmpty) return;
    setState(() {
      group.label = trimmed;
      // Promote the label to the id/alias when it's a clean identifier that
      // isn't already taken — keeps the generated source tidy. Otherwise keep
      // the stable id and let the generator emit `as <id>`.
      final canUseAsId =
          RegExp(r'^[\w.]+$').hasMatch(trimmed) &&
          trimmed != id &&
          _diagram.groupById(trimmed) == null &&
          _diagram.typeByName(trimmed) == null;
      if (canUseAsId) {
        for (final t in _diagram.types) {
          if (t.groupId == id) t.groupId = trimmed;
        }
        for (final g in _diagram.groups) {
          if (g.parentId == id) g.parentId = trimmed;
        }
        for (final r in _diagram.relations) {
          if (r.from == id) r.from = trimmed;
          if (r.to == id) r.to = trimmed;
        }
        group.id = trimmed;
        if (_selectedGroup == id) _selectedGroup = trimmed;
      }
      _syncSource();
    });
  }

  Future<void> _renameGroupDialog(String id) async {
    final group = _diagram.groupById(id);
    if (group == null) return;
    final controller = TextEditingController(text: group.label);
    final appColors = context.appColors;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: appColors.panel,
        title: const Text('Rename package'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Package name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || result == null) return;
    _renameGroup(id, result);
  }

  // Move an existing box into an existing package.
  void _addToPackage(String name, String groupId) {
    final type = _diagram.typeByName(name);
    if (type == null) return;
    setState(() {
      type.groupId = groupId;
      if (_diagram.hasGroups) PlantUmlService.relayoutGroups(_diagram);
      _selected = name;
      _selectedGroup = null;
      _syncSource();
    });
  }

  // Pop a box out of its package, back up to the package's parent (or to the
  // top level if the package was top-level).
  void _removeFromPackage(String name) {
    final type = _diagram.typeByName(name);
    if (type == null || type.groupId == null) return;
    final parent = _diagram.groupById(type.groupId!)?.parentId;
    setState(() {
      type.groupId = parent;
      if (_diagram.hasGroups) PlantUmlService.relayoutGroups(_diagram);
      _selected = name;
      _selectedGroup = null;
      _syncSource();
    });
  }

  // Secondary menu: choose which existing package to move the box into.
  Future<void> _showMoveToPackageMenu(
    String name,
    Offset globalPos,
    List<UmlGroup> packages,
  ) async {
    final appColors = context.appColors;
    final chosen = await showMenu<String>(
      context: context,
      color: appColors.panelElevated,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx,
        globalPos.dy,
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 30,
          child: Text(
            'Move to package',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: appColors.mutedText,
            ),
          ),
        ),
        for (final g in packages)
          PopupMenuItem<String>(
            value: g.id,
            height: 36,
            child: SizedBox(
              width: 180,
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: appColors.mutedText,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(g.label, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    if (!mounted || chosen == null) return;
    _addToPackage(name, chosen);
  }

  // Swatch dialog shared by node and package background-color pickers. Returns
  // a `#RRGGBB` hex, the sentinel `'default'`, or null if cancelled.
  Future<String?> _pickSwatch() {
    const swatches = <int>[
      0xFFEF9A9A,
      0xFFF48FB1,
      0xFFCE93D8,
      0xFFB39DDB,
      0xFF9FA8DA,
      0xFF90CAF9,
      0xFF80DEEA,
      0xFF80CBC4,
      0xFFA5D6A7,
      0xFFC5E1A5,
      0xFFFFF59D,
      0xFFFFE082,
      0xFFFFCC80,
      0xFFBCAAA4,
      0xFFB0BEC5,
      0xFFE57373,
      0xFF64B5F6,
      0xFF4DB6AC,
      0xFF81C784,
      0xFFFFB74D,
    ];
    final appColors = context.appColors;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: appColors.panel,
        title: const Text('Background color'),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final argb in swatches)
                _ColorSwatchDot(
                  color: Color(argb),
                  onTap: () => Navigator.of(ctx).pop(
                    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('default'),
            child: const Text('Default'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // Swatch picker for a box background color (right-click → Background color).
  Future<void> _pickColor(String name) async {
    final type = _diagram.typeByName(name);
    if (type == null) return;
    final picked = await _pickSwatch();
    if (!mounted || picked == null) return;
    setState(() {
      type.color = picked == 'default' ? null : picked;
      _selected = name;
      _selectedGroup = null;
      _syncSource();
    });
  }

  // Swatch picker for a package background color (right-click → Background
  // color). Mirrors [_pickColor] but targets a group.
  Future<void> _pickGroupColor(String id) async {
    final group = _diagram.groupById(id);
    if (group == null) return;
    final picked = await _pickSwatch();
    if (!mounted || picked == null) return;
    setState(() {
      group.color = picked == 'default' ? null : picked;
      _selected = null;
      _selectedGroup = id;
      _syncSource();
    });
  }

  void _deleteSelected() {
    final name = _selected;
    if (name == null) return;
    setState(() {
      _diagram.types.removeWhere((t) => t.name == name);
      _diagram.relations.removeWhere((r) => r.from == name || r.to == name);
      _selected = null;
      _selectedGroup = null;
      _syncSource();
    });
  }

  void _tidyLayout() {
    setState(() {
      PlantUmlService.autoLayout(_diagram);
      _syncSource();
    });
    _scheduleFit();
  }

  // ---- Save / export -------------------------------------------------------

  // A filename-safe base derived from the diagram title/name, else 'diagram'.
  String _diagramFileBase() {
    final name = _diagram.title ?? _diagram.name;
    final base = (name ?? '')
        .trim()
        .replaceAll(RegExp(r'[^\w\-. ]'), '')
        .trim();
    return base.isEmpty ? 'diagram' : base;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  // Save the PlantUML source to a .puml file via the native save panel.
  Future<void> _savePuml() async {
    final path = await FileDialogService.saveFile(
      suggestedName: '${_diagramFileBase()}.puml',
      allowedExtensions: const ['puml', 'txt'],
    );
    if (path == null) return;
    try {
      await File(path).writeAsString(_source.text);
      _toast('Saved ${p.basename(path)}');
    } catch (e) {
      _toast('Save failed: $e');
    }
  }

  // Rasterize the whole diagram (independent of current zoom/pan) to PNG.
  Future<({Uint8List bytes, Size size})?> _captureDiagram() async {
    final capture = await DiagramExportService.capturePng(_diagramCaptureKey);
    if (capture == null) _toast('Nothing to export');
    return capture;
  }

  Future<void> _exportPng() async {
    final capture = await _captureDiagram();
    if (capture == null || !mounted) return;
    final path = await FileDialogService.saveFile(
      suggestedName: '${_diagramFileBase()}.png',
      allowedExtensions: const ['png'],
    );
    if (path == null) return;
    try {
      await File(path).writeAsBytes(capture.bytes);
      _toast('Exported ${p.basename(path)}');
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  Future<void> _exportPdf() async {
    final capture = await _captureDiagram();
    if (capture == null || !mounted) return;
    final pdf = await DiagramExportService.buildPdf(
      capture.bytes,
      capture.size,
    );
    if (!mounted) return;
    final path = await FileDialogService.saveFile(
      suggestedName: '${_diagramFileBase()}.pdf',
      allowedExtensions: const ['pdf'],
    );
    if (path == null) return;
    try {
      await File(path).writeAsBytes(pdf);
      _toast('Exported ${p.basename(path)}');
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  // Opens the native print / "Save as PDF" dialog for the captured diagram.
  Future<void> _printDiagram() async {
    final capture = await _captureDiagram();
    if (capture == null) return;
    await DiagramExportService.printPng(
      capture.bytes,
      capture.size,
      title: _diagramFileBase(),
    );
  }

  void _setSample() {
    setState(() {
      _diagram = PlantUmlService.parse(_sample);
      _selected = null;
      _selectedGroup = null;
      _source.text = PlantUmlService.generate(_diagram);
    });
    _scheduleFit();
  }

  void _clear() {
    setState(() {
      _diagram = UmlDiagram();
      _selected = null;
      _selectedGroup = null;
      _pan = Offset.zero;
      _scale = 1.0;
      _source.text = PlantUmlService.generate(_diagram);
    });
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    if (text.isEmpty) return;
    setState(() {
      _diagram = PlantUmlService.parse(text);
      _selected = null;
      _selectedGroup = null;
      _source.text = PlantUmlService.generate(_diagram);
    });
    _scheduleFit();
  }

  // A .puml/.txt file dropped on the canvas: load and parse it.
  Future<void> _loadDroppedFile(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      final file = File(paths.first);
      if (!await file.exists()) return;
      if (await file.length() > 5 * 1024 * 1024) return;
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _diagram = PlantUmlService.parse(text);
        _selected = null;
        _selectedGroup = null;
        _source.text = PlantUmlService.generate(_diagram);
      });
      _scheduleFit();
    } catch (_) {
      // Binary or unreadable file: leave the diagram untouched.
    }
  }

  void _onBoxDrag(UmlType type, Offset delta) {
    setState(() {
      // Gesture delta is in screen space; convert to canvas space at zoom.
      final dx = delta.dx / _scale;
      final dy = delta.dy / _scale;
      if (_snapToGrid) {
        _dragRaw = (_dragRaw ?? Offset(type.x, type.y)) + Offset(dx, dy);
        type.x = max(0, _snapVal(_dragRaw!.dx));
        type.y = max(0, _snapVal(_dragRaw!.dy));
      } else {
        type.x = max(0, type.x + dx);
        type.y = max(0, type.y + dy);
      }
      // Keep package/composite containers wrapped around their contents.
      if (_diagram.hasGroups) PlantUmlService.relayoutGroups(_diagram);
    });
  }

  void _onBoxDragEnd() {
    _dragRaw = null;
    _syncSource();
  }

  // Dragging a container's title moves it and everything inside it.
  void _onGroupDrag(UmlGroup group, Offset delta) {
    final ids = _descendantGroupIds(group);
    setState(() {
      var adx = delta.dx / _scale;
      var ady = delta.dy / _scale;
      if (_snapToGrid) {
        _groupRaw = (_groupRaw ?? Offset(group.x, group.y)) + Offset(adx, ady);
        // Snap the container's anchor; move members by the resulting step so
        // their relative layout is preserved.
        adx = _snapVal(_groupRaw!.dx) - group.x;
        ady = _snapVal(_groupRaw!.dy) - group.y;
      }
      for (final t in _diagram.types) {
        if (t.groupId != null && ids.contains(t.groupId)) {
          t.x += adx;
          t.y += ady;
        }
      }
      PlantUmlService.relayoutGroups(_diagram);
    });
  }

  void _onGroupDragEnd() {
    _groupRaw = null;
    _syncSource();
  }

  // Resize a box by dragging one of its selection handles. [handle] is a
  // compass id (n/s/e/w/ne/nw/se/sw).
  void _onResize(UmlType type, String handle, Offset delta) {
    const minW = 90.0;
    // Don't let class boxes shrink below their content (avoids clipping rows);
    // nodes scale their label, so they can go smaller. Note: class-like boxes
    // are content-height ([_umlBoxSize] ignores a stored height), so a vertical
    // drag stores a height that doesn't change the box — width is what matters.
    final minH = type.kind == UmlTypeKind.node ? 48.0 : _umlBoxHeight(type);
    final d = Offset(delta.dx / _scale, delta.dy / _scale);
    final size = _umlBoxSize(type);
    var w = type.w ?? size.width;
    var h = type.h ?? size.height;
    var x = type.x;
    var y = type.y;

    if (handle.contains('e')) w += d.dx;
    if (handle.contains('w')) {
      w -= d.dx;
      x += d.dx;
    }
    if (handle.contains('s')) h += d.dy;
    if (handle.contains('n')) {
      h -= d.dy;
      y += d.dy;
    }
    // Respect minimums; when dragging the top/left edge, pin the opposite edge.
    if (w < minW) {
      if (handle.contains('w')) x -= minW - w;
      w = minW;
    }
    if (h < minH) {
      if (handle.contains('n')) y -= minH - h;
      h = minH;
    }

    setState(() {
      type
        ..w = w
        ..h = h
        ..x = x
        ..y = y;
      if (_diagram.hasGroups) PlantUmlService.relayoutGroups(_diagram);
    });
  }

  // Snap the resized box to the grid on release (resizing is fluid, the result
  // lands aligned).
  void _onResizeEnd() {
    final type = _selected == null ? null : _diagram.typeByName(_selected!);
    if (_snapToGrid && type != null) {
      setState(() {
        type
          ..x = _snapVal(type.x)
          ..y = _snapVal(type.y)
          ..w = type.w == null ? null : _snapVal(type.w!)
          ..h = type.h == null ? null : _snapVal(type.h!);
        if (_diagram.hasGroups) PlantUmlService.relayoutGroups(_diagram);
      });
    }
    _syncSource();
  }

  Set<String> _descendantGroupIds(UmlGroup group) {
    final ids = <String>{group.id};
    var added = true;
    while (added) {
      added = false;
      for (final g in _diagram.groups) {
        if (g.parentId != null && ids.contains(g.parentId) && ids.add(g.id)) {
          added = true;
        }
      }
    }
    return ids;
  }

  // Trackpad scroll / pinch: zoom toward [focal] (canvas-viewport coords),
  // keeping the point under the cursor stationary.
  void _onZoom(double factor, Offset focal) {
    final newScale = (_scale * factor).clamp(0.25, 4.0);
    if (newScale == _scale) return;
    final anchor = (focal - _pan) / _scale;
    setState(() {
      _pan = focal - anchor * newScale;
      _scale = newScale;
    });
  }

  // Trackpad pinch (and two-finger pan): macOS delivers these as PanZoom
  // events. [scale] is cumulative since the gesture started.
  double _gestureBaseScale = 1.0;

  void _onScaleStart() => _gestureBaseScale = _scale;

  // A two-finger pan on macOS reports small incidental scale jitter (~1–3%)
  // even when the user isn't pinching. Treating that as zoom re-anchors around
  // the cursor, which shifts far elements more than near ones — the diagram
  // appears to pan at different speeds / with a parallax offset. Only engage
  // zoom once the cumulative scale clears this deadzone.
  static const double _pinchDeadzone = 0.04;

  void _onScaleUpdate(double cumulativeScale, Offset focal, Offset panDelta) {
    setState(() {
      _pan += panDelta; // two-finger pan always translates 1:1
      if ((cumulativeScale - 1.0).abs() < _pinchDeadzone) {
        return; // jitter, not a pinch
      }
      final newScale = (_gestureBaseScale * cumulativeScale).clamp(0.25, 4.0);
      if (newScale == _scale) return;
      final anchor = (focal - _pan) / _scale;
      _pan = focal - anchor * newScale;
      _scale = newScale;
    });
  }

  // Toolbar +/- buttons zoom around the canvas center.
  void _zoomBy(double factor) {
    final focal = _canvasViewport == Size.zero
        ? Offset.zero
        : Offset(_canvasViewport.width / 2, _canvasViewport.height / 2);
    _onZoom(factor, focal);
  }

  void _resetView() => setState(() {
    _pan = Offset.zero;
    _scale = 1.0;
  });

  // Zoom/pan so the whole diagram fits the viewport — every element is then
  // on-screen and grabbable (off-canvas elements can't be hovered or dragged).
  void _fitToView() {
    if (_canvasViewport == Size.zero) {
      _resetView();
      return;
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final t in _diagram.types) {
      final s = _umlBoxSize(t);
      minX = min(minX, t.x);
      minY = min(minY, t.y);
      maxX = max(maxX, t.x + s.width);
      maxY = max(maxY, t.y + s.height);
    }
    for (final g in _diagram.groups) {
      minX = min(minX, g.x);
      minY = min(minY, g.y);
      maxX = max(maxX, g.x + g.w);
      maxY = max(maxY, g.y + g.h);
    }
    if (minX == double.infinity) {
      _resetView();
      return;
    }
    const margin = 36.0;
    final contentW = (maxX - minX) + margin * 2;
    final contentH = (maxY - minY) + margin * 2;
    final scale = min(
      min(_canvasViewport.width / contentW, _canvasViewport.height / contentH),
      1.0,
    ).clamp(0.25, 1.0).toDouble();
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    setState(() {
      _scale = scale;
      _pan = Offset(
        _canvasViewport.width / 2 - centerX * scale,
        _canvasViewport.height / 2 - centerY * scale,
      );
    });
  }

  // Fit after the next frame, once the canvas viewport size is known.
  void _scheduleFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitToView();
    });
  }

  @override
  Widget build(BuildContext context) {
    final split = ResizableSplit(
      horizontal: true,
      initialRatio: 0.6,
      minFirstExtent: 280,
      minSecondExtent: 240,
      first: _UmlCanvasPane(
        diagram: _diagram,
        selected: _selected,
        selectedGroup: _selectedGroup,
        pan: _pan,
        scale: _scale,
        focusNode: _canvasFocus,
        dropTargetId: _canvasDropId,
        onDropFile: _loadDroppedFile,
        onZoom: _onZoom,
        onZoomIn: () => _zoomBy(1.25),
        onZoomOut: () => _zoomBy(0.8),
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onFit: _fitToView,
        onViewport: (size) => _canvasViewport = size,
        bgStyle: _bgStyle,
        nodeSkin: _nodeSkin,
        snapToGrid: _snapToGrid,
        gridStep: _gridStep,
        onBgStyle: (v) => setState(() => _bgStyle = v),
        onNodeSkin: (v) => setState(() => _nodeSkin = v),
        onToggleSnap: () => setState(() => _snapToGrid = !_snapToGrid),
        onAddClass: _addClass,
        onTidy: _tidyLayout,
        onDeleteSelected: _deleteSelected,
        onSelect: _selectType,
        onSelectGroup: _selectGroup,
        onPan: (delta) => setState(() => _pan += delta),
        onBoxDrag: _onBoxDrag,
        onBoxDragEnd: _onBoxDragEnd,
        onGroupDrag: _onGroupDrag,
        onGroupDragEnd: _onGroupDragEnd,
        onGroupMenu: _showGroupMenu,
        editing: _editing,
        onRename: _renameType,
        onEndEdit: _endEdit,
        onNodeMenu: _showNodeMenu,
        onCanvasMenu: _showCanvasMenu,
        onResize: _onResize,
        onResizeEnd: _onResizeEnd,
        captureKey: _diagramCaptureKey,
        onSavePuml: _savePuml,
        onExportPng: _exportPng,
        onExportPdf: _exportPdf,
        onPrint: _printDiagram,
      ),
      second: EditorPane(
        label: 'PlantUML',
        actions: [
          ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
          ToolButton(label: 'Sample', onPressed: _setSample),
          ToolButton(label: 'Clear', onPressed: _clear),
        ],
        controller: _source,
        onChanged: _onSourceChanged,
        revealLine: _highlightLine,
        highlightTheme: plantUmlCodeTheme(context.appColors),
        placeholder:
            'Drop a .puml file here, or type PlantUML '
            '(class or rectangle/package) syntax...',
        copyAction: () => Clipboard.setData(ClipboardData(text: _source.text)),
      ),
    );
    return split;
  }
}

class _UmlCanvasPane extends StatelessWidget {
  const _UmlCanvasPane({
    required this.diagram,
    required this.selected,
    required this.selectedGroup,
    required this.pan,
    required this.scale,
    required this.focusNode,
    required this.dropTargetId,
    required this.onDropFile,
    required this.onZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onFit,
    required this.onViewport,
    required this.bgStyle,
    required this.nodeSkin,
    required this.snapToGrid,
    required this.gridStep,
    required this.onBgStyle,
    required this.onNodeSkin,
    required this.onToggleSnap,
    required this.onAddClass,
    required this.onTidy,
    required this.onDeleteSelected,
    required this.onSelect,
    required this.onSelectGroup,
    required this.onPan,
    required this.onBoxDrag,
    required this.onBoxDragEnd,
    required this.onGroupDrag,
    required this.onGroupDragEnd,
    required this.onGroupMenu,
    required this.editing,
    required this.onRename,
    required this.onEndEdit,
    required this.onNodeMenu,
    required this.onCanvasMenu,
    required this.onResize,
    required this.onResizeEnd,
    required this.captureKey,
    required this.onSavePuml,
    required this.onExportPng,
    required this.onExportPdf,
    required this.onPrint,
  });

  /// Wraps the full-extent diagram content so it can be rasterized for export
  /// independent of the current pan/zoom.
  final GlobalKey captureKey;
  final VoidCallback onSavePuml;
  final VoidCallback onExportPng;
  final VoidCallback onExportPdf;
  final VoidCallback onPrint;

  final UmlDiagram diagram;
  final String? selected;
  final String? selectedGroup;
  final String? editing;
  final Offset pan;
  final double scale;
  final FocusNode focusNode;
  final String dropTargetId;
  final FileDropHandler onDropFile;
  final void Function(String oldName, String text) onRename;
  final VoidCallback onEndEdit;
  final void Function(String name, Offset globalPos) onNodeMenu;
  final void Function(Offset globalPos, Offset localPos) onCanvasMenu;
  final void Function(UmlType type, String handle, Offset delta) onResize;
  final VoidCallback onResizeEnd;
  final void Function(double factor, Offset focal) onZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onScaleStart;
  final void Function(double cumulativeScale, Offset focal, Offset panDelta)
  onScaleUpdate;
  final VoidCallback onFit;
  final ValueChanged<Size> onViewport;
  final String bgStyle;
  final String nodeSkin;
  final bool snapToGrid;
  final double gridStep;
  final ValueChanged<String> onBgStyle;
  final ValueChanged<String> onNodeSkin;
  final VoidCallback onToggleSnap;
  final VoidCallback onAddClass;
  final VoidCallback onTidy;
  final VoidCallback onDeleteSelected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String?> onSelectGroup;
  final ValueChanged<Offset> onPan;
  final void Function(UmlType type, Offset delta) onBoxDrag;
  final VoidCallback onBoxDragEnd;
  final void Function(UmlGroup group, Offset delta) onGroupDrag;
  final VoidCallback onGroupDragEnd;
  final void Function(String id, Offset globalPos) onGroupMenu;

  Size _canvasExtent(Size viewport) {
    var maxRight = viewport.width;
    var maxBottom = viewport.height;
    for (final t in diagram.types) {
      final size = _umlBoxSize(t);
      maxRight = max(maxRight, t.x + size.width + 80);
      maxBottom = max(maxBottom, t.y + size.height + 80);
    }
    for (final g in diagram.groups) {
      maxRight = max(maxRight, g.x + g.w + 80);
      maxBottom = max(maxBottom, g.y + g.h + 80);
    }
    return Size(maxRight, maxBottom);
  }

  /// Groups ordered parents-first so nested containers paint on top.
  List<UmlGroup> get _groupsByDepth {
    int depth(UmlGroup g) {
      var d = 0;
      var p = g.parentId;
      while (p != null) {
        d++;
        p = diagram.groupById(p)?.parentId;
      }
      return d;
    }

    return List<UmlGroup>.of(diagram.groups)
      ..sort((a, b) => depth(a).compareTo(depth(b)));
  }

  PopupMenuItem<String> _exportMenuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          // Matches the EditorPane header height so the "Diagram" and
          // "PlantUML" labels line up across the split.
          height: 38,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              const Text(
                'Diagram',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SmallDropdown(
                          items: _umlCanvasStyles,
                          initialValue: bgStyle,
                          onChanged: onBgStyle,
                        ),
                        const SizedBox(width: 6),
                        SmallDropdown(
                          items: _umlNodeSkins,
                          initialValue: nodeSkin,
                          onChanged: onNodeSkin,
                        ),
                        const SizedBox(width: 6),
                        ToolButton(
                          label: 'Tidy',
                          icon: Icons.grid_view,
                          onPressed: onTidy,
                        ),
                        const SizedBox(width: 6),
                        ToolButton(
                          label: 'Snap',
                          icon: snapToGrid ? Icons.grid_on : Icons.grid_off,
                          onPressed: onToggleSnap,
                        ),
                        const SizedBox(width: 6),
                        ToolIconButton(
                          icon: Icons.zoom_out,
                          tooltip: 'Zoom out',
                          onPressed: onZoomOut,
                        ),
                        ToolIconButton(
                          icon: Icons.zoom_in,
                          tooltip: 'Zoom in',
                          onPressed: onZoomIn,
                        ),
                        ToolButton(
                          label: 'Fit',
                          icon: Icons.fit_screen,
                          onPressed: onFit,
                        ),
                        const SizedBox(width: 6),
                        PopupMenuButton<String>(
                          tooltip: 'Save / export',
                          position: PopupMenuPosition.under,
                          color: appColors.panelElevated,
                          onSelected: (value) => switch (value) {
                            'save' => onSavePuml(),
                            'png' => onExportPng(),
                            'pdf' => onExportPdf(),
                            'print' => onPrint(),
                            _ => null,
                          },
                          itemBuilder: (_) => [
                            _exportMenuItem(
                              'save',
                              Icons.save_outlined,
                              'Save .puml',
                            ),
                            _exportMenuItem(
                              'png',
                              Icons.image_outlined,
                              'Export PNG…',
                            ),
                            _exportMenuItem(
                              'pdf',
                              Icons.picture_as_pdf_outlined,
                              'Export PDF…',
                            ),
                            _exportMenuItem(
                              'print',
                              Icons.print_outlined,
                              'Print…  ⌘P',
                            ),
                          ],
                          child: AbsorbPointer(
                            child: ToolButton(
                              label: 'Export',
                              icon: Icons.ios_share,
                              onPressed: () {},
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: FileDropTargetRegion(
            targetId: dropTargetId,
            onDropped: onDropFile,
            child: Container(
              decoration: BoxDecoration(
                color: _umlCanvasBackground(bgStyle, appColors),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: appColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: FocusableActionDetector(
                focusNode: focusNode,
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.delete): _DeleteIntent(),
                  SingleActivator(LogicalKeyboardKey.backspace):
                      _DeleteIntent(),
                  SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                      _SavePumlIntent(),
                  SingleActivator(LogicalKeyboardKey.keyP, meta: true):
                      _PrintDiagramIntent(),
                },
                actions: {
                  _DeleteIntent: CallbackAction<_DeleteIntent>(
                    onInvoke: (_) {
                      onDeleteSelected();
                      return null;
                    },
                  ),
                  _SavePumlIntent: CallbackAction<_SavePumlIntent>(
                    onInvoke: (_) {
                      onSavePuml();
                      return null;
                    },
                  ),
                  _PrintDiagramIntent: CallbackAction<_PrintDiagramIntent>(
                    onInvoke: (_) {
                      onPrint();
                      return null;
                    },
                  ),
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    onViewport(constraints.biggest);
                    final extent = _canvasExtent(constraints.biggest);
                    return Listener(
                      // Mouse wheel / two-finger scroll zooms toward the cursor.
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          onZoom(
                            exp(-event.scrollDelta.dy * 0.006),
                            event.localPosition,
                          );
                        }
                      },
                      // Trackpad pinch / two-finger pan (macOS delivers these as
                      // pan-zoom gestures, not scroll signals).
                      onPointerPanZoomStart: (_) => onScaleStart(),
                      onPointerPanZoomUpdate: (event) => onScaleUpdate(
                        event.scale,
                        event.localPosition,
                        event.panDelta,
                      ),
                      child: Stack(
                        children: [
                          // Background: empty-space drag pans the canvas; tap clears
                          // the selection.
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onSelect(null),
                              onPanUpdate: (d) => onPan(d.delta),
                              onSecondaryTapDown: (d) => onCanvasMenu(
                                d.globalPosition,
                                d.localPosition,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          if (diagram.types.isEmpty && diagram.groups.isEmpty)
                            Center(
                              child: Text(
                                'Nothing to show yet.\nDrop a .puml file, type PlantUML, '
                                'or add a class.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: appColors.mutedText,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          // Positioned(left:0,top:0) gives the content unbounded
                          // constraints so the SizedBox keeps its FULL extent
                          // (not clamped to the viewport) — otherwise content below
                          // the viewport is painted but not hit-testable.
                          Positioned(
                            left: 0,
                            top: 0,
                            child: Transform.translate(
                              offset: pan,
                              child: Transform.scale(
                                scale: scale,
                                alignment: Alignment.topLeft,
                                child: RepaintBoundary(
                                  key: captureKey,
                                  child: SizedBox(
                                    width: extent.width,
                                    height: extent.height,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        // Solid background so an exported PNG/PDF
                                        // matches the canvas instead of being
                                        // transparent (invisible on-screen behind
                                        // the live content).
                                        Positioned.fill(
                                          child: ColoredBox(
                                            color: _umlCanvasBackground(
                                              bgStyle,
                                              appColors,
                                            ),
                                          ),
                                        ),
                                        // Alignment grid (behind everything) when
                                        // snap-to-grid is on.
                                        if (snapToGrid)
                                          Positioned.fill(
                                            child: IgnorePointer(
                                              child: CustomPaint(
                                                painter: _GridPainter(
                                                  step: gridStep,
                                                  color: appColors.border,
                                                ),
                                              ),
                                            ),
                                          ),
                                        // Group containers (parents first, behind nodes).
                                        for (final group in _groupsByDepth)
                                          Positioned(
                                            left: group.x,
                                            top: group.y,
                                            child: _UmlGroupBox(
                                              group: group,
                                              selected:
                                                  group.id == selectedGroup,
                                              stereo: _stereotypeColors(
                                                diagram,
                                                group.stereotype,
                                                appColors,
                                                nodeSkin,
                                                identity: group.id,
                                              ),
                                              onSelect: () =>
                                                  onSelectGroup(group.id),
                                              onDrag: (delta) =>
                                                  onGroupDrag(group, delta),
                                              onDragEnd: onGroupDragEnd,
                                              onPan: onPan,
                                              onContextMenu: (pos) =>
                                                  onGroupMenu(group.id, pos),
                                            ),
                                          ),
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _UmlDiagramPainter(
                                                diagram: diagram,
                                                colors: appColors,
                                              ),
                                            ),
                                          ),
                                        ),
                                        for (final type in diagram.types)
                                          Positioned(
                                            // Selected boxes reserve a handle margin; shift
                                            // back so the box stays put visually.
                                            left:
                                                type.x -
                                                (type.name == selected
                                                    ? _umlHandleInset
                                                    : 0),
                                            top:
                                                type.y -
                                                (type.name == selected
                                                    ? _umlHandleInset
                                                    : 0),
                                            child: _UmlTypeBox(
                                              type: type,
                                              selected: type.name == selected,
                                              sketch: bgStyle == 'Sketch',
                                              stereo: _stereotypeColors(
                                                diagram,
                                                type.stereotype,
                                                appColors,
                                                nodeSkin,
                                                identity: type.name,
                                              ),
                                              editing: type.name == editing,
                                              onSelect: () =>
                                                  onSelect(type.name),
                                              onDrag: (delta) =>
                                                  onBoxDrag(type, delta),
                                              onDragEnd: onBoxDragEnd,
                                              onPan: onPan,
                                              onRename: (text) =>
                                                  onRename(type.name, text),
                                              onEndEdit: onEndEdit,
                                              onContextMenu: (pos) =>
                                                  onNodeMenu(type.name, pos),
                                              onResize: (handle, delta) =>
                                                  onResize(type, handle, delta),
                                              onResizeEnd: onResizeEnd,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Fixed overlays (unaffected by pan/zoom).
                          if (diagram.heading != null)
                            Positioned(
                              top: 8,
                              left: 12,
                              right: 12,
                              child: IgnorePointer(
                                child: Center(
                                  child: _UmlTitleChip(text: diagram.heading!),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: IgnorePointer(
                              child: _UmlZoomBadge(scale: scale),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _SavePumlIntent extends Intent {
  const _SavePumlIntent();
}

class _PrintDiagramIntent extends Intent {
  const _PrintDiagramIntent();
}

class _UmlTypeBox extends StatelessWidget {
  const _UmlTypeBox({
    required this.type,
    required this.selected,
    required this.sketch,
    required this.stereo,
    required this.editing,
    required this.onSelect,
    required this.onDrag,
    required this.onDragEnd,
    required this.onPan,
    required this.onRename,
    required this.onEndEdit,
    required this.onContextMenu,
    required this.onResize,
    required this.onResizeEnd,
  });

  final UmlType type;
  final bool selected;
  final bool sketch;
  final ({Color background, Color border, Color font}) stereo;
  final bool editing;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<Offset> onPan; // canvas pan when the box isn't selected
  final ValueChanged<String> onRename;
  final VoidCallback onEndEdit;
  final ValueChanged<Offset> onContextMenu;
  final void Function(String handle, Offset delta) onResize;
  final VoidCallback onResizeEnd;

  String? get _stereotypeLabel {
    if (type.isNote) return null;
    if (type.kind == UmlTypeKind.node) {
      return type.stereotype != null ? '«${type.stereotype}»' : null;
    }
    return switch (type.kind) {
      UmlTypeKind.interfaceType => '«interface»',
      UmlTypeKind.enumType => '«enumeration»',
      UmlTypeKind.abstractType => '«abstract»',
      _ => type.stereotype != null ? '«${type.stereotype}»' : null,
    };
  }

  // Effective colors: a user-set background (right-click) overrides the
  // stereotype/theme colors, with a derived border and contrasting text.
  ({Color background, Color border, Color font}) _colors(AppColors appColors) {
    final custom = _parseUmlColor(type.color);
    if (custom == null) return stereo;
    return (
      background: custom,
      border: Color.alphaBlend(const Color(0x40000000), custom),
      font: custom.computeLuminance() > 0.5
          ? const Color(0xFF1F2328)
          : Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final size = _umlBoxSize(type);

    // Nodes are fixed-size and centered; class boxes size to their content
    // height so the border inset never clips the last member row.
    Widget body = type.isNote
        ? SizedBox(
            width: size.width,
            height: size.height,
            child: _buildNote(appColors),
          )
        : type.kind == UmlTypeKind.node
        ? SizedBox(
            width: size.width,
            height: size.height,
            child: _buildNode(appColors),
          )
        : SizedBox(width: size.width, child: _buildClass(appColors));

    // Sketch theme: overlay a hand-drawn rough border (the crisp box border is
    // suppressed in the builders). Notes keep their folded-corner shape.
    if (sketch && !type.isNote) {
      body = CustomPaint(
        foregroundPainter: _SketchBorderPainter(
          color: selected ? appColors.accent : appColors.mutedText,
          seed: type.name.hashCode,
          strokeWidth: selected ? 2.2 : 1.6,
        ),
        child: body,
      );
    }

    final interactive = MouseRegion(
      cursor: editing ? SystemMouseCursors.text : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSelect,
        // Note: no onDoubleTap — it would delay every single-tap selection by
        // the double-tap timeout. Rename is via right-click → Rename instead.
        onSecondaryTapDown: (d) => onContextMenu(d.globalPosition),
        // Tap selects. A drag only MOVES the box if it's already selected;
        // dragging an unselected box pans the canvas instead (and leaves it
        // unselected) — so panning never grabs whatever happened to be under
        // the cursor. Disabled entirely while the inline name editor is open.
        onPanStart: editing ? null : (_) {},
        onPanUpdate: editing
            ? null
            : (d) => selected ? onDrag(d.delta) : onPan(d.delta),
        onPanEnd: editing
            ? null
            : (_) {
                if (selected) onDragEnd();
              },
        child: body,
      ),
    );

    if (!selected || editing) return interactive;

    // Selected: pad by [_umlHandleInset] so the edge/corner handles sit fully
    // inside the hit-testable area (the canvas offsets placement by the same
    // inset so the box stays put visually). The body is the Stack's sizing
    // child and the handles position themselves against its *actual* rendered
    // bounds — so they hug the box exactly even when the box's content height
    // differs from the size estimate (and they scale with zoom since the whole
    // canvas is transformed together).
    const m = _umlHandleInset;
    return Padding(
      padding: const EdgeInsets.all(m),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          interactive,
          for (final handle in _UmlResizeHandle.all)
            _UmlResizeHandle(
              handle: handle,
              color: appColors.accent,
              onResize: (delta) => onResize(handle, delta),
              onResizeEnd: onResizeEnd,
            ),
        ],
      ),
    );
  }

  // Inline name editor shown over the box while renaming.
  Widget _nameEditor(AppColors appColors, {required Color color}) {
    return _UmlNameEditor(
      initial: type.label,
      color: color,
      onSubmit: onRename,
      onCancel: onEndEdit,
    );
  }

  Widget _buildNode(AppColors appColors) {
    final stereotypeLabel = _stereotypeLabel;
    final c = _colors(appColors);
    return Container(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: sketch
              ? Colors.transparent
              : (selected ? appColors.accent : c.border),
          width: selected ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: appColors.shadow,
            blurRadius: selected ? 10 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Element glyph in the top-right corner, ArchiMate-style: a vendored
          // ArchiMate sprite when the stereotype names one, else a Material
          // glyph approximating the element keyword.
          Positioned(
            top: 5,
            right: 6,
            child: _NodeGlyph(type: type, color: c.font.withAlpha(160)),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: editing
                  ? Center(child: _nameEditor(appColors, color: c.font))
                  // Scale the label down if it would otherwise exceed the fixed
                  // node height, so content never overflows the draggable box.
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: _umlBoxSize(type).width - 20,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (stereotypeLabel != null)
                              Text(
                                stereotypeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: c.font.withAlpha(190),
                                ),
                              ),
                            Text(
                              _umlDisplayText(type.label),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: c.font,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNote(AppColors appColors) {
    final custom = _parseUmlColor(type.color);
    final bg = custom ?? const Color(0xFFFFF6C8); // sticky-note yellow
    final border = selected
        ? appColors.accent
        : Color.alphaBlend(const Color(0x40000000), bg);
    final font = bg.computeLuminance() > 0.5
        ? const Color(0xFF3A3320)
        : Colors.white;
    return CustomPaint(
      painter: _NoteShapePainter(
        fill: bg,
        border: border,
        strokeWidth: selected ? 2 : 1.2,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PlantUmlService.notePadL,
          PlantUmlService.notePadV,
          PlantUmlService.notePadR,
          PlantUmlService.notePadV,
        ),
        child: editing
            ? Center(child: _nameEditor(appColors, color: font))
            : Align(
                alignment: Alignment.topLeft,
                child: _NoteBody(
                  body: _umlDisplayText(type.label),
                  color: font,
                ),
              ),
      ),
    );
  }

  Widget _buildClass(AppColors appColors) {
    final stereotypeLabel = _stereotypeLabel;
    final isEnum = type.kind == UmlTypeKind.enumType;
    final fields = isEnum ? type.members : type.fields;
    final methods = isEnum ? const <UmlMember>[] : type.methods;
    const memberStyle = TextStyle(fontFamily: 'Menlo', fontSize: 11);

    // Base colors come from the node skin / stereotype / right-click override
    // (via [_colors]); when that resolves to the plain panel (the `Auto` skin
    // with no stereotype) we keep the exact default header/text for an
    // unchanged look. Any palette skin or custom color tints the whole box.
    final c = _colors(appColors);
    final tinted = c.background != appColors.panel;
    final bodyColor = c.background;
    final headerColor = tinted
        ? Color.alphaBlend(const Color(0x18000000), c.background)
        : appColors.panelHeader;
    final textColor = c.font;

    Widget memberRow(UmlMember m) => SizedBox(
      height: 19,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          isEnum ? m.text : '${m.visibility.symbol}${m.text}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: memberStyle.copyWith(color: textColor),
        ),
      ),
    );

    Widget section(List<UmlMember> members, {bool topBorder = false}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: topBorder
              ? Border(top: BorderSide(color: appColors.border))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: members.map(memberRow).toList(),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bodyColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: sketch
              ? Colors.transparent
              : (selected
                    ? appColors.accent
                    : (tinted ? c.border : appColors.border)),
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: appColors.shadow,
            blurRadius: selected ? 10 : 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: headerColor,
              border: Border(bottom: BorderSide(color: appColors.border)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (stereotypeLabel != null)
                  Text(
                    stereotypeLabel,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: tinted
                          ? textColor.withAlpha(180)
                          : appColors.mutedText,
                    ),
                  ),
                if (editing)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _nameEditor(appColors, color: textColor),
                  )
                else
                  Text(
                    _umlDisplayText(type.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      fontStyle: type.kind == UmlTypeKind.abstractType
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: textColor,
                    ),
                  ),
              ],
            ),
          ),
          if (fields.isNotEmpty) section(fields),
          if (methods.isNotEmpty)
            section(methods, topBorder: fields.isNotEmpty),
        ],
      ),
    );
  }
}

/// A tappable color circle used in the background-color picker dialog.
class _ColorSwatchDot extends StatelessWidget {
  const _ColorSwatchDot({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33000000)),
        ),
      ),
    );
  }
}

/// Draws a hand-drawn (wobbly) rectangular border for the Sketch theme.
/// Edges curve via jittered control points seeded per box so they're stable.
class _SketchBorderPainter extends CustomPainter {
  _SketchBorderPainter({
    required this.color,
    required this.seed,
    required this.strokeWidth,
  });

  final Color color;
  final int seed;
  final double strokeWidth;

  double _rand(int i) {
    final v = sin(seed * 12.9898 + i * 78.233) * 43758.5453;
    return v - v.floorToDouble(); // 0..1
  }

  Offset _jit(Offset p, int i, double amp) =>
      Offset(p.dx + (_rand(i) - 0.5) * amp, p.dy + (_rand(i + 99) - 0.5) * amp);

  void _edge(Canvas canvas, Offset a, Offset b, Paint paint, int i) {
    const amp = 2.6;
    final start = _jit(a, i, amp);
    final end = _jit(b, i + 7, amp);
    final mid = Offset.lerp(a, b, 0.5)!;
    final ctrl = _jit(mid, i + 13, amp * 2.2);
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy),
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final tl = const Offset(0, 0);
    final tr = Offset(size.width, 0);
    final br = Offset(size.width, size.height);
    final bl = Offset(0, size.height);
    _edge(canvas, tl, tr, paint, 1);
    _edge(canvas, tr, br, paint, 2);
    _edge(canvas, br, bl, paint, 3);
    _edge(canvas, bl, tl, paint, 4);
  }

  @override
  bool shouldRepaint(covariant _SketchBorderPainter old) =>
      old.color != color || old.seed != seed || old.strokeWidth != strokeWidth;
}

/// Paints a sticky-note shape (rectangle with a folded top-right corner).
/// Renders a note body as PlantUML creole: pipe tables (with bold `|=`
/// headers), `--` dividers, and `**bold**` text. Column widths size to content,
/// matching `PlantUmlService.noteContentSize` so the note box never clips.
class _NoteBody extends StatelessWidget {
  const _NoteBody({required this.body, required this.color});

  final String body;
  final Color color;

  TextSpan _creole(String text, {required bool bold}) {
    final base = TextStyle(
      fontSize: 12,
      height: 1.25,
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    );
    final parts = text.split('**');
    return TextSpan(
      style: base,
      children: [
        for (var i = 0; i < parts.length; i++)
          if (parts[i].isNotEmpty)
            TextSpan(
              text: parts[i],
              // Odd segments sit between ** markers → bold.
              style: i.isOdd
                  ? base.copyWith(fontWeight: FontWeight.w700)
                  : null,
            ),
      ],
    );
  }

  Widget _table(List<List<UmlNoteCell>> rows) {
    final cols = rows.fold(0, (m, r) => r.length > m ? r.length : m);
    final lineColor = color.withAlpha(95);
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(color: lineColor, width: 1),
      children: [
        for (final row in rows)
          TableRow(
            children: [
              for (var c = 0; c < cols; c++)
                _cell(c < row.length ? row[c] : UmlNoteCell('')),
            ],
          ),
      ],
    );
  }

  Widget _cell(UmlNoteCell cell) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: ColoredBox(
        color: cell.header ? color.withAlpha(22) : const Color(0x00000000),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: RichText(
            text: _creole(cell.text, bold: cell.header),
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = PlantUmlService.parseNoteBody(body);
    final children = <Widget>[];
    for (final block in blocks) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 4));
      switch (block.kind) {
        case UmlNoteBlockKind.text:
          children.add(RichText(text: _creole(block.text, bold: false)));
        case UmlNoteBlockKind.divider:
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Container(height: 1, color: color.withAlpha(70)),
            ),
          );
        case UmlNoteBlockKind.table:
          children.add(_table(block.rows));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// A faint alignment grid drawn behind the diagram when snap-to-grid is on.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.step, required this.color});

  final double step;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withAlpha(40)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.step != step || old.color != color;
}

class _NoteShapePainter extends CustomPainter {
  _NoteShapePainter({
    required this.fill,
    required this.border,
    required this.strokeWidth,
  });

  final Color fill;
  final Color border;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const fold = 14.0;
    final body = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - fold, 0)
      ..lineTo(size.width, fold)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(body, Paint()..color = fill);
    final stroke = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(body, stroke);
    // Folded corner.
    final fold2 = Path()
      ..moveTo(size.width - fold, 0)
      ..lineTo(size.width - fold, fold)
      ..lineTo(size.width, fold);
    canvas.drawPath(fold2, stroke);
  }

  @override
  bool shouldRepaint(covariant _NoteShapePainter old) =>
      old.fill != fill ||
      old.border != border ||
      old.strokeWidth != strokeWidth;
}

/// A draggable resize handle positioned on the edge/corner of a selected box.
class _UmlResizeHandle extends StatelessWidget {
  const _UmlResizeHandle({
    required this.handle,
    required this.color,
    required this.onResize,
    required this.onResizeEnd,
  });

  static const List<String> all = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];

  final String handle;
  final Color color;
  final ValueChanged<Offset> onResize;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) {
    const diameter = 15.0;
    const half = diameter / 2;
    final hasN = handle.contains('n');
    final hasS = handle.contains('s');
    final hasE = handle.contains('e');
    final hasW = handle.contains('w');

    // Positioned against the sibling body (the Stack's sizing child): edges sit
    // half a handle outside the body border; a missing horizontal/vertical edge
    // means the handle spans that axis and centers on it.
    final left = hasW ? -half : (hasE ? null : 0.0);
    final right = hasE ? -half : (hasW ? null : 0.0);
    final top = hasN ? -half : (hasS ? null : 0.0);
    final bottom = hasS ? -half : (hasN ? null : 0.0);

    final SystemMouseCursor cursor;
    if ((hasN && hasW) || (hasS && hasE)) {
      cursor = SystemMouseCursors.resizeUpLeftDownRight;
    } else if ((hasN && hasE) || (hasS && hasW)) {
      cursor = SystemMouseCursors.resizeUpRightDownLeft;
    } else if (hasN || hasS) {
      cursor = SystemMouseCursors.resizeUpDown;
    } else {
      cursor = SystemMouseCursors.resizeLeftRight;
    }

    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: Center(
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onResize(d.delta),
            onPanEnd: (_) => onResizeEnd(),
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Color(0x55000000), blurRadius: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline single-line editor for renaming a box on the canvas. Commits on
/// Enter or tap-outside; cancels on Escape.
class _UmlNameEditor extends StatefulWidget {
  const _UmlNameEditor({
    required this.initial,
    required this.color,
    required this.onSubmit,
    required this.onCancel,
  });

  final String initial;
  final Color color;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_UmlNameEditor> createState() => _UmlNameEditorState();
}

class _UmlNameEditorState extends State<_UmlNameEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focusNode = FocusNode();
  var _committed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    if (_committed) return;
    _committed = true;
    widget.onSubmit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return SizedBox(
      width: 150,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _committed = true;
            widget.onCancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textAlign: TextAlign.center,
          cursorColor: appColors.accent,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: widget.color,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 4,
            ),
            filled: true,
            fillColor: appColors.editorBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: appColors.accent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: appColors.accent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: appColors.accent, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
        ),
      ),
    );
  }
}

/// Translucent container drawn behind nodes for a package or composite element.
/// Only the title bar is interactive (select / drag / context menu); the body
/// is click-through so overlapping containers and the elements inside them stay
/// reachable.
class _UmlGroupBox extends StatelessWidget {
  const _UmlGroupBox({
    required this.group,
    required this.selected,
    required this.stereo,
    required this.onSelect,
    required this.onDrag,
    required this.onDragEnd,
    required this.onPan,
    required this.onContextMenu,
  });

  final UmlGroup group;
  final bool selected;
  final ({Color background, Color border, Color font}) stereo;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<Offset> onPan; // canvas pan when the group isn't selected
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final hasStereotype = group.stereotype != null;
    // A user-set background (right-click → Background color) wins over the
    // stereotype/theme color. Group fills stay translucent so overlapping
    // members below remain visible.
    final custom = _parseUmlColor(group.color);
    final border = selected
        ? appColors.accent
        : custom != null
        ? Color.alphaBlend(const Color(0x55000000), custom)
        : hasStereotype
        ? stereo.border
        : appColors.border;
    final fill = custom != null
        ? custom.withAlpha(48)
        : hasStereotype
        ? stereo.background.withAlpha(36)
        : appColors.panelElevated.withAlpha(60);
    return SizedBox(
      width: group.w,
      height: group.h,
      child: Stack(
        children: [
          // Body: visual only. It must NOT absorb pointer events — group boxes
          // routinely overlap (a container's box is the bounding box of its
          // scattered members), so an opaque body would block selecting any
          // element beneath it. Clicks fall through to nested groups, nodes, or
          // the canvas.
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: border.withAlpha(selected ? 230 : 180),
                    width: selected ? 1.6 : 1,
                  ),
                ),
              ),
            ),
          ),
          // Title bar is the only interactive surface: select, drag (when
          // selected), or right-click the container by its label.
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 24,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSelect,
                onSecondaryTapDown: (d) => onContextMenu(d.globalPosition),
                onPanStart: (_) {},
                onPanUpdate: (d) => selected ? onDrag(d.delta) : onPan(d.delta),
                onPanEnd: (_) {
                  if (selected) onDragEnd();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      group.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: selected
                            ? appColors.accent
                            : appColors.mutedText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diagram title pinned at the top of the canvas, like PlantUML's `title`.
class _UmlTitleChip extends StatelessWidget {
  const _UmlTitleChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appColors.panelElevated.withAlpha(224),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: appColors.editorText,
          ),
        ),
      ),
    );
  }
}

/// Small zoom-percentage readout in the canvas corner.
class _UmlZoomBadge extends StatelessWidget {
  const _UmlZoomBadge({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appColors.panelElevated.withAlpha(208),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: appColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          '${(scale * 100).round()}%',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: appColors.mutedText,
          ),
        ),
      ),
    );
  }
}

class _UmlDiagramPainter extends CustomPainter {
  _UmlDiagramPainter({required this.diagram, required this.colors});

  final UmlDiagram diagram;
  final AppColors colors;

  Rect _rectFor(UmlType type) {
    final size = _umlBoxSize(type);
    return Rect.fromLTWH(type.x, type.y, size.width, size.height);
  }

  // Point on [rect]'s border along the line from its center toward [target].
  Offset _edgePoint(Rect rect, Offset target) {
    final center = rect.center;
    final dx = target.dx - center.dx;
    final dy = target.dy - center.dy;
    if (dx == 0 && dy == 0) return center;
    final scaleX = dx != 0 ? (rect.width / 2) / dx.abs() : double.infinity;
    final scaleY = dy != 0 ? (rect.height / 2) / dy.abs() : double.infinity;
    final scale = min(scaleX, scaleY);
    return Offset(center.dx + dx * scale, center.dy + dy * scale);
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final start = a + dir * drawn;
      final end = a + dir * min(drawn + dash, total);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset tip,
    Offset from,
    Paint stroke, {
    bool triangle = false,
  }) {
    final angle = atan2(tip.dy - from.dy, tip.dx - from.dx);
    const len = 12.0;
    const spread = 0.45;
    final b1 = tip - Offset(cos(angle - spread), sin(angle - spread)) * len;
    final b2 = tip - Offset(cos(angle + spread), sin(angle + spread)) * len;
    if (triangle) {
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(b1.dx, b1.dy)
        ..lineTo(b2.dx, b2.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = colors.canvas);
      canvas.drawPath(path, stroke);
    } else {
      canvas.drawLine(tip, b1, stroke);
      canvas.drawLine(tip, b2, stroke);
    }
  }

  void _drawDiamond(
    Canvas canvas,
    Offset at,
    Offset toward,
    Paint stroke, {
    required bool filled,
  }) {
    final angle = atan2(toward.dy - at.dy, toward.dx - at.dx);
    final dir = Offset(cos(angle), sin(angle));
    final perp = Offset(-sin(angle), cos(angle));
    const len = 16.0;
    const halfWidth = 7.0;
    final p0 = at;
    final p1 = at + dir * (len / 2) + perp * halfWidth;
    final p2 = at + dir * len;
    final p3 = at + dir * (len / 2) - perp * halfWidth;
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = filled ? colors.editorText : colors.canvas,
    );
    canvas.drawPath(path, stroke);
  }

  void _drawLabel(Canvas canvas, Offset at, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colors.editorText, fontSize: 10.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: at,
      width: painter.width + 8,
      height: painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = colors.canvas.withAlpha(232),
    );
    painter.paint(
      canvas,
      Offset(at.dx - painter.width / 2, at.dy - painter.height / 2),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = colors.mutedText
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (final relation in diagram.relations) {
      final from = diagram.typeByName(relation.from);
      final to = diagram.typeByName(relation.to);
      if (from == null || to == null) continue;
      final fromRect = _rectFor(from);
      final toRect = _rectFor(to);
      final p1 = _edgePoint(fromRect, toRect.center);
      final p2 = _edgePoint(toRect, fromRect.center);

      final dotted =
          relation.kind == UmlRelationKind.realization ||
          relation.kind == UmlRelationKind.dependency;
      if (dotted) {
        _drawDashedLine(canvas, p1, p2, stroke);
      } else {
        canvas.drawLine(p1, p2, stroke);
      }

      switch (relation.kind) {
        case UmlRelationKind.inheritance:
        case UmlRelationKind.realization:
          _drawArrowHead(canvas, p2, p1, stroke, triangle: true);
          break;
        case UmlRelationKind.directedAssociation:
        case UmlRelationKind.dependency:
          _drawArrowHead(canvas, p2, p1, stroke);
          break;
        case UmlRelationKind.composition:
          _drawDiamond(canvas, p1, p2, stroke, filled: true);
          break;
        case UmlRelationKind.aggregation:
          _drawDiamond(canvas, p1, p2, stroke, filled: false);
          break;
        case UmlRelationKind.association:
          break;
      }

      final label = relation.label;
      if (label != null && label.isNotEmpty) {
        _drawLabel(canvas, Offset.lerp(p1, p2, 0.5)!, label);
      }
    }

    // Anchor lines tying `note <dir> of X` notes to their target — a light
    // dashed connector with no arrowhead, matching PlantUML's note links.
    final noteStroke = Paint()
      ..color = colors.mutedText.withAlpha(150)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    for (final note in diagram.types) {
      if (!note.isNote || note.attachedTo == null) continue;
      final target = diagram.typeByName(note.attachedTo!);
      if (target == null) continue;
      final noteRect = _rectFor(note);
      final targetRect = _rectFor(target);
      _drawDashedLine(
        canvas,
        _edgePoint(noteRect, targetRect.center),
        _edgePoint(targetRect, noteRect.center),
        noteStroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UmlDiagramPainter oldDelegate) => true;
}
