import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dev_tool/app.dart';
import 'package:dev_tool/registry/tool_registry.dart';
import 'package:dev_tool/services/firewall_fingerprint_service.dart';
import 'package:dev_tool/services/hash_lookup_service.dart';
import 'package:dev_tool/services/network_scanner_service.dart';
import 'package:dev_tool/services/payload_embedding_service.dart';
import 'package:dev_tool/services/port_scanner_service.dart';
import 'package:dev_tool/services/subdomain_lookup_service.dart';
import 'package:dev_tool/services/subdomain_takeover_service.dart';
import 'package:dev_tool/state/tool_state.dart';
import 'package:dev_tool/state/workspace_state.dart';
import 'package:dev_tool/ui/app_colors.dart';
import 'package:dev_tool/ui/tool_views.dart'
    show convertJavaScriptToTypeScriptForPreview, markdownToHtmlForPreview;
import 'package:dev_tool/ui/widgets.dart' show EditorPane;

// ---------------------------------------------------------------------------
// Editor test helpers.
//
// Editors render with re_editor's CodeEditor (via EditorPane), which is NOT a
// Flutter TextField/EditableText — so `find.byType(TextField)` + `enterText`
// don't apply. Tests drive an editor through the EditorPane public API,
// locating the pane by its placeholder (hint) text.
// ---------------------------------------------------------------------------

Finder editorPaneWithHint(String hint) =>
    find.byWidgetPredicate((w) => w is EditorPane && w.placeholder == hint);

EditorPane _paneWithHint(WidgetTester tester, String hint) =>
    tester.widget<EditorPane>(editorPaneWithHint(hint));

/// Sets an editor's text (mirrors a user edit: updates the bound controller and
/// fires the pane's onChanged so live tools recompute).
Future<void> enterEditorText(
  WidgetTester tester,
  String hint,
  String text,
) async {
  final pane = _paneWithHint(tester, hint);
  pane.controller!.text = text;
  pane.onChanged?.call(text);
  // Advance past any input debounce (live tools recompute on a ~200ms timer).
  await tester.pump(const Duration(milliseconds: 250));
}

String editorText(WidgetTester tester, String hint) =>
    _paneWithHint(tester, hint).controller!.text;

