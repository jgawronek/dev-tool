import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class FirewallProbeResponse {
  const FirewallProbeResponse({
    required this.name,
    required this.url,
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.bodySnippet,
  });

  final String name;
  final Uri url;
  final int statusCode;
  final String reasonPhrase;
  final Map<String, String> headers;
  final String bodySnippet;

  String? header(String name) => headers[name.toLowerCase()];

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url.toString(),
    'status_code': statusCode,
    'reason': reasonPhrase,
    'headers': headers,
    'body_snippet': bodySnippet,
  };
}

class FirewallDetection {
  const FirewallDetection({
    required this.firewall,
    required this.manufacturer,
    required this.confidence,
    required this.evidence,
  });

  final String firewall;
  final String manufacturer;
  final int confidence;
  final List<String> evidence;

  Map<String, Object?> toJson() => {
    'firewall': firewall,
    'manufacturer': manufacturer,
    'confidence': confidence,
    'evidence': evidence,
  };
}

class FirewallFingerprintResult {
  const FirewallFingerprintResult({
    required this.target,
    required this.url,
    required this.detected,
    required this.genericDetected,
    required this.genericReason,
    required this.detections,
    required this.probes,
    required this.requestCount,
    required this.timestamp,
  });

  final String target;
  final Uri url;
  final bool detected;
  final bool genericDetected;
  final String genericReason;
  final List<FirewallDetection> detections;
  final List<FirewallProbeResponse> probes;
  final int requestCount;
  final DateTime timestamp;

  Map<String, Object?> toJson() => {
    'target': target,
    'url': url.toString(),
    'detected': detected,
    'generic_detected': genericDetected,
    'generic_reason': genericReason,
    'detections': detections.map((item) => item.toJson()).toList(),
    'request_count': requestCount,
    'timestamp': timestamp.toIso8601String(),
    'probes': probes.map((item) => item.toJson()).toList(),
  };

  String toJsonReport() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toTextReport() {
    final buffer = StringBuffer()
      ..writeln('Target: $target')
      ..writeln('URL: $url')
      ..writeln('Detected: ${detected ? 'yes' : 'no'}')
      ..writeln('Requests: $requestCount')
      ..writeln();

    if (detections.isEmpty) {
      buffer.writeln(
        genericDetected ? 'Generic firewall detected' : 'No WAF detected',
      );
      if (genericReason.isNotEmpty) buffer.writeln(genericReason);
    } else {
      for (final detection in detections) {
        buffer.writeln(
          '${detection.firewall} (${detection.manufacturer}) '
          '${detection.confidence}% confidence',
        );
        for (final evidence in detection.evidence) {
          buffer.writeln('  - $evidence');
        }
      }
    }

    buffer
      ..writeln()
      ..writeln('Probes:');
    for (final probe in probes) {
      buffer.writeln(
        '  ${probe.name}: HTTP ${probe.statusCode} ${probe.reasonPhrase}',
      );
    }
    return buffer.toString();
  }
}

class FirewallFingerprintService {
  FirewallFingerprintService({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;

  static const String xssPayload = '<script>alert("XSS");</script>';
  static const String sqliPayload =
      'UNION SELECT ALL FROM information_schema AND " or SLEEP(5) or "';
  static const String lfiPayload = '../../etc/passwd';
  static const String rcePayload =
      '/bin/cat /etc/passwd; ping 127.0.0.1; curl google.com';
  static const String xxePayload =
      '<!ENTITY xxe SYSTEM "file:///etc/shadow">]><pwn>&hack;</pwn>';

  static Uri normalizeUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) throw const FormatException('Enter a URL or host.');
    if (!value.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('Enter a valid URL or host.');
    }
    return uri.path.isEmpty ? uri.replace(path: '/') : uri;
  }

