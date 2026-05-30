import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

typedef CnameLookup = Future<List<String>> Function(String host);

enum TakeoverConfidence {
  safe,
  low,
  medium,
  high;

  String get label => switch (this) {
    TakeoverConfidence.safe => 'SAFE',
    TakeoverConfidence.low => 'LOW',
    TakeoverConfidence.medium => 'MEDIUM',
    TakeoverConfidence.high => 'HIGH',
  };

  int get score => switch (this) {
    TakeoverConfidence.safe => 0,
    TakeoverConfidence.low => 1,
    TakeoverConfidence.medium => 2,
    TakeoverConfidence.high => 3,
  };
}

class TakeoverScanProgress {
  const TakeoverScanProgress({
    required this.scanned,
    required this.total,
    required this.potentialCount,
  });

  final int scanned;
  final int total;
  final int potentialCount;

  double get ratio => total == 0 ? 0 : scanned / total;
}

class TakeoverHttpProbe {
  const TakeoverHttpProbe({
    required this.url,
    this.statusCode,
    this.body = '',
    this.headers = const {},
    this.error,
  });

  final Uri url;
  final int? statusCode;
  final String body;
  final Map<String, String> headers;
  final String? error;

  bool get responded => statusCode != null;

  String get searchableText {
    final buffer = StringBuffer(body);
    for (final entry in headers.entries) {
      buffer.write('\n${entry.key}: ${entry.value}');
    }
    return buffer.toString().toLowerCase();
  }

  Map<String, Object?> toJson() => {
    'url': url.toString(),
    'status_code': statusCode,
    'error': error,
  };
}

class TakeoverScanResult {
  const TakeoverScanResult({
    required this.host,
    required this.service,
    required this.confidence,
    required this.evidence,
    required this.cnameChain,
    required this.probes,
    required this.matchedBodyIndicator,
    required this.matchedCnameIndicator,
    required this.scannedAt,
  });

  final String host;
  final String service;
  final TakeoverConfidence confidence;
  final String evidence;
  final List<String> cnameChain;
  final List<TakeoverHttpProbe> probes;
  final String? matchedBodyIndicator;
  final String? matchedCnameIndicator;
  final DateTime scannedAt;

  bool get isPotential => confidence != TakeoverConfidence.safe;

  int? get statusCode {
    for (final probe in probes) {
      if (probe.statusCode != null) return probe.statusCode;
    }
    return null;
  }

  Uri? get primaryUrl {
    for (final probe in probes) {
      if (probe.statusCode != null) return probe.url;
    }
    return probes.isEmpty ? null : probes.first.url;
  }

  Map<String, Object?> toJson() => {
    'host': host,
    'service': service,
    'confidence': confidence.label,
    'evidence': evidence,
    'cname_chain': cnameChain,
    'matched_body_indicator': matchedBodyIndicator,
    'matched_cname_indicator': matchedCnameIndicator,
    'status_code': statusCode,
    'url': primaryUrl?.toString(),
    'probes': probes.map((probe) => probe.toJson()).toList(),
    'scanned_at': scannedAt.toIso8601String(),
  };
}

class TakeoverScanSummary {
  const TakeoverScanSummary({
    required this.targets,
    required this.startedAt,
    required this.endedAt,
    required this.results,
  });

  final List<String> targets;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<TakeoverScanResult> results;

  Duration get duration => endedAt.difference(startedAt);

  int get potentialCount =>
      results.where((result) => result.isPotential).length;

  List<TakeoverScanResult> get potentialResults =>
      results.where((result) => result.isPotential).toList();

  Map<String, Object?> toJson() => {
    'targets': targets,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt.toIso8601String(),
    'duration_ms': duration.inMilliseconds,
    'total': results.length,
    'potential': potentialCount,
    'results': results.map((result) => result.toJson()).toList(),
  };

  String toJsonReport() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toCsvReport() {
    final buffer = StringBuffer();
    buffer.writeln(
      'host,service,confidence,status_code,url,cname_chain,evidence',
    );
    for (final result in results) {
      buffer.writeln(
        [
          result.host,
          result.service,
          result.confidence.label,
          result.statusCode?.toString() ?? '',
          result.primaryUrl?.toString() ?? '',
          result.cnameChain.join(' > '),
          result.evidence,
        ].map(_csvEscape).join(','),
      );
    }
    return buffer.toString();
  }
}

