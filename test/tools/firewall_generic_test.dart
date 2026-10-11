import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dev_tool/services/firewall_fingerprint_service.dart';

void main() {
  test('ordinary missing attack path and changed server header are not WAF proof', () async {
    final service = FirewallFingerprintService(client: MockClient((r) async =>
      http.Response(r.url.path == '/' ? 'home' : 'missing page', r.url.path == '/' ? 200 : 404,
        headers: {'server': r.url.path == '/' ? 'normal-web' : 'error-web'})));
    addTearDown(service.close);
    final result = await service.scan(target: 'example.com', findAll: true);
    expect(result.genericDetected, isFalse);
    expect(result.detected, isFalse);
  });
  test('blocked probe after successful baseline is generic evidence', () async {
    final service = FirewallFingerprintService(client: MockClient((r) async =>
      http.Response('response', r.url.hasQuery ? 403 : 200)));
    addTearDown(service.close);
    final result = await service.scan(target: 'example.com', findAll: true);
    expect(result.genericDetected, isTrue);
    expect(result.genericReason, contains('403'));
  });
  test('baseline outage does not turn every probe into WAF evidence', () async {
    final service = FirewallFingerprintService(client: MockClient((r) async =>
      http.Response('temporarily unavailable', 503)));
    addTearDown(service.close);
    final result = await service.scan(target: 'example.com', findAll: true);
    expect(result.detected, isFalse);
  });
}