  Future<FirewallFingerprintResult> scan({
    required String target,
    bool findAll = false,
    bool followRedirects = true,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    final uri = normalizeUrl(target);
    final probes = <FirewallProbeResponse>[];

    final normal = await _request(
      'Normal',
      uri,
      timeout: timeout,
      followRedirects: followRedirects,
      headers: _browserHeaders,
    );
    probes.add(normal);

    final noUserAgent = await _request(
      'No User-Agent',
      uri,
      timeout: timeout,
      followRedirects: followRedirects,
      headers: const {'Accept': '*/*'},
    );
    probes.add(noUserAgent);

    final central = await _request(
      'Central attack',
      _attackUri(uri, {
        _randomParam(): xssPayload,
        _randomParam(): sqliPayload,
        _randomParam(): lfiPayload,
      }),
      timeout: timeout,
      followRedirects: followRedirects,
      headers: _browserHeaders,
    );
    probes.add(central);

    final attackProbes = <FirewallProbeResponse>[
      await _request(
        'XSS probe',
        _attackUri(uri, {_randomParam(): xssPayload}),
        timeout: timeout,
        followRedirects: followRedirects,
        headers: _browserHeaders,
      ),
      await _request(
        'SQLi probe',
        _attackUri(uri, {_randomParam(): sqliPayload}),
        timeout: timeout,
        followRedirects: followRedirects,
        headers: _browserHeaders,
      ),
      await _request(
        'LFI probe',
        _appendPath(uri, lfiPayload),
        timeout: timeout,
        followRedirects: followRedirects,
        headers: _browserHeaders,
      ),
      await _request(
        'XXE probe',
        _attackUri(uri, {_randomParam(): xxePayload}),
        timeout: timeout,
        followRedirects: followRedirects,
        headers: _browserHeaders,
      ),
      await _request(
        'RCE probe',
        _attackUri(uri, {_randomParam(): rcePayload}),
        timeout: timeout,
        followRedirects: followRedirects,
        headers: _browserHeaders,
      ),
    ];
    probes.addAll(attackProbes);

    final detections = _detectSignatures(probes, findAll: findAll);
    final genericReason = _genericReason(normal, noUserAgent, attackProbes);
    final genericDetected = genericReason.isNotEmpty;

    return FirewallFingerprintResult(
      target: target.trim(),
      url: uri,
      detected: detections.isNotEmpty || genericDetected,
      genericDetected: genericDetected,
      genericReason: genericReason,
      detections: detections,
      probes: probes,
      requestCount: probes.length,
      timestamp: _now(),
    );
  }

  void close() {
    _client.close();
  }

  Future<FirewallProbeResponse> _request(
    String name,
    Uri uri, {
    required Duration timeout,
    required bool followRedirects,
    required Map<String, String> headers,
  }) async {
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = followRedirects
        ..maxRedirects = 5
        ..headers.addAll(headers);
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(timeout);
      return FirewallProbeResponse(
        name: name,
        url: uri,
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase ?? '',
        headers: _normalizeHeaders(response.headers),
        bodySnippet: _truncate(response.body, 4096),
      );
    } on Object catch (error) {
      return FirewallProbeResponse(
        name: name,
        url: uri,
        statusCode: 0,
        reasonPhrase: 'Request failed',
        headers: const {},
        bodySnippet: error.toString(),
      );
    }
  }

  List<FirewallDetection> _detectSignatures(
    List<FirewallProbeResponse> probes, {
    required bool findAll,
  }) {
    final detections = <FirewallDetection>[];
    for (final signature in _signatures) {
      final evidence = <String>[];
      var score = 0;
      for (final rule in signature.rules) {
        for (final probe in probes) {
          if (rule.matches(probe)) {
            evidence.add('${probe.name}: ${rule.evidence}');
            score += rule.weight;
            break;
          }
        }
      }
      if (score >= signature.threshold) {
        detections.add(
          FirewallDetection(
            firewall: signature.firewall,
            manufacturer: signature.manufacturer,
            confidence: score.clamp(0, 100),
            evidence: evidence,
          ),
        );
        if (!findAll) break;
      }
    }
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    return detections;
  }