class SubdomainTakeoverService {
  SubdomainTakeoverService({
    http.Client? client,
    CnameLookup? cnameLookup,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _cnameLookup = cnameLookup ?? _lookupCnameWithDig,
       _now = now ?? DateTime.now;

  final http.Client _client;
  final CnameLookup _cnameLookup;
  final DateTime Function() _now;

  static List<String> parseTargets(String input) {
    final targets = <String>{};
    final parts = input
        .split(RegExp(r'[\s,;]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);

    for (final part in parts) {
      final host = normalizeHost(part);
      targets.add(host);
    }

    if (targets.isEmpty) {
      throw const FormatException('Enter at least one host to scan.');
    }

    return targets.toList()..sort(_compareHosts);
  }

  static String normalizeHost(String input) {
    var value = input.trim().toLowerCase();
    if (value.isEmpty) {
      throw const FormatException('Enter a host to scan.');
    }

    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      value = uri.host;
    }

    value = value
        .replaceFirst(RegExp(r'^\*\.'), '')
        .replaceAll(RegExp(r':\d+$'), '')
        .replaceAll(RegExp(r'\.$'), '');

    if (!_domainPattern.hasMatch(value) || value.contains('..')) {
      throw FormatException('Invalid host: $input');
    }

    return value;
  }

  Future<TakeoverScanSummary> scanText(
    String input, {
    Duration timeout = const Duration(seconds: 8),
    int concurrency = 8,
    void Function(TakeoverScanProgress progress)? onProgress,
  }) {
    return scanTargets(
      parseTargets(input),
      timeout: timeout,
      concurrency: concurrency,
      onProgress: onProgress,
    );
  }

  Future<TakeoverScanSummary> scanTargets(
    List<String> targets, {
    Duration timeout = const Duration(seconds: 8),
    int concurrency = 8,
    void Function(TakeoverScanProgress progress)? onProgress,
  }) async {
    final normalized = targets.map(normalizeHost).toSet().toList()
      ..sort(_compareHosts);
    if (normalized.isEmpty) {
      throw const FormatException('Enter at least one host to scan.');
    }

    final startedAt = _now();
    final results = <TakeoverScanResult>[];
    var nextIndex = 0;
    var scanned = 0;
    var potential = 0;
    final safeConcurrency = concurrency < 1
        ? 1
        : concurrency > 32
        ? 32
        : concurrency;
    final workerCount = safeConcurrency > normalized.length
        ? normalized.length
        : safeConcurrency;

    Future<void> worker() async {
      while (true) {
        if (nextIndex >= normalized.length) return;
        final host = normalized[nextIndex++];
        final result = await scanHost(host, timeout: timeout);
        results.add(result);
        scanned++;
        if (result.isPotential) potential++;
        onProgress?.call(
          TakeoverScanProgress(
            scanned: scanned,
            total: normalized.length,
            potentialCount: potential,
          ),
        );
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    results.sort((a, b) {
      final confidence = b.confidence.score.compareTo(a.confidence.score);
      if (confidence != 0) return confidence;
      return _compareHosts(a.host, b.host);
    });

    return TakeoverScanSummary(
      targets: normalized,
      startedAt: startedAt,
      endedAt: _now(),
      results: results,
    );
  }

  Future<TakeoverScanResult> scanHost(
    String input, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final host = normalizeHost(input);
    final cnameChain = await _safeCnameLookup(host, timeout);
    final probes = <TakeoverHttpProbe>[
      await _request(Uri(scheme: 'https', host: host), timeout),
      await _request(Uri(scheme: 'http', host: host), timeout),
    ];

    final matches = <_FingerprintMatch>[];
    for (final fingerprint in _fingerprints) {
      final cnameIndicator = _findCnameIndicator(fingerprint, cnameChain);
      final bodyIndicator =
          fingerprint.bodyRequiresCname && cnameIndicator == null
          ? null
          : _findBodyIndicator(fingerprint, probes);
      if (bodyIndicator == null && cnameIndicator == null) continue;
      matches.add(
        _FingerprintMatch(
          fingerprint: fingerprint,
          bodyIndicator: bodyIndicator,
          cnameIndicator: cnameIndicator,
        ),
      );
    }

    if (matches.isEmpty) {
      final responded = probes.any((probe) => probe.responded);
      return TakeoverScanResult(
        host: host,
        service: 'No match',
        confidence: TakeoverConfidence.safe,
        evidence: responded
            ? 'No takeover fingerprint matched.'
            : 'No HTTP response and no provider CNAME matched.',
        cnameChain: cnameChain,
        probes: probes,
        matchedBodyIndicator: null,
        matchedCnameIndicator: null,
        scannedAt: _now(),
      );
    }

    matches.sort((a, b) => b.confidence.score.compareTo(a.confidence.score));
    final best = matches.first;
    return TakeoverScanResult(
      host: host,
      service: best.fingerprint.service,
      confidence: best.confidence,
      evidence: best.evidence,
      cnameChain: cnameChain,
      probes: probes,
      matchedBodyIndicator: best.bodyIndicator,
      matchedCnameIndicator: best.cnameIndicator,
      scannedAt: _now(),
    );
  }

  Future<List<String>> _safeCnameLookup(String host, Duration timeout) async {
    try {
      final cnames = await _cnameLookup(host).timeout(timeout);
      return cnames
          .map((cname) => cname.trim().toLowerCase())
          .where((cname) => cname.isNotEmpty)
          .map((cname) => cname.replaceAll(RegExp(r'\.$'), ''))
          .toSet()
          .toList()
        ..sort();
    } on Object {
      return const <String>[];
    }
  }

  Future<TakeoverHttpProbe> _request(Uri uri, Duration timeout) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              'User-Agent':
                  'DevUtils takeover scanner (+https://github.com/jgawronek/dev-tools)',
              'Accept': 'text/html,application/xhtml+xml,text/plain,*/*',
            },
          )
          .timeout(timeout);
      return TakeoverHttpProbe(
        url: uri,
        statusCode: response.statusCode,
        body: response.body,
        headers: response.headers,
      );
    } on Object catch (error) {
      return TakeoverHttpProbe(url: uri, error: _shortError(error));
    }
  }

  void close() {
    _client.close();
  }
}

class TakeoverFingerprint {
  const TakeoverFingerprint({
    required this.service,
    required this.bodyIndicators,
    required this.cnameIndicators,
    this.bodyRequiresCname = false,
  });

