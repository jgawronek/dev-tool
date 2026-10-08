import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/services/subnet_service.dart';
import 'package:dev_tool/ui/widgets.dart';

import '../helpers/tool_harness.dart';

void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body,
) {
  testWidgets(description, (tester) async {
    final h = ToolHarness(tester);
    await h.open(toolId);
    await body(h);
  });
}

void main() {
  group('tool view', () {
    /// Clear lives in the editor's right-click menu, not the toolbar.
    Future<void> editorMenu(ToolHarness h, String item) async {
      await h.tester.tapAt(
        h.tester.getCenter(find.byType(EditorPane).first),
        buttons: kSecondaryMouseButton,
      );
      await h.settle();
      await h.tap(item);
      await h.settle();
    }

    /// Drives the single address editor the tool exposes.
    Future<void> enterAddress(ToolHarness h, String value) =>
        h.enter('192.168.1.10/24, 2001:db8::1/64, 10.0.0.0/8...', text: value);

    toolTest('computes an IPv4 subnet as you type', 'subnet_calculator',
        (h) async {
      await enterAddress(h, '192.168.1.10/24');
      final output = h.text('Subnet details...');
      expect(output, contains('192.168.1.0/24'));
      expect(output, contains('255.255.255.0'));
      expect(output, contains('Usable hosts        254'));
    });

    toolTest('computes an IPv6 subnet', 'subnet_calculator', (h) async {
      await enterAddress(h, '2001:db8::1/64');
      expect(h.text('Subnet details...'), contains('2001:db8::'));
    });

    toolTest('shows a readable error for a bad address', 'subnet_calculator',
        (h) async {
      await enterAddress(h, '999.1.1.1');
      expect(find.textContaining('outside 0-255'), findsOneWidget);
    });

    toolTest('defaults to a /32 host route', 'subnet_calculator', (h) async {
      await enterAddress(h, '8.8.8.8');
      expect(h.text('Subnet details...'), contains('255.255.255.255'));
    });

    toolTest('clearing empties both panes', 'subnet_calculator', (h) async {
      await enterAddress(h, '192.168.1.10/24');
      await editorMenu(h, 'Clear');
      expect(h.text('Subnet details...'), isEmpty);
    });
  });

  group('IPv4', () {
    test('a /24 private range', () {
      final info = calculateSubnet('192.168.1.10/24').info!;
      expect(info.networkAddress, '192.168.1.0');
      expect(info.netmask, '255.255.255.0');
      expect(info.wildcardMask, '0.0.0.255');
      expect(info.broadcastAddress, '192.168.1.255');
      expect(info.firstHost, '192.168.1.1');
      expect(info.lastHost, '192.168.1.254');
      expect(info.usableHosts, '254');
      expect(info.totalAddresses, '256');
      expect(info.isPrivate, isTrue);
      expect(info.ipClass, 'C private (192.168)');
    });

    test('a /30 point-to-point link', () {
      final info = calculateSubnet('172.16.5.4/30').info!;
      expect(info.networkAddress, '172.16.5.4');
      expect(info.netmask, '255.255.255.252');
      expect(info.broadcastAddress, '172.16.5.7');
      expect(info.firstHost, '172.16.5.5');
      expect(info.lastHost, '172.16.5.6');
      expect(info.usableHosts, '2');
    });

    test('a /8 block reports millions of hosts', () {
      final info = calculateSubnet('10.0.0.0/8').info!;
      expect(info.networkAddress, '10.0.0.0');
      expect(info.netmask, '255.0.0.0');
      expect(info.broadcastAddress, '10.255.255.255');
      expect(info.usableHosts, '16,777,214');
      expect(info.isPrivate, isTrue);
      expect(info.ipClass, 'A (1-126)');
    });

    test('a /27 near the top of the range', () {
      final info = calculateSubnet('203.0.113.7/27').info!;
      expect(info.networkAddress, '203.0.113.0');
      expect(info.netmask, '255.255.255.224');
      expect(info.broadcastAddress, '203.0.113.31');
      expect(info.usableHosts, '30');
      expect(info.isPrivate, isFalse);
      expect(info.ipClass, 'C (192-223)');
    });

    test('a /32 host route has one usable address', () {
      final info = calculateSubnet('1.2.3.4/32').info!;
      expect(info.networkAddress, '1.2.3.4');
      expect(info.netmask, '255.255.255.255');
      expect(info.usableHosts, '1');
      expect(info.firstHost, '1.2.3.4');
      expect(info.lastHost, '1.2.3.4');
    });

    test('an omitted prefix defaults to a host route', () {
      final info = calculateSubnet('8.8.8.8').info!;
      expect(info.prefixLength, 32);
      expect(info.networkAddress, '8.8.8.8');
    });

    test('loopback, multicast and link-local are flagged', () {
      expect(calculateSubnet('127.0.0.1/8').info!.isLoopback, isTrue);
      expect(calculateSubnet('224.0.0.1/4').info!.isMulticast, isTrue);
      expect(calculateSubnet('169.254.1.1/16').info!.isLinkLocal, isTrue);
      expect(calculateSubnet('192.168.0.1/16').info!.isPrivate, isTrue);
      expect(calculateSubnet('172.16.0.1/12').info!.isPrivate, isTrue);
      expect(calculateSubnet('8.8.8.8/8').info!.isPrivate, isFalse);
    });

    test('a /31 has no network or broadcast reservation', () {
      final info = calculateSubnet('192.168.1.0/31').info!;
      expect(info.netmask, '255.255.255.254');
      expect(info.broadcastAddress, '192.168.1.1');
      expect(info.usableHosts, '2');
      expect(info.networkHosts, contains('n/a'));
    });

    test('malformed IPv4 is rejected with a specific message', () {
      expect(calculateSubnet('999.1.1.1/24').error, contains('outside 0-255'));
      expect(calculateSubnet('192.168.1/24').error, contains('four octets'));
      expect(calculateSubnet('192.168.1.1/33').error, contains('0-32'));
      expect(calculateSubnet('192.168.1.1/abc').error, contains('must be a number'));
      expect(calculateSubnet('a.b.c.d').error, contains('must be numbers'));
      expect(calculateSubnet('').error, contains('Enter an IP address'));
    });
  });

  group('IPv6', () {
    test('documentation prefix with /64', () {
      final info = calculateSubnet('2001:db8::1/64').info!;
      expect(info.version, 6);
      expect(info.networkAddress, '2001:db8::');
      expect(info.netmask, 'ffff:ffff:ffff:ffff::');
      expect(info.wildcardMask, '::ffff:ffff:ffff:ffff');
    });

    test('link-local /10', () {
      final info = calculateSubnet('fe80::1/10').info!;
      expect(info.networkAddress, 'fe80::');
      expect(info.netmask, 'ffc0::');
      expect(info.isLinkLocal, isTrue);
    });

    test('loopback /128', () {
      final info = calculateSubnet('::1/128').info!;
      expect(info.networkAddress, '::1');
      expect(info.netmask, 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff');
      expect(info.wildcardMask, '::');
      expect(info.isLoopback, isTrue);
    });

    test('a /32 documentation prefix', () {
      final info = calculateSubnet('2001:db8::/32').info!;
      expect(info.networkAddress, '2001:db8::');
      expect(info.netmask, 'ffff:ffff::');
    });

    test('unique local addresses are flagged private', () {
      expect(calculateSubnet('fd00::1/8').info!.isPrivate, isTrue);
      expect(calculateSubnet('2001:db8::1/32').info!.isPrivate, isFalse);
    });

    test('multicast prefix is flagged', () {
      expect(calculateSubnet('ff02::1/8').info!.isMulticast, isTrue);
    });

    test('embedded IPv4 notation parses', () {
      final info = calculateSubnet('::ffff:192.168.1.1/128').info;
      expect(info, isNotNull);
      expect(info!.networkAddress, contains('c0a8'));
    });

    test('malformed IPv6 is rejected', () {
      expect(calculateSubnet('2001:db8::/129').error, contains('0-128'));
      expect(calculateSubnet('gggg::1/64').error, contains('Not a valid IPv6'));
      expect(calculateSubnet('1:2:3:4:5:6:7:8:9/64').error, contains('Not a valid'));
      expect(calculateSubnet('1::2::3/64').error, contains('Not a valid'));
    });

    test('RFC 5952 compression rules', () {
      expect(calculateSubnet('2001:0db8:0000:0000:0000:0000:0000:0001/128').info!.networkAddress, '2001:db8::1');
      // A single zero group is written out rather than compressed.
      expect(calculateSubnet('1:0:2:3:4:5:6:7/128').info!.networkAddress, '1:0:2:3:4:5:6:7');
    });
  });

  group('reporting', () {
    test('the report lists the key fields', () {
      final report = calculateSubnet('192.168.1.10/24').info!.toReport();
      expect(report, contains('192.168.1.0/24'));
      expect(report, contains('255.255.255.0'));
      expect(report, contains('Usable hosts'));
      expect(report, contains('254'));
    });

    test('enumeration refuses an unhelpfully wide prefix', () {
      final info = calculateSubnet('10.0.0.0/8').info!;
      final subnets = enumerateSubnets(info);
      expect(subnets.single, contains('too large to enumerate'));
    });
  });
}