  String _genericReason(
    FirewallProbeResponse normal,
    FirewallProbeResponse noUserAgent,
    List<FirewallProbeResponse> attacks,
  ) {
    final reasons = <String>[];
    final baselineAllowed = normal.statusCode >= 200 && normal.statusCode < 400;
    if (baselineAllowed && _blockedStatusCodes.contains(noUserAgent.statusCode)) {
      reasons.add(
        'Request without a User-Agent was blocked: normal ${normal.statusCode}, modified ${noUserAgent.statusCode}.',
      );
    }
    for (final attack in attacks) {
      if (baselineAllowed && _blockedStatusCodes.contains(attack.statusCode)) {
        reasons.add(
          '${attack.name} returned blocking status ${attack.statusCode} after normal ${normal.statusCode}.',
        );
        break;
      }
      if (_blockBodyPattern.hasMatch(attack.bodySnippet)) {
        reasons.add('${attack.name} returned a block page pattern.');
        break;
      }
    }
    return reasons.join('\n');
  }

  static Uri _attackUri(Uri uri, Map<String, String> params) {
    final query = Map<String, String>.from(uri.queryParameters)..addAll(params);
    return uri.replace(queryParameters: query);
  }

  static Uri _appendPath(Uri uri, String suffix) {
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: '$path$suffix');
  }

  static String _randomParam() {
    const chars = 'abcdefghijklmnopqrstuvwxyz';
    final random = Random();
    return String.fromCharCodes(
      List<int>.generate(
        8,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  static Map<String, String> _normalizeHeaders(Map<String, String> headers) {
    return {
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
  }

  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 DevUtils/1.0',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  static final RegExp _blockBodyPattern = RegExp(
    r'(access denied|request blocked|security policy|malicious request|not acceptable|forbidden|captcha|incident id|ray id)',
    caseSensitive: false,
  );

  static const Set<int> _blockedStatusCodes = {
    401,
    403,
    406,
    419,
    429,
    501,
    503,
  };

  static final List<_WafSignature> _signatures = [
    _WafSignature(
      firewall: 'Cloudflare',
      manufacturer: 'Cloudflare Inc.',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'cloudflare', 55),
        _HeaderRule('cf-ray', r'.+', 70),
        _HeaderRule('cf-cache-status', r'.+', 45),
        _HeaderRule('set-cookie', r'(__cf_bm|cf_clearance)', 55),
        _BodyRule(r'(attention required|cloudflare ray id|cf-error-code)', 40),
      ],
    ),
    _WafSignature(
      firewall: 'AWS WAF / CloudFront',
      manufacturer: 'Amazon',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'cloudfront', 45),
        _HeaderRule('x-amz-cf-id', r'.+', 60),
        _HeaderRule('x-amz-cf-pop', r'.+', 45),
        _BodyRule(r'(request blocked|generated by cloudfront)', 45),
      ],
    ),
    _WafSignature(
      firewall: 'Azure Front Door / Application Gateway',
      manufacturer: 'Microsoft',
      threshold: 50,
      rules: [
        _HeaderRule('x-azure-ref', r'.+', 65),
        _HeaderRule('x-msedge-ref', r'.+', 65),
        _HeaderRule(
          'server',
          r'(microsoft-azure-application-gateway|azure)',
          55,
        ),
        _HeaderRule(
          'set-cookie',
          r'(ApplicationGatewayAffinity|ARRAffinity)',
          50,
        ),
      ],
    ),
    _WafSignature(
      firewall: 'Kona SiteDefender',
      manufacturer: 'Akamai',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'akamai', 50),
        _HeaderRule('x-akamai-transformed', r'.+', 60),
        _HeaderRule('akamai-origin-hop', r'.+', 50),
        _BodyRule(r'(akamai|reference #[0-9a-f.]+)', 35),
      ],
    ),
    _WafSignature(
      firewall: 'Fastly',
      manufacturer: 'Fastly CDN',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'fastly', 65),
        _HeaderRule('x-served-by', r'cache-', 35),
        _HeaderRule('x-cache', r'(hit|miss)', 25),
        _HeaderRule('fastly-debug-digest', r'.+', 55),
      ],
    ),
    _WafSignature(
      firewall: 'Incapsula / SecureSphere',
      manufacturer: 'Imperva Inc.',
      threshold: 50,
      rules: [
        _HeaderRule('set-cookie', r'(incap_ses|visid_incap)', 65),
        _HeaderRule('x-iinfo', r'.+', 60),
        _BodyRule(r'(incapsula|imperva|request unsuccessful)', 45),
      ],
    ),
    _WafSignature(
      firewall: 'Sucuri CloudProxy',
      manufacturer: 'Sucuri Inc.',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'sucuri', 60),
        _HeaderRule('x-sucuri-id', r'.+', 70),
        _HeaderRule('x-sucuri-cache', r'.+', 50),
        _BodyRule(r'sucuri website firewall', 55),
      ],
    ),
    _WafSignature(
      firewall: 'BIG-IP ASM/APM/LTM',
      manufacturer: 'F5 Networks',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'big-ip|f5', 60),
        _HeaderRule('set-cookie', r'(BIGipServer|F5_ST|TS[a-zA-Z0-9]{3,})', 60),
        _BodyRule(r'the requested url was rejected', 45),
      ],
    ),
    _WafSignature(
      firewall: 'Barracuda',
      manufacturer: 'Barracuda Networks',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'barracuda', 65),
        _HeaderRule('set-cookie', r'barra_counter_session', 55),
        _BodyRule(r'barracuda', 40),
      ],
    ),
    _WafSignature(
      firewall: 'ModSecurity',
      manufacturer: 'SpiderLabs',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'mod_security|modsecurity', 65),
        _BodyRule(r'(mod_security|modsecurity|not acceptable)', 55),
        _StatusRule(406, 25),
      ],
    ),
    _WafSignature(
      firewall: 'FortiWeb / FortiGate',
      manufacturer: 'Fortinet',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'fortiweb|fortigate', 65),
        _HeaderRule('set-cookie', r'(FORTIWAFSID|cookiesession1)', 55),
        _BodyRule(r'fortinet|fortiweb', 45),
      ],
    ),
    _WafSignature(
      firewall: 'Palo Alto Next Gen Firewall',
      manufacturer: 'Palo Alto Networks',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'palo alto', 65),
        _BodyRule(r'(palo alto|url filtering|threat prevention)', 55),
      ],
    ),
    _WafSignature(
      firewall: 'Google Cloud Armor',
      manufacturer: 'Google Cloud',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'google frontend|gfe', 45),
        _HeaderRule('x-cloud-trace-context', r'.+', 30),
        _BodyRule(r'(cloud armor|your client does not have permission)', 55),
      ],
    ),
    _WafSignature(
      firewall: 'Vercel WAF',
      manufacturer: 'Vercel',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'vercel', 60),
        _HeaderRule('x-vercel-id', r'.+', 70),
        _HeaderRule('x-vercel-cache', r'.+', 45),
      ],
    ),
    _WafSignature(
      firewall: 'NetScaler AppFirewall',
      manufacturer: 'Citrix Systems',
      threshold: 50,
      rules: [
        _HeaderRule('set-cookie', r'NSC_', 60),
        _HeaderRule('server', r'netscaler|citrix', 60),
        _BodyRule(r'citrix application firewall', 55),
      ],
    ),
    _WafSignature(
      firewall: 'StackPath',
      manufacturer: 'StackPath',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'stackpath', 65),
        _HeaderRule('x-sp-url', r'.+', 55),
        _BodyRule(r'stackpath', 40),
      ],
    ),
    _WafSignature(
      firewall: 'DDoS-GUARD',
      manufacturer: 'DDOS-GUARD CORP.',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'ddos-guard', 70),
        _HeaderRule('set-cookie', r'__ddg', 65),
        _BodyRule(r'ddos-guard', 55),
      ],
    ),
    _WafSignature(
      firewall: 'Safeline',
      manufacturer: 'Chaitin Tech.',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'safeline', 65),
        _HeaderRule('set-cookie', r'sl-session|safeline', 55),
        _BodyRule(r'safeline|chaitin', 55),
      ],
    ),
    _WafSignature(
      firewall: 'Wordfence',
      manufacturer: 'Defiant',
      threshold: 50,
      rules: [
        _HeaderRule('set-cookie', r'(wfvt_|wordfence_verifiedHuman)', 60),
        _BodyRule(r'(wordfence|generated by wordfence)', 65),
      ],
    ),
    _WafSignature(
      firewall: 'LiteSpeed',
      manufacturer: 'LiteSpeed Technologies',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'litespeed', 65),
        _HeaderRule('x-litespeed-cache', r'.+', 55),
        _HeaderRule('set-cookie', r'_lscache_vary', 50),
      ],
    ),
    _WafSignature(
      firewall: 'Open-Resty Lua Nginx',
      manufacturer: 'FLOSS',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'openresty', 70),
        _HeaderRule('x-openresty', r'.+', 55),
      ],
    ),
    _WafSignature(
      firewall: 'NAXSI',
      manufacturer: 'NBS Systems',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'naxsi', 65),
        _BodyRule(r'naxsi|blocked by naxsi', 55),
      ],
    ),
    _WafSignature(
      firewall: 'Wallarm',
      manufacturer: 'Wallarm Inc.',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'wallarm', 65),
        _HeaderRule('set-cookie', r'wallarm', 55),
        _BodyRule(r'wallarm', 55),
      ],
    ),
    _WafSignature(
      firewall: 'Reblaze',
      manufacturer: 'Reblaze',
      threshold: 50,
      rules: [
        _HeaderRule('server', r'reblaze', 65),
        _HeaderRule('set-cookie', r'rbzid|rbzsessionid', 60),
        _BodyRule(r'reblaze', 55),
      ],
    ),
    _WafSignature(
      firewall: 'PerimeterX',
      manufacturer: 'PerimeterX',
      threshold: 50,
      rules: [
        _HeaderRule('set-cookie', r'(_px|pxvid|pxcts)', 65),
        _BodyRule(r'(perimeterx|px-captcha|_pxAppId)', 60),
      ],
    ),
    _WafSignature(
      firewall: 'DataDome',
      manufacturer: 'DataDome',
      threshold: 50,
      rules: [
        _HeaderRule('set-cookie', r'datadome', 65),
        _BodyRule(r'datadome|geo\.captcha-delivery\.com', 60),
      ],
    ),
  ];
}

