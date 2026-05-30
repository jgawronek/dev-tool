import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

typedef DnsLookup = Future<List<InternetAddress>> Function(String host);
typedef SubfinderCommandRunner =
    Future<SubfinderCommandResult> Function(
      String executable,
      List<String> arguments,
      Duration timeout,
    );

enum SubdomainLookupMode { domain, organization }

class SubdomainLookupService {
  SubdomainLookupService({
    http.Client? client,
    DnsLookup? dnsLookup,
    Duration? certificateTimeout,
    Duration? dnsTimeout,
    Duration? subfinderTimeout,
    List<String>? dnsProbeLabels,
    List<String>? subfinderPaths,
    SubfinderCommandRunner? subfinderRunner,
  }) : _client = client ?? http.Client(),
       _dnsLookup = dnsLookup ?? InternetAddress.lookup,
       _certificateTimeout = certificateTimeout ?? const Duration(seconds: 12),
       _dnsTimeout = dnsTimeout ?? const Duration(seconds: 2),
       _subfinderTimeout = subfinderTimeout ?? const Duration(seconds: 35),
       _dnsProbeLabels = dnsProbeLabels ?? _defaultDnsProbeLabels,
       _subfinderPaths = subfinderPaths,
       _subfinderRunner = subfinderRunner ?? _runSubfinderCommand;

  final http.Client _client;
  final DnsLookup _dnsLookup;
  final Duration _certificateTimeout;
  final Duration _dnsTimeout;
  final Duration _subfinderTimeout;
  final List<String> _dnsProbeLabels;
  final List<String>? _subfinderPaths;
  final SubfinderCommandRunner _subfinderRunner;

  static String normalizeDomain(String input) {
    var value = input.trim().toLowerCase();
    if (value.isEmpty) {
      throw const FormatException('Enter a domain first.');
    }

    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      value = uri.host;
    }

    value = value
        .replaceFirst(RegExp(r'^\*\.'), '')
        .replaceFirst(RegExp(r'^www\.'), '')
        .replaceAll(RegExp(r'/$'), '');

    if (!_domainPattern.hasMatch(value) ||
        value.contains('..') ||
        value.split('.').length < 2) {
      throw const FormatException(
        'Enter a valid root domain, like example.com.',
      );
    }