void main() {
  test('Preferences are registered as one combined tool', () {
    final preferences = ToolRegistry.tools
        .where((tool) => tool.category == 'Preferences')
        .toList();

    expect(preferences, hasLength(1));
    expect(preferences.single.id, 'preferences');
    expect(preferences.single.name, 'Preferences');
  });

  test('Subdomain finder normalizes pasted domains and URLs', () {
    expect(
      SubdomainLookupService.normalizeDomain('https://www.Example.com/a'),
      'example.com',
    );
    expect(
      SubdomainLookupService.normalizeDomain('*.api.example.com'),
      'api.example.com',
    );
  });

  test('Subdomain takeover scanner normalizes pasted host lists', () {
    expect(
      SubdomainTakeoverService.parseTargets(
        'https://Docs.Example.com/path\n*.help.example.com, api.example.com:443',
      ),
      ['api.example.com', 'docs.example.com', 'help.example.com'],
    );
  });

  test(
    'Subdomain takeover scanner detects high-confidence provider evidence',
    () async {
      final service = SubdomainTakeoverService(
        client: MockClient(
          (_) async =>
              http.Response("There isn't a GitHub Pages site here.", 404),
        ),
        cnameLookup: (_) async => ['owner.github.io.'],
        now: () => DateTime(2026),
      );
      addTearDown(service.close);

      final summary = await service.scanText('docs.example.com');
      final result = summary.results.single;

      expect(summary.potentialCount, 1);
      expect(result.service, 'GitHub Pages');
      expect(result.confidence, TakeoverConfidence.high);
      expect(result.matchedCnameIndicator, 'github.io');
      expect(
        result.matchedBodyIndicator,
        'There isn\'t a GitHub Pages site here',
      );
    },
  );

  test('Subdomain takeover scanner avoids generic body-only matches', () async {
    final service = SubdomainTakeoverService(
      client: MockClient((_) async => http.Response('404 Not Found', 404)),
      cnameLookup: (_) async => const <String>[],
      now: () => DateTime(2026),
    );
    addTearDown(service.close);

    final summary = await service.scanText('missing.example.com');

    expect(summary.potentialCount, 0);
    expect(summary.results.single.confidence, TakeoverConfidence.safe);
  });

  test('Port scanner parses custom ports and scores risky services', () {
    expect(PortScannerService.parsePorts('22,80,8000-8002'), [
      22,
      80,
      8000,
      8001,
      8002,
    ]);

    final service = PortScannerService.commonServices[445]!;
    final risk = PortScannerService.riskyPorts[445]!;
    final score = PortScannerService.calculateSecurityScore([
      PortScanResult(
        port: 445,
        status: 'OPEN',
        service: service.name,
        protocol: service.protocol,
        category: service.category,
        encrypted: service.encrypted,
        riskLevel: risk.level,
        riskScore: risk.score,
        riskReason: risk.reason,
        vulnerabilities: PortScannerService.vulnerabilityDatabase[445]!,
        timestamp: DateTime(2026),
        banner: 'No banner',
      ),
    ]);

    expect(score.score, lessThan(100));
    expect(score.recommendations.single.title, 'Secure SMB');
  });

  test('Network scanner parses CIDR ranges and finds devices', () async {
    final range = NetworkScannerService.parseNetwork('192.168.1.0/30');
    expect(range.cidr, '192.168.1.0/30');
    expect(range.hosts(maxHosts: 8), ['192.168.1.1', '192.168.1.2']);

    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());
    server.listen((client) {
      unawaited(client.flush().whenComplete(client.destroy));
    });

    final service = NetworkScannerService(
      now: () => DateTime(2026),
      ping: (host, {required timeout}) async => host == '127.0.0.1',
    );
    addTearDown(service.close);
    final summary = await service.scan(
      networkText: '127.0.0.0/30',
      profile: NetworkScanProfile(
        name: 'Test',
        description: 'Local discovery test',
        ports: [server.port],
        timeout: const Duration(milliseconds: 600),
        concurrency: 1,
        maxHosts: 8,
      ),
    );

    final loopback = summary.results.firstWhere(
      (result) => result.ip == '127.0.0.1',
    );
    expect(loopback.pingResponded, isTrue);
    expect(loopback.openPorts.single.port, server.port);
    expect(summary.toJsonReport(), contains('responsive_devices'));
  });

  test('Hash lookup identifies hashes and cracks local wordlists', () async {
    final candidates = HashLookupService.extractCandidates(
      'admin:21232f297a57a5a743894a0e4a801fc3',
    );
    expect(candidates, hasLength(1));
    expect(candidates.single.label, contains('MD5'));

    final service = HashLookupService();
    addTearDown(service.close);
    final results = await service.crackWithWordlist(
      input: candidates.single.value,
      words: const ['root', 'admin', 'devutils'],
    );

    expect(results.single.cracked, isTrue);
    expect(results.single.algorithm, 'MD5');
    expect(results.single.plaintext, 'admin');
  });

  test('Firewall fingerprint detects Cloudflare evidence', () async {
    final service = FirewallFingerprintService(
      client: MockClient(
        (_) async => http.Response(
          'Attention Required! Cloudflare Ray ID: abc',
          403,
          headers: {
            'server': 'cloudflare',
            'cf-ray': 'abc',
            'set-cookie': '__cf_bm=test',
          },
        ),
      ),
      now: () => DateTime(2026),
    );
    addTearDown(service.close);

    final result = await service.scan(target: 'example.com', findAll: true);

    expect(result.url.toString(), 'https://example.com/');
    expect(result.detected, isTrue);
    expect(result.detections.first.firewall, 'Cloudflare');
    expect(result.requestCount, 8);
  });

  test('Payload embedder roundtrips encrypted PNG, JPEG, and PDF carriers', () {
    final carriers = <PayloadCarrierFormat, Uint8List>{
      PayloadCarrierFormat.png: _minimalPng(),
      PayloadCarrierFormat.jpeg: _minimalJpeg(),
      PayloadCarrierFormat.pdf: _minimalPdf(),
    };
    final payload = Uint8List.fromList(utf8.encode('secret payload'));

    for (final entry in carriers.entries) {
      final result = PayloadEmbeddingService.embed(
        carrier: entry.value,
        payload: payload,
        payloadFileName: 'secret.txt',
        passphrase: 'correct horse battery staple',
        iterations: 1000,
      );

      final info = PayloadEmbeddingService.inspect(result.bytes);
      expect(info, isNotNull);
      expect(info!.format, entry.key);
      expect(info.envelopeSize, greaterThan(payload.length));

      final decoded = PayloadEmbeddingService.extract(
        carrier: result.bytes,
        passphrase: 'correct horse battery staple',
      );
      expect(decoded.fileName, 'secret.txt');
      expect(utf8.decode(decoded.bytes), 'secret payload');
      expect(
        () => PayloadEmbeddingService.extract(
          carrier: result.bytes,
          passphrase: 'wrong',
        ),
        throwsFormatException,
      );
    }
  });

  test('Payload embedder inspect returns null when no payload exists', () {
    expect(PayloadEmbeddingService.inspect(_minimalPdf()), isNull);
  });

  test('Subdomain finder parses certificate transparency results', () async {
    final service = SubdomainLookupService(
      client: MockClient(
        (_) async => http.Response(
          '[{"name_value":"www.example.com\\n*.api.example.com","common_name":"example.com"}]',
          200,
        ),
      ),
      dnsProbeLabels: const [],
    );
    addTearDown(service.close);

    final result = await service.lookup('example.com');

    expect(result.domain, 'example.com');
    expect(result.subdomains, ['api.example.com', 'www.example.com']);
    expect(result.sources, ['Certificate transparency']);
    expect(result.warnings, isEmpty);
  });

  test(
    'Subdomain finder uses subfinder when the binary is available',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('subfinder-test-');
      addTearDown(() => tempDir.delete(recursive: true));
      final binary = File('${tempDir.path}/subfinder');
      await binary.writeAsString('');

      final service = SubdomainLookupService(
        client: MockClient((_) async => http.Response('', 404)),
        dnsProbeLabels: const [],
        subfinderPaths: [binary.path],
        subfinderRunner: (executable, arguments, timeout) async {
          expect(executable, binary.path);
          expect(arguments, contains('example.com'));
          return const SubfinderCommandResult(
            exitCode: 0,
            stdout: 'www.example.com\napi.example.com\nexample.com\n',
            stderr: '',
          );
        },
      );
      addTearDown(service.close);

      final result = await service.lookup('example.com');

      expect(result.usedSubfinder, isTrue);
      expect(result.sources, contains('subfinder'));
      expect(result.subdomains, ['api.example.com', 'www.example.com']);
    },
  );

  test(
    'Subdomain finder stays quiet when subfinder is not installed',
    () async {
      final service = SubdomainLookupService(
        client: MockClient((_) async => http.Response('', 404)),
        dnsProbeLabels: const [],
        subfinderPaths: const ['/tmp/devutils-missing-subfinder'],
      );
      addTearDown(service.close);

      final result = await service.lookup('example.com');

      expect(result.usedSubfinder, isFalse);
      expect(result.warnings, isEmpty);
      expect(result.subdomains, isEmpty);
    },
  );

  test('Subdomain finder uses CertSpotter when crt.sh is empty', () async {
    final service = SubdomainLookupService(
      client: MockClient((request) async {
        if (request.url.host == 'api.certspotter.com') {
          return http.Response(
            '[{"dns_names":["example.com","*.example.com","forge.example.com","sdk12.example.com"]}]',
            200,
          );
        }
        return http.Response('', 404);
      }),
      dnsProbeLabels: const [],
      subfinderPaths: const ['/tmp/devutils-missing-subfinder'],
    );
    addTearDown(service.close);

    final result = await service.lookup('example.com');

    expect(result.sources, contains('CertSpotter'));
    expect(result.subdomains, ['forge.example.com', 'sdk12.example.com']);
  });

  test('Subdomain finder uses HackerTarget host search', () async {
    final service = SubdomainLookupService(
      client: MockClient((request) async {
        if (request.url.host == 'api.hackertarget.com') {
          return http.Response(
            'example.com,192.0.2.1\nbot99.example.com,192.0.2.2\nsentry.example.com,192.0.2.3',
            200,
          );
        }
        return http.Response('', 404);
      }),
      dnsProbeLabels: const [],
      subfinderPaths: const ['/tmp/devutils-missing-subfinder'],
    );
    addTearDown(service.close);

    final result = await service.lookup('example.com');

    expect(result.sources, contains('HackerTarget'));
    expect(result.subdomains, ['bot99.example.com', 'sentry.example.com']);
  });

  test('Subdomain finder parses organization certificate results', () async {
    final service = SubdomainLookupService(
      client: MockClient(
        (_) async => http.Response(
          '[{"common_name":"www.github.com","name_value":"*.api.github.com\\nsecurity@github.com"}]',
          200,
        ),
      ),
      dnsProbeLabels: const [],
    );
    addTearDown(service.close);

    final result = await service.lookupOrganization(' GitHub Inc ');

    expect(result.domain, 'GitHub Inc');
    expect(result.mode, SubdomainLookupMode.organization);
    expect(result.subdomains, ['api.github.com', 'www.github.com']);
    expect(result.sources, ['Organization certificates']);
    expect(result.warnings, isEmpty);
  });

  test(
    'Subdomain finder falls back to DNS when certificate lookup times out',
    () async {
      final service = SubdomainLookupService(
        client: MockClient((_) async => throw TimeoutException('slow')),
        dnsProbeLabels: const ['www', 'api'],
        dnsLookup: (host) async {
          if (host == 'www.example.com') {
            return [InternetAddress('127.0.0.1')];
          }
          return const <InternetAddress>[];
        },
      );
      addTearDown(service.close);

      final result = await service.lookup('example.com');

      expect(result.subdomains, ['www.example.com']);
      expect(result.sources, ['DNS probe']);
      expect(result.warnings, contains('crt.sh timed out.'));
    },
  );

  testWidgets('App shell renders the workspace', (WidgetTester tester) async {
    await tester.pumpWidget(DevToolApp(state: ToolState.inMemory()));

    expect(find.text('Search tools'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Open a tool from the sidebar'), findsOneWidget);
  });

  testWidgets('Sidebar opens tools as workspace panels', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DevToolApp(state: ToolState.inMemory()));

    await tester.tap(find.text('JSON Format/Validate').first);
    await tester.pumpAndSettle();

    expect(find.text('Paste JSON...'), findsOneWidget);
    expect(find.byIcon(Icons.data_object), findsWidgets);
  });

  testWidgets('Subdomain finder renders domain lookup controls', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('subdomain_finder');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Domain'), findsOneWidget);
    expect(find.text('Organization'), findsOneWidget);
    expect(find.text('Find known'), findsOneWidget);
    expect(find.textContaining('Sources:'), findsNothing);

    await tester.tap(find.text('Organization'));
    await tester.pump();

    expect(find.textContaining('Source:'), findsNothing);
    expect(
      find.text('Enter an organization name to find public certificate names.'),
      findsOneWidget,
    );
  });

  testWidgets('Network security tools render controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var state = ToolState.inMemory();
    state.workspace.openTool('port_scanner');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Port Scanner'), findsWidgets);
    expect(find.text('Quick Scan'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Recon'), findsWidgets);
    expect(find.text('Banners'), findsOneWidget);
    expect(find.text('TLS details'), findsOneWidget);
    expect(find.text('HTTP HEAD'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    state = ToolState.inMemory();
    state.workspace.openTool('network_scanner');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Network Scanner'), findsWidgets);
    expect(find.text('Quick LAN'), findsOneWidget);
    expect(find.text('Ping'), findsOneWidget);
    expect(find.text('TCP ports'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('network-scanner-targets')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    state = ToolState.inMemory();
    state.workspace.openTool('subdomain_takeover');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Subdomain Takeover Check'), findsWidgets);
    expect(find.text('Targets'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subdomain-takeover-targets')),
      findsOneWidget,
    );
    expect(find.text('Timeout'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    state = ToolState.inMemory();
    state.workspace.openTool('firewall_fingerprint');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Firewall Fingerprint'), findsWidgets);
    expect(find.text('Fingerprint'), findsOneWidget);
    expect(find.text('Find all'), findsOneWidget);
    expect(find.text('Redirects'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('firewall-fingerprint-target')),
      findsOneWidget,
    );
  });

  testWidgets('Sidebar splitter adjusts menu width', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    await tester.pumpWidget(DevToolApp(state: state));

    await tester.drag(
      find.byKey(const ValueKey('sidebar-resize-handle')),
      const Offset(40, 0),
    );
    await tester.pump();

    expect(state.sidebarWidth.value, 290);

    await tester.drag(
      find.byKey(const ValueKey('sidebar-resize-handle')),
      const Offset(-400, 0),
    );
    await tester.pump();

    expect(state.sidebarWidth.value, 64);
  });

  testWidgets('Sidebar collapses to icon-only navigation', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.sidebarWidth.value = 64;
    await tester.pumpWidget(DevToolApp(state: state));

    expect(find.text('Search tools'), findsNothing);
    expect(find.byTooltip('JSON Format/Validate'), findsOneWidget);
  });

  test('Workspace tiles every visible panel', () {
    final workspace = WorkspaceState.inMemory();
    workspace.openTool('json_format_validate', forceNew: true);
    workspace.openTool('base64_string_encode_decode', forceNew: true);
    workspace.openTool('jwt_debugger', forceNew: true);

    workspace.tileVisiblePanels(const Size(1200, 800));

    final visible = workspace.panels.value
        .where((panel) => !panel.isMinimized)
        .toList();
    expect(visible, hasLength(3));
    expect(
      visible.map((panel) => panel.dockMode),
      everyElement(PanelDockMode.tiled),
    );

    final bounds = visible.map((panel) => panel.bounds).toList();
    for (var i = 0; i < bounds.length; i++) {
      expect(bounds[i].left, greaterThanOrEqualTo(0));
      expect(bounds[i].top, greaterThanOrEqualTo(0));
      expect(bounds[i].right, lessThanOrEqualTo(1200));
      expect(bounds[i].bottom, lessThanOrEqualTo(800));
      for (var j = i + 1; j < bounds.length; j++) {
        expect(bounds[i].overlaps(bounds[j]), isFalse);
      }
    }
  });

  test('Workspace groups panels docked to the same side as tabs', () {
    final workspace = WorkspaceState.inMemory();
    final first = workspace.openTool('json_format_validate', forceNew: true);
    final second = workspace.openTool(
      'base64_string_encode_decode',
      forceNew: true,
    );

    workspace.snapPanel(
      first.instanceId,
      PanelDockMode.left,
      const Size(1200, 800),
    );
    workspace.snapPanel(
      second.instanceId,
      PanelDockMode.left,
      const Size(1200, 800),
    );

    final leftPanels = workspace.panels.value
        .where((panel) => panel.dockMode == PanelDockMode.left)
        .toList();
    expect(leftPanels, hasLength(2));
    for (final panel in leftPanels) {
      expectRectClose(panel.bounds, const Rect.fromLTWH(14, 14, 579, 772));
    }

    workspace.closePanel(first.instanceId);

    final remaining = workspace.panelById(second.instanceId)!;
    expectRectClose(remaining.bounds, const Rect.fromLTWH(14, 14, 579, 772));
    expect(workspace.focusedPanelId.value, second.instanceId);
  });

  test('Workspace keeps left and right dock tab groups independent', () {
    final workspace = WorkspaceState.inMemory();
    final left = workspace.openTool('json_format_validate', forceNew: true);
    final rightFirst = workspace.openTool(
      'base64_string_encode_decode',
      forceNew: true,
    );
    final rightSecond = workspace.openTool('jwt_debugger', forceNew: true);

    workspace.snapPanel(
      left.instanceId,
      PanelDockMode.left,
      const Size(1200, 800),
    );
    workspace.snapPanel(
      rightFirst.instanceId,
      PanelDockMode.right,
      const Size(1200, 800),
    );
    workspace.snapPanel(
      rightSecond.instanceId,
      PanelDockMode.right,
      const Size(1200, 800),
    );

    expectRectClose(
      workspace.panelById(left.instanceId)!.bounds,
      const Rect.fromLTWH(14, 14, 579, 772),
    );

    final rightPanels = workspace.panels.value
        .where((panel) => panel.dockMode == PanelDockMode.right)
        .toList();
    expect(rightPanels, hasLength(2));
    for (final panel in rightPanels) {
      expectRectClose(panel.bounds, const Rect.fromLTWH(607, 14, 579, 772));
    }
  });

  testWidgets('Dock tab groups render one active panel at a time', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = ToolState.inMemory();
    final jwt = state.workspace.openTool('jwt_debugger', forceNew: true);
    final regexp = state.workspace.openTool('regexp_tester', forceNew: true);
    state.workspace.snapPanel(
      jwt.instanceId,
      PanelDockMode.left,
      const Size(1200, 800),
    );
    state.workspace.snapPanel(
      regexp.instanceId,
      PanelDockMode.left,
      const Size(1200, 800),
    );

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('RegExp:'), findsOneWidget);
    expect(find.text('Header'), findsNothing);

    await tester.tap(find.text('JWT Debugger').first);
    await tester.pumpAndSettle();

    expect(find.text('Header'), findsOneWidget);
    expect(find.text('RegExp:'), findsNothing);
    expect(state.workspace.focusedPanelId.value, jwt.instanceId);
  });

  testWidgets('Clipboard paste icons are hidden from tool panels', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DevToolApp(state: ToolState.inMemory()));

    await tester.tap(find.text('JSON Format/Validate').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Clipboard'), findsNothing);
    expect(find.byIcon(Icons.content_paste), findsNothing);
    expect(find.byIcon(Icons.copy), findsNothing);
    expect(find.byIcon(Icons.copy_all), findsNothing);
  });

  testWidgets('JSON panel formats as the user types without action buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DevToolApp(state: ToolState.inMemory()));

    await tester.tap(find.text('JSON Format/Validate').first);
    await tester.pumpAndSettle();

    expect(find.text('Go'), findsNothing);
    expect(find.text('Sample'), findsNothing);
    expect(find.text('Clear'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(find.byTooltip('Sample'), findsNothing);
    expect(find.byIcon(Icons.clear), findsNothing);
    expect(find.byTooltip('Clear'), findsNothing);

    final inputFinder = editorPaneWithHint('Paste JSON...');
    await tester.tapAt(
      tester.getCenter(inputFinder),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Example'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();

    expect(editorText(tester, 'Paste JSON...'), contains('"name":"DevUtils"'));

    await tester.tapAt(
      tester.getCenter(inputFinder),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(editorText(tester, 'Paste JSON...'), isEmpty);

    await enterEditorText(tester, 'Paste JSON...', '{"name":"DevUtils"}');

    expect(
      editorText(tester, 'Formatted JSON...'),
      contains('"name": "DevUtils"'),
    );
  });

  testWidgets('JSON CSV panel converts live without action buttons', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('json_csv_converter');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Go'), findsNothing);
    expect(find.text('Sample'), findsNothing);
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('CSV → JSON'), findsOneWidget);
    expect(find.text('JSON → CSV'), findsOneWidget);

    await enterEditorText(tester, 'id,name,note', 'id,name\n1,DevUtils');

    final output = editorText(tester, '[]');
    expect(output, contains('"id": "1"'));
    expect(output, contains('"name": "DevUtils"'));
  });

  testWidgets('Base64 converter updates live with compact editor controls', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('base64_string_encode_decode');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Go'), findsNothing);
    expect(find.text('Sample'), findsNothing);
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Copy'), findsNothing);

    final inputFinder = editorPaneWithHint('SGVsbG8=');
    final outputFinder = editorPaneWithHint('Hello');
    final inputHeight = tester.getSize(inputFinder).height;
    final outputHeight = tester.getSize(outputFinder).height;

    await tester.drag(
      find.byKey(const ValueKey('split-editor-vertical-resize-handle')).first,
      const Offset(0, 80),
    );
    await tester.pump();

    expect(tester.getSize(inputFinder).height, greaterThan(inputHeight));
    expect(tester.getSize(outputFinder).height, lessThan(outputHeight));

    await enterEditorText(tester, 'SGVsbG8=', 'SGVsbG8=');

    expect(editorText(tester, 'Hello'), 'Hello');
  });

  testWidgets('Number base converter handles BigInt values and inspector', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = ToolState.inMemory();
    state.workspace.openTool('number_base_converter');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Number Base Converter'), findsWidgets);
    expect(
      find.text('Enter your number in any of the text field.'),
      findsNothing,
    );
    expect(find.text('Unsigned'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('number-base-input')),
      '0xffffffffffffffffffffffffffffffff',
    );
    await tester.pump();

    expect(find.text('Base 32'), findsOneWidget);
    expect(
      find.text('340282366920938463463374607431768211455'),
      findsOneWidget,
    );
    expect(find.text('0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'), findsOneWidget);
    expect(find.text('128'), findsWidgets);
    expect(find.text('16'), findsWidgets);
  });

  testWidgets('Base64 image load action is overlaid and save is removed', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('base64_image_encode_decode');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Load File...'), findsOneWidget);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.byIcon(Icons.save_alt), findsNothing);
  });

  testWidgets('HTML beautify tool can render preview mode', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('html_beautify_minify');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    await enterEditorText(
      tester,
      'Paste HTML here...',
      '<h1>Hello</h1><p><strong>Rendered</strong> preview</p>',
    );

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('html-rendered-preview')), findsOneWidget);
  });

  testWidgets('CSS minify emits valid CSS without capture placeholders', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('css_beautify_minify');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    await enterEditorText(
      tester,
      'Drop a .css file here or paste CSS...',
      '''
html,
body {
  margin: 0;
}

* {
  box-sizing: border-box;
}

body {
  background-color: #2f3542;
}''',
    );

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minify').last);
    await tester.pumpAndSettle();

    final output = editorText(tester, 'Output...');
    expect(
      output,
      'html,body{margin:0}*{box-sizing:border-box}body{background-color:#2f3542}',
    );
    expect(output, isNot(contains(r'$1')));
  });

  testWidgets('SVG to CSS accepts typed source and exposes Finder loading', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('svg_to_css');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose SVG file'), findsOneWidget);

    await enterEditorText(
      tester,
      'Drop an .svg file here or paste SVG source...',
      '<svg xmlns="http://www.w3.org/2000/svg"><circle cx="4" cy="4" r="4"/></svg>',
    );

    final output = editorText(tester, 'Output...');
    expect(
      output,
      startsWith("background-image: url('data:image/svg+xml,"),
    );
    expect(output, contains('%3Csvg'));
  });

  testWidgets('Color converter uses a compact palette picker', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = ToolState.inMemory();
    state.workspace.openTool('color_converter');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('color-converter-swatch-panel')),
      findsOneWidget,
    );
    expect(find.text('Palette'), findsOneWidget);
    expect(find.text('Hue'), findsOneWidget);
    expect(find.text('Swatch'), findsNothing);
    expect(find.text('Code Presets'), findsNothing);
    expect(find.text('View Source'), findsNothing);
    expect(find.text('Variables'), findsNothing);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == '#5CC07F, rgb(92, 192, 127)',
      ),
      'rgba(92, 192, 127, 0.5)',
    );
    await tester.pump();
    expect(find.text('#5cc07f80'), findsOneWidget);

    final preset = tester.widget<InkWell>(
      find.byKey(const ValueKey('color-preset-#3b82f6')),
    );
    preset.onTap?.call();
    await tester.pump();
    expect(find.text('#3b82f6'), findsOneWidget);
  });

  testWidgets('Preferences expose live color themes', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = ToolState.inMemory();
    state.workspace.openTool('preferences');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();

    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('Classic Blue'), findsWidgets);
    expect(find.text('Emerald'), findsOneWidget);

    await tester.tap(find.text('Emerald'));
    await tester.pumpAndSettle();

    expect(state.colorTheme.value, 'Emerald');
    final element = tester.element(find.text('Color theme'));
    expect(
      Theme.of(element).extension<AppColors>()?.accent,
      AppColors.darkForTheme('Emerald').accent,
    );
  });

  testWidgets('Payload embedder exposes Finder and drop-backed file fields', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('payload_embedder');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose file'), findsNWidgets(3));
    expect(find.byTooltip('Choose folder'), findsOneWidget);
    expect(find.text('Check embedded data'), findsOneWidget);
    expect(find.text('Carrier file'), findsOneWidget);
    expect(find.text('Payload file'), findsOneWidget);
    expect(find.text('Output file'), findsOneWidget);

    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();

    expect(find.text('Stego file'), findsOneWidget);
    expect(find.text('Output file'), findsNothing);
    expect(find.text('Check embedded data'), findsOneWidget);
  });

  testWidgets('Payload embedder can inspect generated output file', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tempDir = await Directory.systemTemp.createTemp(
      'devutils-payload-widget-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final carrierFile = File('${tempDir.path}/carrier.png');
    final payloadFile = File('${tempDir.path}/secret.txt');
    final outputFile = File('${tempDir.path}/carrier.embedded.png');
    await carrierFile.writeAsBytes(_minimalPng());
    await payloadFile.writeAsString('secret payload');

    final state = ToolState.inMemory();
    state.workspace.openTool('payload_embedder');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                '/path/to/image.png, image.jpg, or document.pdf',
      ),
      carrierFile.path,
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == '/path/to/secret.txt',
      ),
      payloadFile.path,
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Leave empty to create *.embedded.*',
      ),
      outputFile.path,
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Required for encryption/decode',
      ),
      'correct horse battery staple',
    );
    await tester.pump();

    final embedded = PayloadEmbeddingService.embed(
      carrier: _minimalPng(),
      payload: Uint8List.fromList(utf8.encode('secret payload')),
      payloadFileName: 'secret.txt',
      passphrase: 'correct horse battery staple',
      iterations: 1000,
    );
    await outputFile.writeAsBytes(embedded.bytes);
    expect(await outputFile.exists(), isTrue);

    await tester.tap(find.text('Check embedded data'));
    await tester.pumpAndSettle();

    final result = editorText(
      tester,
      'Embed, check, or decode encrypted files inside PNG, JPG, or PDF carriers...',
    );
    expect(result, contains('Encrypted payload found.'));
    expect(result, contains('Checked: ${outputFile.path}'));
  });

  testWidgets('HTML to JSX converts comments attributes styles and roots', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('html_to_jsx');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    const html = '''
<!-- Hello world -->
<div class="awesome" style="border: 1px solid red">
  <label for="name">Enter your name: </label>
  <input type="text" id="name" />
</div>
<p>Enter your HTML here</p>''';

    await enterEditorText(tester, 'Paste HTML here...', html);

    expect(editorText(tester, 'JSX output...'), '''
<div>
  {/* Hello world */}
  <div className="awesome" style={{ border: '1px solid red' }}>
    <label htmlFor="name">Enter your name: </label>
    <input type="text" id="name" />
  </div>
  <p>Enter your HTML here</p>
</div>''');
  });

  test('JS to TS converter adds migration-safe TypeScript hints', () {
    const js = '''
const express = require('express');

/**
 * @param {string} name
 * @param {number} count
 * @returns {string}
 */
function greet(name, count) {
  return name.repeat(count);
}

greet('DevUtils');

class Super {
  touch() {
    this.superProp = 1;
  }
}

class Sub extends Super {
  touch() {
    const self = this;
    self.superProp = 2;
    self.subProp = 3;
  }
}

module.exports = { greet, Sub };''';

    final ts = convertJavaScriptToTypeScriptForPreview(js);

    expect(ts, contains("import express from 'express';"));
    expect(
      ts,
      contains('function greet(name: string, count?: number): string {'),
    );
    expect(ts, contains('public superProp: any;'));
    expect(ts, contains('public subProp: any;'));
    expect(
      ts,
      isNot(contains('class Sub extends Super {\n  public superProp')),
    );
    expect(ts, contains('export { greet, Sub };'));
  });

  testWidgets('JS to TS converter is registered and converts pasted source', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('js_to_ts_converter');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose JavaScript file'), findsOneWidget);

    await enterEditorText(
      tester,
      'Choose a .js/.jsx file or paste JavaScript...',
      '''
/** @param {string} name @returns {string} */
function greet(name) {
  return name;
}
module.exports = greet;''',
    );

    final output = editorText(tester, 'TypeScript output...');
    expect(output, contains('function greet(name: string): string {'));
    expect(output, contains('export default greet;'));
  });

  testWidgets('Text encryption updates output without a Go button', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('text_encryption');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Go'), findsNothing);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Enter password for encryption/decryption...',
      ),
      'secret',
    );
    await enterEditorText(tester, 'Enter text to encrypt...', 'hello');

    expect(editorText(tester, 'Encrypted output appears here...'), isNotEmpty);
  });

  testWidgets('String case converter applies selected output case', (
    WidgetTester tester,
  ) async {
    final state = ToolState.inMemory();
    state.workspace.openTool('string_case_converter');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    await enterEditorText(tester, 'Enter text...', 'requestURLDecoderID');

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONSTANT_CASE').last);
    await tester.pumpAndSettle();

    expect(editorText(tester, 'Output...'), contains('REQUEST_URL_DECODER_ID'));
  });

  testWidgets('HTML and Markdown preview tools render preview panes', (
    WidgetTester tester,
  ) async {
    var state = ToolState.inMemory();
    state.workspace.openTool('html_preview');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();
    await enterEditorText(tester, '<html>...</html>', '<h1>Hello</h1>');

    expect(find.byKey(const ValueKey('html-rendered-preview')), findsOneWidget);
    expect(find.text('Rendered HTML'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    state = ToolState.inMemory();
    state.workspace.openTool('markdown_preview');

    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();
    await enterEditorText(
      tester,
      'Drop a .md file here or type Markdown...',
      '# Hello\n\n**Rendered** markdown',
    );

    expect(find.byKey(const ValueKey('html-rendered-preview')), findsOneWidget);
    expect(find.text('Rendered Markdown'), findsOneWidget);
  });

  test('Markdown preview renders pipe tables as HTML tables', () {
    const markdown = '''
## Tech Stack

| Layer | Technology | Version | Purpose |
|-------|------------|---------|---------|
| Runtime | Flutter | 3.24+ (stable) | Cross-platform desktop framework |
| Language | Dart | 3.10.4+ | Primary language with strong typing |''';

    final html = markdownToHtmlForPreview(markdown);

    expect(html, contains('<h2>Tech Stack</h2>'));
    expect(html, contains('<table>'));
    expect(html, contains('<th>Layer</th>'));
    expect(html, contains('<td>Flutter</td>'));
    expect(html, isNot(contains('<p>| Layer | Technology')));
  });

  testWidgets('Hash generator fills SHA digests without a key', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = ToolState.inMemory();
    state.workspace.openTool('hash_generator');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    await enterEditorText(tester, 'Enter text to hash...', 'abc');

    expect(find.text('HMAC key'), findsNothing);
    expect(
      find.text('A9993E364706816ABA3E25717850C26C9CD0D89D'),
      findsOneWidget,
    );
    expect(
      find.text('23097D223405D8228642A477BDA255B32AADBCE4BDA0B3F7E36C9DA7'),
      findsOneWidget,
    );
    expect(
      find.text(
        'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'CB00753F45A35E8BB5A03D699AC65007272C32AB0EDED163'
        '1A8B605A43FF5BED8086072BA1E7CC2358BAECA134C825A7',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEE'
        'E64B55D39A2192992A274FC1A836BA3C23A3FEEBBD454D442364'
        '3CE80E2A9AC94FA54CA49F',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Lookup').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('hash-lookup-input')),
      '900150983cd24fb0d6963f7d28e17f72',
    );
    await tester.pump();
    await tester.tap(find.text('Local crack'));
    await tester.pumpAndSettle();

    final report = editorText(tester, 'Hash analysis and crack results...');
    expect(report, contains('1 of 1 hash matched'));
    expect(report, contains('plaintext: abc'));
  });

  testWidgets('tool helper text stays readable in light and dark mode', (
    WidgetTester tester,
  ) async {
    const helperText = 'Tips: Mathematical operators + - * / are supported';

    for (final darkMode in [false, true]) {
      final state = ToolState.inMemory();
      state.darkMode.value = darkMode;
      state.workspace.openTool('unix_time_converter');

      await tester.pumpWidget(DevToolApp(state: state));
      await tester.pumpAndSettle();

      final helper = tester.widget<Text>(find.text(helperText));
      expect(
        helper.style?.color,
        darkMode ? AppColors.dark.mutedText : AppColors.light.mutedText,
      );
      expect(find.text(_testLocalTimezoneLabel()), findsOneWidget);
      expect(find.textContaining('Local timezone:'), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.text('Other timezones:'), findsNothing);
      expect(find.text('Add timezone...'), findsNothing);
      expect(find.text('(Pick a timezone to get started...)'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Unix time converter compares two selectable timezones', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = ToolState.inMemory();
    state.workspace.openTool('unix_time_converter');
    await tester.pumpWidget(DevToolApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Timezone 1'), findsOneWidget);
    expect(find.text('Timezone 2'), findsOneWidget);
    final timezone1TopLeft = tester.getTopLeft(find.text('Timezone 1'));
    final timezone2TopLeft = tester.getTopLeft(find.text('Timezone 2'));
    expect(timezone2TopLeft.dx, greaterThan(timezone1TopLeft.dx));
    expect(
      (timezone2TopLeft.dy - timezone1TopLeft.dy).abs(),
      lessThanOrEqualTo(1),
    );
    expect(find.text(_testLocalTimezoneLabel()), findsOneWidget);
    expect(find.text('UTC'), findsOneWidget);
    expect(find.text('Selected:'), findsNothing);
    expect(find.byIcon(Icons.copy), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('unix-time-input')), '0');
    await tester.pump();

    expect(find.text('Unix ms'), findsWidgets);
    expect(find.text('Unix ns'), findsWidgets);
    expect(find.text('RFC 3339'), findsWidgets);
    expect(find.text('RFC 1123'), findsWidgets);
    expect(find.text('1970-01-01 00:00:00'), findsOneWidget);
    expect(find.text('1970-01-01T00:00:00+00:00'), findsOneWidget);
    expect(find.text('Thu, 01 Jan 1970 00:00:00 +0000'), findsOneWidget);
    expect(find.text('UTC+00:00'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('UTC-12:00').last);
    await tester.pumpAndSettle();

    expect(find.text('1969-12-31 12:00:00'), findsOneWidget);
    expect(find.text('UTC-12:00'), findsWidgets);
  });

  testWidgets('custom multi-pane tools expose adjustable splitters', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const horizontalHandle = ValueKey('split-editor-horizontal-resize-handle');
    const verticalHandle = ValueKey('split-editor-vertical-resize-handle');
    const tools = <String, List<ValueKey<String>>>{
      'base64_image_encode_decode': [horizontalHandle],
      'url_parser': [verticalHandle],
      'uuid_ulid_generate_decode': [horizontalHandle],
      'html_preview': [verticalHandle],
      'text_diff_checker': [horizontalHandle, verticalHandle],
      'lorem_ipsum_generator': [horizontalHandle],
      'qr_code_reader_generator': [verticalHandle],
      'string_inspector': [verticalHandle],
      'markdown_preview': [verticalHandle],
      'color_converter': [horizontalHandle],
      'random_string_generator': [horizontalHandle],
      'svg_to_css': [verticalHandle],
      'json_to_code': [horizontalHandle],
      'hash_generator': [horizontalHandle],
      'text_encryption': [horizontalHandle],
      'payload_embedder': [horizontalHandle],
      'jwt_debugger': [verticalHandle],
      'regexp_tester': [verticalHandle],
      'port_scanner': [horizontalHandle],
      'network_scanner': [horizontalHandle],
      'firewall_fingerprint': [horizontalHandle],
    };

    for (final entry in tools.entries) {
      final state = ToolState.inMemory();
      state.workspace.openTool(entry.key);
      await tester.pumpWidget(DevToolApp(state: state));
      await tester.pumpAndSettle();

      for (final handle in entry.value) {
        expect(find.byKey(handle), findsWidgets, reason: entry.key);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}

void expectRectClose(Rect actual, Rect expected) {
  expect(actual.left, moreOrLessEquals(expected.left));
  expect(actual.top, moreOrLessEquals(expected.top));
  expect(actual.width, moreOrLessEquals(expected.width));
  expect(actual.height, moreOrLessEquals(expected.height));
}

String _testLocalTimezoneLabel() {
  final now = DateTime.now();
  return '${now.timeZoneName} (${_testUtcOffset(now.timeZoneOffset)})';
}

String _testUtcOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final hours = absolute.inHours.toString().padLeft(2, '0');
  final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$minutes';
}

Uint8List _minimalPng() {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  final ihdr = <int>[
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x02,
    0x00,
    0x00,
    0x00,
  ];
  return Uint8List.fromList([
    ...signature,
    ..._pngChunkForTest('IHDR', ihdr),
    ..._pngChunkForTest('IEND', const []),
  ]);
}

Uint8List _minimalJpeg() {
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x04,
    0x4A,
    0x46,
    0xFF,
    0xD9,
  ]);
}

Uint8List _minimalPdf() {
  return Uint8List.fromList(
    latin1.encode('%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n'),
  );
}

List<int> _pngChunkForTest(String type, List<int> data) {
  return [
    ..._uint32ForTest(data.length),
    ...ascii.encode(type),
    ...data,
    0,
    0,
    0,
    0,
  ];
}

List<int> _uint32ForTest(int value) {
  final data = ByteData(4)..setUint32(0, value);
  return data.buffer.asUint8List();
}