class _WafSignature {
  const _WafSignature({
    required this.firewall,
    required this.manufacturer,
    required this.threshold,
    required this.rules,
  });

  final String firewall;
  final String manufacturer;
  final int threshold;
  final List<_WafRule> rules;
}

abstract class _WafRule {
  const _WafRule(this.weight, this.evidence);

  final int weight;
  final String evidence;

  bool matches(FirewallProbeResponse probe);
}

class _HeaderRule extends _WafRule {
  _HeaderRule(this.header, String pattern, int weight)
    : _pattern = RegExp(pattern, caseSensitive: false),
      super(
        weight,
        '${header == 'set-cookie' ? 'cookie name' : header} matches /$pattern/',
      );

  final String header;
  final RegExp _pattern;

  // HTTP clients can combine Set-Cookie fields. An Expires date also has a
  // comma, so only accept a comma followed by a cookie name and equals sign.
  static final _cookieNames = RegExp(
    r"(?:^|,)\s*([!#$%&'*+.^_`|~0-9A-Za-z-]+)=",
  );

  @override
  bool matches(FirewallProbeResponse probe) {
    final value = probe.header(header);
    if (value == null) return false;
    if (header == 'set-cookie') {
      return _cookieNames
          .allMatches(value)
          .any((match) => _pattern.matchAsPrefix(match.group(1)!) != null);
    }
    return _pattern.hasMatch(value);
  }
}

class _BodyRule extends _WafRule {
  _BodyRule(String pattern, int weight)
    : _pattern = RegExp(pattern, caseSensitive: false),
      super(weight, 'body matches /$pattern/');

  final RegExp _pattern;

  @override
  bool matches(FirewallProbeResponse probe) {
    return _pattern.hasMatch(probe.bodySnippet);
  }
}

class _StatusRule extends _WafRule {
  const _StatusRule(this.statusCode, int weight)
    : super(weight, 'status code matches');

  final int statusCode;

  @override
  bool matches(FirewallProbeResponse probe) {
    return probe.statusCode == statusCode;
  }
}

String _truncate(String value, int maxLength) {
  if (value.length <= maxLength) return value;
  return value.substring(0, maxLength);
}