  final String service;
  final List<String> bodyIndicators;
  final List<String> cnameIndicators;
  final bool bodyRequiresCname;
}

class _FingerprintMatch {
  const _FingerprintMatch({
    required this.fingerprint,
    required this.bodyIndicator,
    required this.cnameIndicator,
  });

  final TakeoverFingerprint fingerprint;
  final String? bodyIndicator;
  final String? cnameIndicator;

  TakeoverConfidence get confidence {
    if (bodyIndicator != null && cnameIndicator != null) {
      return TakeoverConfidence.high;
    }
    if (bodyIndicator != null) return TakeoverConfidence.medium;
    return TakeoverConfidence.low;
  }

  String get evidence {
    if (bodyIndicator != null && cnameIndicator != null) {
      return 'Provider CNAME and unavailable-service page both matched.';
    }
    if (bodyIndicator != null) {
      return 'Unavailable-service page matched. Confirm DNS ownership before remediation.';
    }
    return 'Provider CNAME matched, but the HTTP response was inconclusive.';
  }
}

String? _findBodyIndicator(
  TakeoverFingerprint fingerprint,
  List<TakeoverHttpProbe> probes,
) {
  for (final indicator in fingerprint.bodyIndicators) {
    final normalized = indicator.toLowerCase();
    for (final probe in probes) {
      if (probe.searchableText.contains(normalized)) return indicator;
    }
  }
  return null;
}

String? _findCnameIndicator(
  TakeoverFingerprint fingerprint,
  List<String> cnameChain,
) {
  for (final indicator in fingerprint.cnameIndicators) {
    final normalized = indicator.toLowerCase();
    for (final cname in cnameChain) {
      if (cname.contains(normalized)) return indicator;
    }
  }
  return null;
}

Future<List<String>> _lookupCnameWithDig(String host) async {
  try {
    final result = await Process.run('dig', [
      '+short',
      'CNAME',
      host,
    ]).timeout(const Duration(seconds: 4));
    if (result.exitCode != 0) return const <String>[];
    return const LineSplitter()
        .convert(result.stdout.toString())
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  } on Object {
    return const <String>[];
  }
}

String _shortError(Object error) {
  if (error is TimeoutException) return 'Timed out';
  if (error is SocketException) return error.message;
  if (error is http.ClientException) return error.message;
  if (error is HandshakeException) return 'TLS handshake failed';
  return error.toString();
}

int _compareHosts(String a, String b) {
  final depth = a.split('.').length.compareTo(b.split('.').length);
  if (depth != 0) return depth;
  return a.compareTo(b);
}

String _csvEscape(Object? value) {
  final text = '${value ?? ''}';
  if (!text.contains(',') && !text.contains('"') && !text.contains('\n')) {
    return text;
  }
  return '"${text.replaceAll('"', '""')}"';
}

final _domainPattern = RegExp(
  r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
);

const _fingerprints = <TakeoverFingerprint>[
  TakeoverFingerprint(
    service: 'AWS S3',
    bodyIndicators: ['The specified bucket does not exist'],
    cnameIndicators: ['s3.amazonaws.com', 's3-website', 'amazonaws.com'],
  ),
  TakeoverFingerprint(
    service: 'Bitbucket',
    bodyIndicators: ['Repository not found'],
    cnameIndicators: ['bitbucket.io'],
  ),
  TakeoverFingerprint(
    service: 'GitHub Pages',
    bodyIndicators: [
      "There isn't a GitHub Pages site here",
      'Github Pages site here',
    ],
    cnameIndicators: ['github.io'],
  ),
  TakeoverFingerprint(
    service: 'Shopify',
    bodyIndicators: [
      'Sorry, this shop is currently unavailable',
      'Sorry, this store is currently unavailable',
    ],
    cnameIndicators: ['myshopify.com'],
  ),
  TakeoverFingerprint(
    service: 'Fastly',
    bodyIndicators: ['Fastly error: unknown domain'],
    cnameIndicators: ['fastly.net', 'fastlylb.net'],
  ),
  TakeoverFingerprint(
    service: 'Ghost',
    bodyIndicators: [
      'The thing you were looking for is no longer here, or never was',
    ],
    cnameIndicators: ['ghost.io'],
  ),
  TakeoverFingerprint(
    service: 'Heroku',
    bodyIndicators: ['No such app', 'no-such-app.html'],
    cnameIndicators: ['herokuapp.com', 'herokudns.com', 'herokuapp.com'],
  ),
  TakeoverFingerprint(
    service: 'Pantheon',
    bodyIndicators: [
      'The gods are wise, but do not know of the site which you seek',
      '404 error unknown site',
    ],
    cnameIndicators: ['pantheonsite.io'],
  ),
  TakeoverFingerprint(
    service: 'Tumblr',
    bodyIndicators: [
      "Whatever you were looking for doesn't currently exist at this address",
    ],
    cnameIndicators: ['tumblr.com'],
  ),
  TakeoverFingerprint(
    service: 'WordPress',
    bodyIndicators: ['Do you want to register'],
    cnameIndicators: ['wordpress.com'],
  ),
  TakeoverFingerprint(
    service: 'Teamwork',
    bodyIndicators: ["Oops - We didn't find your site"],
    cnameIndicators: ['teamwork.com'],
  ),
  TakeoverFingerprint(
    service: 'Helpjuice',
    bodyIndicators: ["We could not find what you're looking for"],
    cnameIndicators: ['helpjuice.com'],
  ),
  TakeoverFingerprint(
    service: 'Help Scout',
    bodyIndicators: ['No settings were found for this company'],
    cnameIndicators: ['helpscoutdocs.com', 'helpscout.net'],
  ),
  TakeoverFingerprint(
    service: 'Cargo',
    bodyIndicators: ['404 &mdash; File not found'],
    cnameIndicators: ['cargocollective.com'],
  ),
  TakeoverFingerprint(
    service: 'UserVoice',
    bodyIndicators: ['This UserVoice subdomain is currently available'],
    cnameIndicators: ['uservoice.com'],
  ),
  TakeoverFingerprint(
    service: 'Surge',
    bodyIndicators: ['project not found'],
    cnameIndicators: ['surge.sh'],
  ),
  TakeoverFingerprint(
    service: 'Intercom',
    bodyIndicators: [
      'This page is reserved for artistic dogs',
      "Uh oh. That page doesn't exist",
    ],
    cnameIndicators: ['custom.intercom.help', 'intercom.help'],
  ),
  TakeoverFingerprint(
    service: 'Webflow',
    bodyIndicators: [
      "The page you are looking for doesn't exist or has been moved",
    ],
    cnameIndicators: ['proxy.webflow.com', 'webflow.io'],
  ),
  TakeoverFingerprint(
    service: 'Kajabi',
    bodyIndicators: ["The page you were looking for doesn't exist"],
    cnameIndicators: ['mykajabi.com'],
  ),
  TakeoverFingerprint(
    service: 'Thinkific',
    bodyIndicators: [
      'You may have mistyped the address or the page may have moved',
    ],
    cnameIndicators: ['thinkific.com'],
  ),
  TakeoverFingerprint(
    service: 'Tave',
    bodyIndicators: ['Error 404: Page Not Found'],
    cnameIndicators: ['tave.com'],
    bodyRequiresCname: true,
  ),
  TakeoverFingerprint(
    service: 'Wishpond',
    bodyIndicators: ['wishpond.com/404?campaign=true'],
    cnameIndicators: ['wishpond.com'],
  ),
  TakeoverFingerprint(
    service: 'AfterShip',
    bodyIndicators: ["The page you're looking for doesn't exist"],
    cnameIndicators: ['aftership.com'],
  ),
  TakeoverFingerprint(
    service: 'Aha!',
    bodyIndicators: ['There is no portal here', 'sending you back to Aha'],
    cnameIndicators: ['aha.io'],
  ),
  TakeoverFingerprint(
    service: 'Tictail',
    bodyIndicators: ['Start selling on Tictail', 'tictail.com'],
    cnameIndicators: ['tictail.com'],
  ),
  TakeoverFingerprint(
    service: 'Brightcove',
    bodyIndicators: ['Error Code: 404'],
    cnameIndicators: ['brightcovegallery.com'],
    bodyRequiresCname: true,
  ),
  TakeoverFingerprint(
    service: 'Big Cartel',
    bodyIndicators: ["Oops! We couldn't find that page"],
    cnameIndicators: ['bigcartel.com'],
  ),
  TakeoverFingerprint(
    service: 'ActiveCampaign',
    bodyIndicators: ['LIGHTTPD - fly light'],
    cnameIndicators: ['activehosted.com'],
  ),
  TakeoverFingerprint(
    service: 'Campaign Monitor',
    bodyIndicators: ['Trying to access your account', 'help@createsend.com'],
    cnameIndicators: ['createsend.com'],
  ),
  TakeoverFingerprint(
    service: 'Acquia',
    bodyIndicators: [
      'The site you are looking for could not be found',
      'Web Site Not Found',
      'Acquia Cloud customer',
    ],
    cnameIndicators: ['acquia-sites.com'],
  ),
  TakeoverFingerprint(
    service: 'Proposify',
    bodyIndicators: ['support@proposify.biz'],
    cnameIndicators: ['proposify.biz'],
  ),
  TakeoverFingerprint(
    service: 'Simplebooklet',
    bodyIndicators: ["We can't find this", 'simplebooklet.com'],
    cnameIndicators: ['simplebooklet.com'],
  ),
  TakeoverFingerprint(
    service: 'GetResponse',
    bodyIndicators: [
      'With GetResponse Landing Pages, lead generation has never been easier',
    ],
    cnameIndicators: ['getresponse.com'],
  ),
  TakeoverFingerprint(
    service: 'Vend',
    bodyIndicators: ["Looks like you've traveled too far into cyberspace"],
    cnameIndicators: ['vendhq.com'],
  ),
  TakeoverFingerprint(
    service: 'JetBrains',
    bodyIndicators: ['is not a registered InCloud YouTrack'],
    cnameIndicators: ['myjetbrains.com'],
  ),
  TakeoverFingerprint(
    service: 'Smartling',
    bodyIndicators: ['Domain is not configured'],
    cnameIndicators: ['smartling.com'],
  ),
  TakeoverFingerprint(
    service: 'Pingdom',
    bodyIndicators: ["Sorry, couldn't find the status page"],
    cnameIndicators: ['pingdom.com'],
  ),
  TakeoverFingerprint(
    service: 'Tilda',
    bodyIndicators: [
      'Domain has been assigned',
      'Please renew your subscription',
    ],
    cnameIndicators: ['tilda.ws'],
  ),
  TakeoverFingerprint(
    service: 'SurveyGizmo',
    bodyIndicators: ['data-html-name'],
    cnameIndicators: ['surveygizmo.com', 'alchemer.com'],
  ),
  TakeoverFingerprint(
    service: 'Mashery',
    bodyIndicators: ['Unrecognized domain'],
    cnameIndicators: ['mashery.com'],
  ),
  TakeoverFingerprint(
    service: 'Divio',
    bodyIndicators: ['Application not responding'],
    cnameIndicators: ['divio.com'],
  ),
  TakeoverFingerprint(
    service: 'FeedPress',
    bodyIndicators: ['The feed has not been found'],
    cnameIndicators: ['feedpress.me'],
  ),
  TakeoverFingerprint(
    service: 'ReadMe',
    bodyIndicators: ['Project doesnt exist... yet'],
    cnameIndicators: ['readme.io'],
  ),
  TakeoverFingerprint(
    service: 'Statuspage',
    bodyIndicators: ['You are being'],
    cnameIndicators: ['statuspage.io'],
    bodyRequiresCname: true,
  ),
  TakeoverFingerprint(
    service: 'Zendesk',
    bodyIndicators: ['Help Center Closed'],
    cnameIndicators: ['zendesk.com'],
  ),
  TakeoverFingerprint(
    service: 'Worksites',
    bodyIndicators: ['Hello! Sorry, but the webs'],
    cnameIndicators: ['worksites.net'],
  ),
  TakeoverFingerprint(
    service: 'Agile CRM',
    bodyIndicators: ['this page is no longer available'],
    cnameIndicators: ['agilecrm.com'],
  ),
  TakeoverFingerprint(
    service: 'Anima',
    bodyIndicators: [
      'try refreshing in a minute',
      "this is your website and you've just created it",
    ],
    cnameIndicators: ['animaapp.io'],
  ),
  TakeoverFingerprint(
    service: 'Fly.io',
    bodyIndicators: ['404 Not Found'],
    cnameIndicators: ['fly.dev', 'fly.io'],
    bodyRequiresCname: true,
  ),
  TakeoverFingerprint(
    service: 'Gemfury',
    bodyIndicators: ['This page could not be found'],
    cnameIndicators: ['gemfury.com'],
    bodyRequiresCname: true,
  ),
  TakeoverFingerprint(
    service: 'HatenaBlog',
    bodyIndicators: ['404 Blog is not found'],
    cnameIndicators: ['hatenablog.com'],
  ),
  TakeoverFingerprint(
    service: 'Kinsta',
    bodyIndicators: ['No Site For Domain'],
    cnameIndicators: ['kinsta.cloud', 'kinsta.com'],
  ),
  TakeoverFingerprint(
    service: 'LaunchRock',
    bodyIndicators: [
      'It looks like you may have taken a wrong turn somewhere',
      'it happens to all of us',
    ],
    cnameIndicators: ['launchrock.com'],
  ),
  TakeoverFingerprint(
    service: 'Ngrok',
    bodyIndicators: ['ngrok.io not found'],
    cnameIndicators: ['ngrok.io', 'ngrok-free.app'],
  ),
  TakeoverFingerprint(
    service: 'SmartJobBoard',
    bodyIndicators: [
      'This job board website is either expired or its domain name is invalid',
    ],
    cnameIndicators: ['smartjobboard.com'],
  ),
  TakeoverFingerprint(
    service: 'Strikingly',
    bodyIndicators: ['page not found'],
    cnameIndicators: ['strikinglydns.com', 'strikingly.com'],
    bodyRequiresCname: true,
  ),
  TakeoverFingerprint(
    service: 'Uberflip',
    bodyIndicators: [
      "The URL you've accessed does not provide a hub",
      'hub domain',
    ],
    cnameIndicators: ['uberflip.com'],
  ),
  TakeoverFingerprint(
    service: 'Unbounce',
    bodyIndicators: ['The requested URL was not found on this server'],
    cnameIndicators: ['unbouncepages.com'],
  ),
  TakeoverFingerprint(
    service: 'UptimeRobot',
    bodyIndicators: ['page not found'],
    cnameIndicators: ['uptimerobot.com'],
    bodyRequiresCname: true,
  ),
  TakeoverFingerprint(
    service: 'CloudFront',
    bodyIndicators: [],
    cnameIndicators: ['cloudfront.net'],
  ),
];