    return value;
  }

  static String normalizeOrganization(String input) {
    final value = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) {
      throw const FormatException('Enter an organization name first.');
    }
    if (value.length > 160) {
      throw const FormatException('Organization name is too long.');
    }
    return value;
  }

  Future<List<String>> findSubdomains(String input) async {
    final result = await lookup(input);
    return result.subdomains;
  }

  Future<SubdomainLookupResult> lookup(String input) async {
    final domain = normalizeDomain(input);
    final subdomains = <String>{};
    final sources = <String>[];
    final warnings = <String>[];
    final subfinderPath = await _findSubfinderExecutable();

    await Future.wait([
      if (subfinderPath != null)
        _lookupSubfinder(domain, subfinderPath)
            .then((hosts) {
              if (hosts.isNotEmpty) {
                sources.add('subfinder');
                subdomains.addAll(hosts);
              }
            })
            .catchError((Object error) {
              warnings.add(_sourceWarning('subfinder', error));
            }),
      _lookupCertSpotter(domain)
          .then((hosts) {
            if (hosts.isNotEmpty) {
              sources.add('CertSpotter');
              subdomains.addAll(hosts);
            }
          })
          .catchError((Object error) {
            warnings.add(_sourceWarning('CertSpotter', error));
          }),
      _lookupHackerTarget(domain)
          .then((hosts) {
            if (hosts.isNotEmpty) {
              sources.add('HackerTarget');
              subdomains.addAll(hosts);
            }
          })
          .catchError((Object error) {
            warnings.add(_sourceWarning('HackerTarget', error));
          }),
      _lookupCertificateTransparency(domain)
          .then((hosts) {
            if (hosts.isNotEmpty) {
              sources.add('Certificate transparency');
              subdomains.addAll(hosts);
            }
          })
          .catchError((Object error) {
            warnings.add(_sourceWarning('crt.sh', error));
          }),
      _lookupCommonDns(domain)
          .then((hosts) {
            if (hosts.isNotEmpty) {
              sources.add('DNS probe');
              subdomains.addAll(hosts);
            }
          })
          .catchError((Object error) {
            warnings.add(_sourceWarning('DNS probe', error));
          }),
    ]);

    final results = subdomains.toList()..sort(_compareHosts);
    return SubdomainLookupResult(
      domain: domain,
      mode: SubdomainLookupMode.domain,
      usedSubfinder: subfinderPath != null,
      subdomains: results,
      sources: sources,
      warnings: warnings,
    );
  }

  Future<SubdomainLookupResult> lookupOrganization(String input) async {
    final organization = normalizeOrganization(input);
    final hosts = <String>{};
    final sources = <String>[];
    final warnings = <String>[];

    try {
      final certificateHosts = await _lookupOrganizationCertificates(
        organization,
      );
      if (certificateHosts.isNotEmpty) {
        sources.add('Organization certificates');
        hosts.addAll(certificateHosts);
      }
    } on Object catch (error) {
      warnings.add(_sourceWarning('crt.sh', error));
    }

    final results = hosts.toList()..sort(_compareHosts);
    return SubdomainLookupResult(
      domain: organization,
      mode: SubdomainLookupMode.organization,
      subdomains: results,
      sources: sources,
      warnings: warnings,
    );
  }

  Future<List<String>> _lookupCertificateTransparency(String domain) async {
    final decoded = await _fetchCrtShRows('%.$domain');

    final subdomains = <String>{};
    for (final row in decoded) {
      if (row is! Map) continue;
      for (final key in const ['name_value', 'common_name']) {
        final value = row[key];
        if (value is! String) continue;
        for (final candidate in value.split('\n')) {
          final host = _normalizeHost(candidate);
          if (host == null || host == domain) continue;
          if (!host.endsWith('.$domain')) continue;
          subdomains.add(host);
        }
      }
    }

    return subdomains.toList()..sort(_compareHosts);
  }

  Future<List<String>> _lookupSubfinder(
    String domain,
    String executable,
  ) async {
    final result = await _subfinderRunner(executable, [
      '-d',
      domain,
      '-silent',
      '-all',
      '-timeout',
      '10',
      '-duc',
    ], _subfinderTimeout);

    if (result.exitCode != 0) {
      final error = result.stderr.trim();
      throw StateError(
        error.isEmpty ? 'subfinder exited with an error.' : error,
      );
    }

    final hosts = <String>{};
    for (final line in const LineSplitter().convert(result.stdout)) {
      final host = _normalizeHostFromOutput(line);
      if (host == null || host == domain) continue;
      if (!host.endsWith('.$domain')) continue;
      hosts.add(host);
    }

    return hosts.toList()..sort(_compareHosts);
  }

  Future<List<String>> _lookupCertSpotter(String domain) async {
    final uri = Uri.https('api.certspotter.com', '/v1/issuances', {
      'domain': domain,
      'include_subdomains': 'true',
      'expand': 'dns_names',
    });

    final response = await _client.get(uri).timeout(_certificateTimeout);
    if (response.statusCode == 404) return const <String>[];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('CertSpotter returned HTTP ${response.statusCode}.');
    }

    final body = response.body.trim();
    if (body.isEmpty) return const <String>[];

    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException(
        'CertSpotter returned an unexpected response.',
      );
    }

    final hosts = <String>{};
    for (final row in decoded) {
      if (row is! Map) continue;
      final dnsNames = row['dns_names'];
      if (dnsNames is! List) continue;
      for (final value in dnsNames) {
        if (value is! String) continue;
        final host = _normalizeHost(value);
        if (host == null || host == domain) continue;
        if (!host.endsWith('.$domain')) continue;
        hosts.add(host);
      }
    }

    return hosts.toList()..sort(_compareHosts);
  }

  Future<List<String>> _lookupHackerTarget(String domain) async {
    final uri = Uri.https('api.hackertarget.com', '/hostsearch/', {
      'q': domain,
    });

    final response = await _client.get(uri).timeout(_certificateTimeout);
    if (response.statusCode == 404) return const <String>[];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HackerTarget returned HTTP ${response.statusCode}.');
    }

    final body = response.body.trim();
    if (body.isEmpty || body.toLowerCase().startsWith('error ')) {
      return const <String>[];
    }

    final hosts = <String>{};
    for (final line in const LineSplitter().convert(body)) {
      final host = _normalizeHostFromOutput(line.split(',').first);
      if (host == null || host == domain) continue;
      if (!host.endsWith('.$domain')) continue;
      hosts.add(host);
    }

    return hosts.toList()..sort(_compareHosts);
  }

  Future<List<String>> _lookupOrganizationCertificates(
    String organization,
  ) async {
    final decoded = await _fetchCrtShRows(organization);

    final hosts = <String>{};
    for (final row in decoded) {
      if (row is! Map) continue;
      for (final key in const ['common_name', 'name_value']) {
        final value = row[key];
        if (value is! String) continue;
        for (final candidate in value.split('\n')) {
          final host = _normalizeHost(candidate);
          if (host != null) hosts.add(host);
        }
      }
    }

    return hosts.toList()..sort(_compareHosts);
  }

  Future<List<dynamic>> _fetchCrtShRows(String query) async {
    final uri = Uri.https('crt.sh', '/', {'q': query, 'output': 'json'});

    final response = await _client.get(uri).timeout(_certificateTimeout);
    if (response.statusCode == 404) return const <dynamic>[];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('crt.sh returned HTTP ${response.statusCode}.');
    }

    final body = response.body.trim();
    if (body.isEmpty) return const <dynamic>[];

    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('crt.sh returned an unexpected response.');
    }
    return decoded;
  }

  Future<List<String>> _lookupCommonDns(String domain) async {
    if (_dnsProbeLabels.isEmpty) return const <String>[];

    final wildcard = await _resolves(
      'devutils-${DateTime.now().microsecondsSinceEpoch}.$domain',
    );
    if (wildcard) {
      throw const FormatException(
        'Wildcard DNS detected, so common-name probing was skipped.',
      );
    }

    final probes = _dnsProbeLabels.map((label) async {
      final host = '$label.$domain';
      return await _resolves(host) ? host : null;
    });
    final resolved = await Future.wait(probes);
    return resolved.whereType<String>().toList()..sort(_compareHosts);
  }

  Future<bool> _resolves(String host) async {
    try {
      final addresses = await _dnsLookup(host).timeout(_dnsTimeout);
      return addresses.isNotEmpty;
    } on Object {
      return false;
    }
  }

  Future<String?> _findSubfinderExecutable() async {
    final candidates = _subfinderPaths ?? _defaultSubfinderPaths();
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final file = File(candidate);
      try {
        if (await file.exists()) return candidate;
      } on Object {
        continue;
      }
    }
    return null;
  }

  void close() {
    _client.close();
  }
}

