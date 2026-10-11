import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dev_tool/ui/widgets.dart';
import '../helpers/tool_harness.dart';

void main() {
  for (final id in ['port_scanner', 'network_scanner']) {
    testWidgets(
      '$id Scan finds only the loopback fixture and exports both report formats',
      (tester) async {
        late ServerSocket server;
        await tester.runAsync(() async {
          server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((socket) {
            socket.write('SSH-2.0-AuditFixture\r\n');
            socket.flush().then((_) => socket.close());
          });
        });
        addTearDown(() => server.close());
        final h = ToolHarness(tester);
        await h.open(id, surface: const Size(2560, 1640));
        final target = tester.widget<TextField>(
          find.byKey(
            ValueKey(
              id == 'port_scanner'
                  ? 'port-scanner-target'
                  : 'network-scanner-targets',
            ),
          ),
        );
        target.controller!.text = id == 'port_scanner'
            ? '127.0.0.1'
            : '127.0.0.1/32';
        tester
            .widget<SmallDropdown>(
              find.byWidgetPredicate(
                (w) => w is SmallDropdown && w.items.contains('Custom Ports'),
              ),
            )
            .onChanged!('Custom Ports');
        await h.settle();
        final ports = tester.widget<TextField>(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText == '22,80,443 or 8000-8010',
          ),
        );
        ports.controller!.text = '${server.port}';
        if (id == 'network_scanner') {
          tester.widget<Checkbox>(find.byType(Checkbox).first).onChanged!(
            false,
          );
        }
        await tester.runAsync(() async {
          tester
              .widget<ToolButton>(
                find.byWidgetPredicate(
                  (w) => w is ToolButton && w.label == 'Scan',
                ),
              )
              .onPressed!();
          await Future<void>.delayed(const Duration(seconds: 2));
        });
        await h.settle();
        await h.tap('Report');
        final report = tester.widget<EditorPane>(
          find.byWidgetPredicate((w) => w is EditorPane && w.label == 'Report'),
        );
        expect(report.controller!.text, contains('127.0.0.1'));
        expect(report.controller!.text, contains('${server.port}'));
        for (final mode in ['CSV', 'JSON']) {
          tester
              .widget<SmallDropdown>(
                find.byWidgetPredicate(
                  (w) =>
                      w is SmallDropdown &&
                      w.items.contains('CSV') &&
                      w.items.contains('JSON'),
                ),
              )
              .onChanged!(mode);
          await h.settle();
          if (mode == 'JSON' || id == 'network_scanner') {
            expect(h.text(null, label: 'Report'), contains('127.0.0.1'));
          }
          expect(h.text(null, label: 'Report'), contains('${server.port}'));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
