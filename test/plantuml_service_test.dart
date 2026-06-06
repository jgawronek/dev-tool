import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/plantuml_service.dart';

const _sample = '''
@startuml
class User {
  +name: String
  -password: String
  +login(pw: String): bool
}
interface Repository {
  +save(item)
}
abstract class Base
enum Role {
  ADMIN
  MEMBER
}
User --> Order : places
Admin --|> User
User ..|> Repository
Order *-- LineItem
Cart o-- Product
User ..> Logger
@enduml
''';

void main() {
  group('PlantUmlService.parse', () {
    final diagram = PlantUmlService.parse(_sample);

    test('parses declared and stub types', () {
      // 4 declared + Order, Admin, LineItem, Cart, Product, Logger stubs.
      expect(diagram.types.map((t) => t.name), containsAll(<String>[
        'User',
        'Repository',
        'Base',
        'Role',
        'Order',
        'Admin',
        'LineItem',
        'Cart',
        'Product',
        'Logger',
      ]));
    });

    test('classifies type kinds', () {
      expect(diagram.typeByName('User')!.kind, UmlTypeKind.classType);
      expect(diagram.typeByName('Repository')!.kind, UmlTypeKind.interfaceType);
      expect(diagram.typeByName('Base')!.kind, UmlTypeKind.abstractType);
      expect(diagram.typeByName('Role')!.kind, UmlTypeKind.enumType);
    });

    test('splits members into fields and methods by visibility/signature', () {
      final user = diagram.typeByName('User')!;
      expect(user.fields.map((m) => m.text), ['name: String', 'password: String']);
      expect(user.methods.map((m) => m.text), ['login(pw: String): bool']);
      expect(user.fields.first.visibility, UmlVisibility.public);
      expect(
        user.members.firstWhere((m) => m.text.startsWith('password')).visibility,
        UmlVisibility.private,
      );
    });

    test('classifies relation kinds and orients heads from -> to', () {
      UmlRelation rel(String from, String to) => diagram.relations
          .firstWhere((r) => r.from == from && r.to == to);

      expect(rel('User', 'Order').kind, UmlRelationKind.directedAssociation);
      expect(rel('User', 'Order').label, 'places');
      expect(rel('Admin', 'User').kind, UmlRelationKind.inheritance);
      expect(rel('User', 'Repository').kind, UmlRelationKind.realization);
      expect(rel('Order', 'LineItem').kind, UmlRelationKind.composition);
      expect(rel('Cart', 'Product').kind, UmlRelationKind.aggregation);
      expect(rel('User', 'Logger').kind, UmlRelationKind.dependency);
    });

    test('auto-lays out types onto a grid when no positions are given', () {
      // First type anchored, none overlapping at the origin.
      final positions = diagram.types.map((t) => '${t.x},${t.y}').toSet();
      expect(positions.length, diagram.types.length);
    });
  });

  group('round-trip', () {
    test('parse → generate → parse preserves type and relation counts', () {
      final first = PlantUmlService.parse(_sample);
      final regenerated = PlantUmlService.generate(first);
      final second = PlantUmlService.parse(regenerated);

      expect(second.types.length, first.types.length);
      expect(second.relations.length, first.relations.length);
    });

    test('box positions survive a text round-trip via @pos comments', () {
      final first = PlantUmlService.parse(_sample);
      final user = first.typeByName('User')!..x = 123..y = 456;

      final regenerated = PlantUmlService.generate(first);
      expect(regenerated, contains("'@pos User 123 456"));

      final second = PlantUmlService.parse(regenerated);
      expect(second.typeByName('User')!.x, user.x);
      expect(second.typeByName('User')!.y, user.y);
    });

    test('previous diagram positions are reused for surviving types', () {
      final previous = PlantUmlService.parse(_sample);
      previous.typeByName('User')!
        ..x = 99
        ..y = 88;

      // Re-parse a positionless source, carrying positions forward.
      const noPos = 'class User\nclass Order\nUser --> Order';
      final next = PlantUmlService.parse(noPos, previous: previous);
      expect(next.typeByName('User')!.x, 99);
      expect(next.typeByName('User')!.y, 88);
    });
  });

  group('generate', () {
    test('emits the correct PlantUML arrow for each relation kind', () {
      final diagram = UmlDiagram(
        types: [UmlType(name: 'A'), UmlType(name: 'B')],
        relations: [
          UmlRelation(from: 'A', to: 'B', kind: UmlRelationKind.inheritance),
        ],
      );
      expect(PlantUmlService.generate(diagram), contains('A --|> B'));
    });

    test('quotes type names that need it', () {
      final diagram = UmlDiagram(types: [UmlType(name: 'My Class')]);
      expect(PlantUmlService.generate(diagram), contains('class "My Class"'));
    });
  });

  group('architecture / component diagrams', () {
    const archSource = '''
@startuml platform_view
skinparam shadowing false
skinparam rectangle {
  BackgroundColor<<business>>    #FAEEDA
  BorderColor<<business>>        #BA7517
}

package "Business" {
  rectangle "Marketer" as marketer <<business>>
  package "Run campaign" {
    rectangle "Create"   as p1 <<business>>
    rectangle "Publish"  as p2 <<business>>
  }
}
package "Application" {
  rectangle "SaaS platform" as saas {
    rectangle "Web client"  as client <<application>>
    rectangle "API gateway" as api    <<application>>
  }
}

p1 --> p2
marketer <-- client : uses
api <-- p1
@enduml''';

    test('parses rectangle elements with label, alias and stereotype', () {
      final d = PlantUmlService.parse(archSource);
      final marketer = d.typeByName('marketer')!;
      expect(marketer.kind, UmlTypeKind.node);
      expect(marketer.label, 'Marketer');
      expect(marketer.nodeKeyword, 'rectangle');
      expect(marketer.stereotype, 'business');
      // No alias-named stubs left over.
      expect(d.types.where((t) => t.label == t.name && t.kind == UmlTypeKind.node),
          isEmpty);
    });

    test('builds nested package + composite-element groups', () {
      final d = PlantUmlService.parse(archSource);
      expect(d.groupById('Business')!.parentId, isNull);
      expect(d.groupById('Run campaign')!.parentId, 'Business');
      expect(d.groupById('saas')!.keyword, 'rectangle');
      expect(d.typeByName('p1')!.groupId, 'Run campaign');
      expect(d.typeByName('client')!.groupId, 'saas');
    });

    test('captures stereotype colors from the skinparam block', () {
      final d = PlantUmlService.parse(archSource);
      expect(d.stereotypeStyles['business']!.background, '#FAEEDA');
      expect(d.stereotypeStyles['business']!.border, '#BA7517');
    });

    test('orients <-- relations so the head points from -> to', () {
      final d = PlantUmlService.parse(archSource);
      final uses = d.relations.firstWhere((r) => r.label == 'uses');
      expect(uses.from, 'client');
      expect(uses.to, 'marketer');
    });

    test('round-trip preserves structure, style and stereotype colors', () {
      final first = PlantUmlService.parse(archSource);
      final regenerated = PlantUmlService.generate(first);
      final second = PlantUmlService.parse(regenerated);

      expect(second.types.length, first.types.length);
      expect(second.groups.length, first.groups.length);
      expect(second.relations.length, first.relations.length);
      expect(second.styleLines, first.styleLines);
      expect(second.stereotypeStyles['business']!.background, '#FAEEDA');
      expect(regenerated, contains('rectangle "Marketer" as marketer <<business>>'));
      expect(regenerated, contains('package "Business" {'));
    });

    test('auto-layout keeps nodes inside their groups and groups disjoint', () {
      final d = PlantUmlService.parse(archSource);

      // Every node sits within its group's box.
      for (final t in d.types.where((t) => t.groupId != null)) {
        final g = d.groupById(t.groupId!)!;
        expect(t.x >= g.x, isTrue, reason: '${t.name} left of ${g.id}');
        expect(t.y >= g.y, isTrue, reason: '${t.name} above ${g.id}');
        expect(t.x + PlantUmlService.nodeWidth <= g.x + g.w, isTrue,
            reason: '${t.name} right of ${g.id}');
        expect(t.y + PlantUmlService.nodeHeight <= g.y + g.h, isTrue,
            reason: '${t.name} below ${g.id}');
      }

      // Top-level packages don't overlap.
      final roots = d.groups.where((g) => g.parentId == null).toList();
      for (var i = 0; i < roots.length; i++) {
        for (var j = i + 1; j < roots.length; j++) {
          final a = roots[i];
          final b = roots[j];
          final overlap = a.x < b.x + b.w &&
              a.x + a.w > b.x &&
              a.y < b.y + b.h &&
              a.y + a.h > b.y;
          expect(overlap, isFalse, reason: '${a.id} overlaps ${b.id}');
        }
      }
    });
  });

  group('autoLayout (the canvas "Tidy" action)', () {
    // An architecture diagram whose components each carry a large attached
    // note — the case the old layout collided badly on. Mirrors the shape of a
    // real API-endpoint diagram.
    const noteHeavy = '''
@startuml
package "Auth" as PAuth {
  component "Auth" as RAuth
  note bottom of RAuth
    |= verb |= path |
    | POST | /token |
    | GET | /ttl |
    --
    issue body { account_id } -> bearer
  end note
}
package "Requests" as PRequests {
  component "Trending" as RTrending
  note bottom of RTrending
    |= verb |= path |
    | POST | / |
    | GET | /{token} |
    --
    **POST body** platform, hashtag, duration
  end note
  component "Likes" as RLikes
  note bottom of RLikes
    |= verb |= path |
    | POST | / |
    --
    **POST body** platform, post_url, like_count
  end note
}
database "SQLite" as Sqlite
actor "Operator" as Operator
PAuth --> Sqlite
@enduml''';

    // Two boxes overlap when their rectangles intersect (notes included).
    bool overlaps(UmlType a, UmlType b) {
      double w(UmlType t) => t.w ?? PlantUmlService.nodeWidth;
      double h(UmlType t) => t.h ?? PlantUmlService.nodeHeight;
      return a.x < b.x + w(b) &&
          a.x + w(a) > b.x &&
          a.y < b.y + h(b) &&
          a.y + h(a) > b.y;
    }

    int overlapCount(UmlDiagram d) {
      var n = 0;
      for (var i = 0; i < d.types.length; i++) {
        for (var j = i + 1; j < d.types.length; j++) {
          if (overlaps(d.types[i], d.types[j])) n++;
        }
      }
      return n;
    }

    test('lays note-heavy components out with zero box overlaps', () {
      final d = PlantUmlService.parse(noteHeavy);
      // Parse runs the same engine; assert it is clean out of the box.
      expect(overlapCount(d), 0, reason: 'parse-time layout should not overlap');

      // Scramble every position, then Tidy must restore an overlap-free layout.
      for (final t in d.types) {
        t
          ..x = 0
          ..y = 0;
      }
      PlantUmlService.autoLayout(d);
      expect(overlapCount(d), 0, reason: 'Tidy should not overlap');
    });

    test('seats each attached note directly below its host, inside reach', () {
      final d = PlantUmlService.parse(noteHeavy);
      PlantUmlService.autoLayout(d);

      for (final note in d.types.where((t) => t.isNote)) {
        final host = d.typeByName(note.attachedTo!)!;
        final hostBottom = host.y + (host.h ?? PlantUmlService.nodeHeight);
        // Note sits below its host and is horizontally centered on it.
        expect(note.y, greaterThanOrEqualTo(hostBottom),
            reason: '${note.name} should be below ${host.name}');
        final hostCenter = host.x + (host.w ?? PlantUmlService.nodeWidth) / 2;
        final noteCenter = note.x + (note.w ?? PlantUmlService.nodeWidth) / 2;
        expect((hostCenter - noteCenter).abs(), lessThan(1.0),
            reason: '${note.name} should be centered under ${host.name}');
      }
    });

    // Regression: class boxes size to their member rows, not the compact node
    // box. The grid must reserve that real height (tall User/Role boxes) and a
    // wide gap (so relationship arrows have a visible run) — otherwise boxes
    // pile on top of each other and arrows collapse to nothing.
    const classDiagram = '''
@startuml
class User {
  +id: int
  +name: String
  -password: String
}
interface Repository {
  +save(item)
  +findById(id): Item
}
enum Role {
  ADMIN
  MEMBER
  GUEST
}
class Order {
  +total: double
}
User --> Order
User ..|> Repository
@enduml''';

    test('class boxes use content height and never overlap after Tidy', () {
      final d = PlantUmlService.parse(classDiagram);
      PlantUmlService.autoLayout(d);

      double w(UmlType t) => PlantUmlService.effectiveWidth(t);
      double h(UmlType t) => PlantUmlService.effectiveHeight(t);

      // Tall boxes are taller than the compact node box.
      expect(h(d.typeByName('User')!),
          greaterThan(PlantUmlService.nodeHeight),
          reason: 'a 3-member class should be taller than a node box');

      for (var i = 0; i < d.types.length; i++) {
        for (var j = i + 1; j < d.types.length; j++) {
          final a = d.types[i], b = d.types[j];
          final hit = a.x < b.x + w(b) &&
              a.x + w(a) > b.x &&
              a.y < b.y + h(b) &&
              a.y + h(a) > b.y;
          expect(hit, isFalse, reason: '${a.name} overlaps ${b.name}');
        }
      }
    });

    test('leaves a visible horizontal gap between related boxes for arrows', () {
      final d = PlantUmlService.parse(classDiagram);
      PlantUmlService.autoLayout(d);
      // Find any two horizontally-adjacent boxes on the same row and confirm
      // the gap between them is wide enough to draw an arrow into.
      final byRow = <double, List<UmlType>>{};
      for (final t in d.types) {
        byRow.putIfAbsent(t.y, () => []).add(t);
      }
      var sawAdjacentPair = false;
      for (final row in byRow.values.where((r) => r.length > 1)) {
        row.sort((a, b) => a.x.compareTo(b.x));
        for (var i = 0; i + 1 < row.length; i++) {
          final left = row[i], right = row[i + 1];
          final gap = right.x - (left.x + PlantUmlService.effectiveWidth(left));
          sawAdjacentPair = true;
          expect(gap, greaterThanOrEqualTo(40),
              reason: 'gap between ${left.name} and ${right.name} too tight');
        }
      }
      expect(sawAdjacentPair, isTrue, reason: 'expected a multi-box row');
    });

    test('keeps notes within their package box and packages disjoint', () {
      final d = PlantUmlService.parse(noteHeavy);
      PlantUmlService.autoLayout(d);

      // Every member (component or note) is enclosed by its package box.
      for (final t in d.types.where((t) => t.groupId != null)) {
        final g = d.groupById(t.groupId!)!;
        final w = t.w ?? PlantUmlService.nodeWidth;
        final h = t.h ?? PlantUmlService.nodeHeight;
        expect(t.x, greaterThanOrEqualTo(g.x - 0.01), reason: '${t.name} left of ${g.id}');
        expect(t.y, greaterThanOrEqualTo(g.y - 0.01), reason: '${t.name} above ${g.id}');
        expect(t.x + w, lessThanOrEqualTo(g.x + g.w + 0.01), reason: '${t.name} right of ${g.id}');
        expect(t.y + h, lessThanOrEqualTo(g.y + g.h + 0.01), reason: '${t.name} below ${g.id}');
      }

      final roots = d.groups.where((g) => g.parentId == null).toList();
      for (var i = 0; i < roots.length; i++) {
        for (var j = i + 1; j < roots.length; j++) {
          final a = roots[i], b = roots[j];
          final hit = a.x < b.x + b.w &&
              a.x + a.w > b.x &&
              a.y < b.y + b.h &&
              a.y + a.h > b.y;
          expect(hit, isFalse, reason: '${a.id} overlaps ${b.id}');
        }
      }
    });
  });

  // Mirrors what the canvas "Wrap in package" / "Move to package" / "Rename"
  // actions produce: a UmlGroup is added and a type's groupId points at it.
  // These assert the model round-trips back through generate -> parse.
  group('package membership round-trip', () {
    test('a class wrapped in a package round-trips with membership intact', () {
      final diagram = PlantUmlService.parse('''
@startuml
class Invoice
@enduml
''');
      // Same operations _wrapInPackage performs.
      diagram.groups.add(UmlGroup(id: 'Package', label: 'Package', keyword: 'package'));
      diagram.typeByName('Invoice')!.groupId = 'Package';
      PlantUmlService.relayoutGroups(diagram);

      final source = PlantUmlService.generate(diagram);
      expect(source, contains('package "Package"'));

      final reparsed = PlantUmlService.parse(source);
      expect(reparsed.groups.map((g) => g.id), contains('Package'));
      expect(reparsed.typeByName('Invoice')!.groupId, 'Package');
    });

    test('a package background color round-trips via @color', () {
      final diagram = PlantUmlService.parse('''
@startuml
package "Payments" as Payments {
  class Invoice
}
@enduml
''');
      diagram.groupById('Payments')!.color = '#FFE082';

      final source = PlantUmlService.generate(diagram);
      expect(source, contains("'@color Payments #FFE082"));

      final reparsed = PlantUmlService.parse(source);
      expect(reparsed.groupById('Payments')!.color, '#FFE082');
    });

    test('renaming a package to a clean identifier promotes the id', () {
      final diagram = PlantUmlService.parse('''
@startuml
package "Package" {
  class Invoice
}
@enduml
''');
      // Same id/label/relation rewrite _renameGroup performs for a clean name.
      const oldId = 'Package';
      const newId = 'Payments';
      for (final t in diagram.types) {
        if (t.groupId == oldId) t.groupId = newId;
      }
      diagram.groupById(oldId)!
        ..id = newId
        ..label = newId;

      final reparsed = PlantUmlService.parse(PlantUmlService.generate(diagram));
      expect(reparsed.groupById('Payments'), isNotNull);
      expect(reparsed.typeByName('Invoice')!.groupId, 'Payments');
    });

    test('multi-line notes parse, attach, render-size and round-trip', () {
      const src = '''
@startuml
package "Routes" as Routes {
  component "Trending" as RTrending
  note bottom of RTrending
    |= verb |= path |
    | POST | /request/trending |
    --
    **POST body** platform, hashtag
  end note
}
note as Free
  Standalone commentary
  spanning two lines
end note
note left of RTrending : inline anchored note
@enduml
''';
      final d = PlantUmlService.parse(src);
      final notes = d.types.where((t) => t.isNote).toList();
      // One anchored block, one free block, one inline anchored.
      expect(notes.length, 3);

      final anchoredBlock = notes.firstWhere((n) => n.label.contains('verb'));
      expect(anchoredBlock.attachedTo, 'RTrending');
      expect(anchoredBlock.groupId, 'Routes'); // sits in the target's package
      // Body text is preserved (escaped \n) and sized to content, not clamped
      // to the fixed node box.
      expect(anchoredBlock.label, contains(r'\n'));
      expect(anchoredBlock.h, greaterThan(PlantUmlService.nodeHeight));

      final free = notes.firstWhere((n) => n.name == 'Free');
      expect(free.attachedTo, isNull);
      expect(free.label, contains('Standalone commentary'));

      final inline = notes.firstWhere((n) => n.label.contains('inline'));
      expect(inline.attachedTo, 'RTrending');

      // Round-trip: notes and their anchors survive generate -> parse.
      final d2 = PlantUmlService.parse(PlantUmlService.generate(d));
      final notes2 = d2.types.where((t) => t.isNote).toList();
      expect(notes2.length, 3);
      expect(notes2.where((n) => n.attachedTo == 'RTrending').length, 2);
      expect(
        notes2.firstWhere((n) => n.name == 'Free').label,
        contains('spanning two lines'),
      );
    });

    test('note body parses into tables, dividers and text blocks', () {
      const body = '''
|= verb |= path |= -> |
| GET | /a | ok 200 |
| DELETE | /a | gone |
--
**POST body** required fields
plain trailing line''';
      final blocks = PlantUmlService.parseNoteBody(body);
      expect(blocks.map((b) => b.kind), [
        UmlNoteBlockKind.table,
        UmlNoteBlockKind.divider,
        UmlNoteBlockKind.text,
      ]);

      final table = blocks.first;
      expect(table.rows.length, 3);
      // Header row: all `|=` cells flagged as headers, `=` stripped.
      expect(table.rows.first.every((c) => c.header), isTrue);
      expect(table.rows.first.map((c) => c.text), ['verb', 'path', '->']);
      // Body rows are not headers.
      expect(table.rows[1].map((c) => c.text), ['GET', '/a', 'ok 200']);
      expect(table.rows[1].every((c) => !c.header), isTrue);

      // Text block keeps creole markers (the renderer interprets **bold**).
      expect(blocks.last.text, contains('**POST body**'));
      expect(blocks.last.text, contains('plain trailing line'));
    });

    test('a table note is sized wider/taller than a plain node box', () {
      const tableBody =
          '|= verb |= path |\n| DELETE | /request/{token} |\n| GET | /requests |';
      final (w, h) = PlantUmlService.noteContentSize(tableBody);
      expect(w, greaterThan(PlantUmlService.nodeWidth));
      expect(h, greaterThan(PlantUmlService.nodeHeight));

      // A parsed note picks up that estimate as its box override.
      final d = PlantUmlService.parse('''
@startuml
component "X" as X
note bottom of X
$tableBody
end note
@enduml
''');
      final note = d.types.firstWhere((t) => t.isNote);
      expect(note.w, greaterThan(PlantUmlService.nodeWidth));
    });

    test('note <side> of X positions the note on that side of the target', () {
      final d = PlantUmlService.parse('''
@startuml
component "A" as A
component "B" as B
component "C" as C
component "D" as D
note bottom of A
  below A
end note
note top of B
  above B
end note
note left of C : left of C
note right of D : right of D
@enduml
''');
      ({double x, double y, double w, double h}) box(String name) {
        final t = d.typeByName(name)!;
        return (
          x: t.x,
          y: t.y,
          w: t.w ?? PlantUmlService.nodeWidth,
          h: t.h ?? PlantUmlService.nodeHeight,
        );
      }

      UmlType noteFor(String target) =>
          d.types.firstWhere((t) => t.isNote && t.attachedTo == target);

      final a = box('A');
      final bottom = noteFor('A');
      expect(bottom.attachedSide, 'bottom');
      expect(bottom.y, greaterThanOrEqualTo(a.y + a.h));

      final b = box('B');
      final top = noteFor('B');
      expect(top.attachedSide, 'top');
      expect(top.y + top.h!, lessThanOrEqualTo(b.y));

      final c = box('C');
      final left = noteFor('C');
      expect(left.attachedSide, 'left');
      expect(left.x + left.w!, lessThanOrEqualTo(c.x + 0.01));

      final dd = box('D');
      final right = noteFor('D');
      expect(right.attachedSide, 'right');
      expect(right.x, greaterThanOrEqualTo(dd.x + dd.w));

      // Side survives a round-trip through generate -> parse.
      final d2 = PlantUmlService.parse(PlantUmlService.generate(d));
      expect(
        d2.types.firstWhere((t) => t.isNote && t.attachedTo == 'A').attachedSide,
        'bottom',
      );
      expect(
        d2.types.firstWhere((t) => t.isNote && t.attachedTo == 'C').attachedSide,
        'left',
      );
    });

    test('a label with spaces keeps a stable alias id', () {
      final diagram = PlantUmlService.parse('''
@startuml
package "Package" {
  class Invoice
}
@enduml
''');
      // Spaces can't be an id, so _renameGroup keeps the id and sets only label.
      diagram.groupById('Package')!.label = 'Billing System';

      final source = PlantUmlService.generate(diagram);
      expect(source, contains('package "Billing System" as Package'));

      final reparsed = PlantUmlService.parse(source);
      expect(reparsed.groupById('Package')!.label, 'Billing System');
      expect(reparsed.typeByName('Invoice')!.groupId, 'Package');
    });
  });
}