class SubfinderCommandResult {
  const SubfinderCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class SubdomainLookupResult {
  const SubdomainLookupResult({
    required this.domain,
    this.mode = SubdomainLookupMode.domain,
    this.usedSubfinder = false,
    required this.subdomains,
    required this.sources,
    required this.warnings,
  });

  final String domain;
  final SubdomainLookupMode mode;
  final bool usedSubfinder;
  final List<String> subdomains;
  final List<String> sources;
  final List<String> warnings;

  bool get hasWarnings => warnings.isNotEmpty;
}

final _domainPattern = RegExp(
  r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
);

String? _normalizeHost(String value) {
  final host = value
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^\*\.'), '')
      .replaceAll(RegExp(r'\.$'), '');
  if (host.isEmpty || host.contains(' ') || !_domainPattern.hasMatch(host)) {
    return null;
  }
  return host;
}

String? _normalizeHostFromOutput(String value) {
  var candidate = value.trim().toLowerCase();
  if (candidate.isEmpty) return null;

  final uri = Uri.tryParse(candidate);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    candidate = uri.host;
  } else {
    candidate = candidate.split(RegExp(r'\s+')).first;
  }

  return _normalizeHost(candidate);
}

int _compareHosts(String a, String b) {
  final depth = a.split('.').length.compareTo(b.split('.').length);
  if (depth != 0) return depth;
  return a.compareTo(b);
}

String _sourceWarning(String source, Object error) {
  if (error is TimeoutException) {
    return '$source timed out.';
  }
  if (error is SocketException) {
    return '$source was not reachable.';
  }
  if (error is FormatException) {
    return error.message;
  }
  return '$source lookup failed.';
}

const _defaultDnsProbeLabels = [
  'www',
  'api',
  'app',
  'admin',
  'auth',
  'blog',
  'cdn',
  'dashboard',
  'dev',
  'docs',
  'help',
  'img',
  'login',
  'm',
  'mail',
  'media',
  'mobile',
  'portal',
  'shop',
  'staging',
  'static',
  'status',
  'support',
  'test',
  'vpn',
  'webmail',
];

List<String> _defaultSubfinderPaths() {
  final paths = <String>[];
  final resolvedExecutable = Platform.resolvedExecutable;
  if (resolvedExecutable.isNotEmpty) {
    final contentsDir = File(resolvedExecutable).parent.parent.path;
    paths.add(p.join(contentsDir, 'Resources', 'subfinder', 'subfinder'));
    paths.add(p.join(contentsDir, 'Resources', 'subfinder'));
  }

  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    paths.add(p.join(home, 'go', 'bin', 'subfinder'));
  }

  paths.addAll(const [
    '/opt/homebrew/bin/subfinder',
    '/usr/local/bin/subfinder',
    '/usr/bin/subfinder',
  ]);

  final path = Platform.environment['PATH'];
  if (path != null && path.isNotEmpty) {
    for (final dir in path.split(':')) {
      if (dir.isNotEmpty) paths.add(p.join(dir, 'subfinder'));
    }
  }

  return paths.toSet().toList();
}

Future<SubfinderCommandResult> _runSubfinderCommand(
  String executable,
  List<String> arguments,
  Duration timeout,
) async {
  final process = await Process.start(executable, arguments);
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();

  try {
    final exitCode = await process.exitCode.timeout(timeout);
    return SubfinderCommandResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    throw TimeoutException('subfinder timed out.');
  }
}
