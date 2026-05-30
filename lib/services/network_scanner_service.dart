import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'port_scanner_service.dart';

typedef NetworkConnector =
    Future<Socket> Function(String host, int port, {required Duration timeout});

typedef NetworkLookup = Future<List<InternetAddress>> Function(String host);

typedef NetworkPing =
    Future<bool> Function(String host, {required Duration timeout});

class LocalNetworkCandidate {
  const LocalNetworkCandidate({
    required this.interfaceName,
    required this.address,
    required this.cidr,
  });

  final String interfaceName;
  final String address;
  final String cidr;

  String get label => '$cidr ($interfaceName)';
}

class NetworkScanProfile {
  const NetworkScanProfile({
    required this.name,
    required this.description,
    required this.ports,
    required this.timeout,
    required this.concurrency,
    required this.maxHosts,
  });

  final String name;
  final String description;
  final List<int> ports;
  final Duration timeout;
  final int concurrency;
  final int maxHosts;
}

class NetworkRange {
  const NetworkRange({
    required this.input,
    required this.networkAddress,
    required this.prefixLength,
    required this.firstHost,
    required this.lastHost,
  });

  final String input;
  final String networkAddress;
  final int prefixLength;
  final int firstHost;
  final int lastHost;

  String get cidr => '$networkAddress/$prefixLength';

  int get hostCount => lastHost < firstHost ? 0 : lastHost - firstHost + 1;

  List<String> hosts({required int maxHosts}) {
    if (hostCount > maxHosts) {
      throw FormatException(
        'Network has $hostCount hosts. Narrow the CIDR or raise the scan profile limit.',
      );
    }
    return [
      for (var value = firstHost; value <= lastHost; value++) _intToIpv4(value),
    ];
  }
}

class NetworkDevicePort {
  const NetworkDevicePort({
    required this.port,
    required this.service,
    required this.protocol,
    required this.category,
    required this.encrypted,
  });

  final int port;
  final String service;
  final String protocol;
  final String category;
  final bool encrypted;

  Map<String, Object?> toJson() => {
    'port': port,
    'service': service,
    'protocol': protocol,
    'category': category,
    'encrypted': encrypted,
  };
}

class NetworkDeviceResult {
  const NetworkDeviceResult({
    required this.ip,
    required this.hostname,
    required this.pingResponded,
    required this.latencyMs,
    required this.openPorts,
    required this.timestamp,
  });

  final String ip;
  final String? hostname;
  final bool pingResponded;
  final int? latencyMs;
  final List<NetworkDevicePort> openPorts;
  final DateTime timestamp;

  String get displayName =>
      hostname == null || hostname!.isEmpty ? ip : '$hostname ($ip)';

  String get evidenceLabel {
    final parts = <String>[
      if (pingResponded) 'ping',
      if (openPorts.isNotEmpty) '${openPorts.length} open port(s)',
    ];
    return parts.isEmpty ? 'responsive' : parts.join(' + ');
  }

  Map<String, Object?> toJson() => {
    'ip': ip,
    'hostname': hostname,
    'ping_responded': pingResponded,
    'latency_ms': latencyMs,
    'open_ports': openPorts.map((port) => port.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
  };
}

class NetworkScanProgress {
  const NetworkScanProgress({
    required this.scanned,
    required this.total,
    required this.active,
    required this.deviceCount,
  });

  final int scanned;
  final int total;
  final bool active;
  final int deviceCount;

  double get ratio => total == 0 ? 0 : scanned / total;
}

class NetworkScanSummary {
  const NetworkScanSummary({
    required this.networkInput,
    required this.cidr,
    required this.profile,
    required this.startedAt,
    required this.endedAt,
    required this.totalHosts,
    required this.totalPortChecks,
    required this.results,
    required this.warnings,
  });

  final String networkInput;
  final String cidr;
  final String profile;
  final DateTime startedAt;
  final DateTime endedAt;
  final int totalHosts;
  final int totalPortChecks;
  final List<NetworkDeviceResult> results;
  final List<String> warnings;

  Duration get duration => endedAt.difference(startedAt);

  int get pingCount => results.where((result) => result.pingResponded).length;

  int get openPortCount =>
      results.fold(0, (sum, result) => sum + result.openPorts.length);

  Map<String, Object?> toJson() => {
    'network_input': networkInput,
    'cidr': cidr,
    'profile': profile,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt.toIso8601String(),
    'duration_ms': duration.inMilliseconds,
    'total_hosts': totalHosts,
    'total_port_checks': totalPortChecks,
    'responsive_devices': results.length,
    'ping_responses': pingCount,
    'open_ports': openPortCount,
    'warnings': warnings,
    'devices': results.map((result) => result.toJson()).toList(),
  };

  String toJsonReport() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  String toCsvReport() {
    final buffer = StringBuffer();
    buffer.writeln('ip,hostname,ping,latency_ms,open_ports,services');
    for (final result in results) {
      buffer.writeln(
        [
          result.ip,
          result.hostname ?? '',
          result.pingResponded,
          result.latencyMs ?? '',
          result.openPorts.map((port) => port.port).join(' '),
          result.openPorts.map((port) => port.service).join(' | '),
        ].map(_csvEscape).join(','),
      );
    }
    return buffer.toString();
  }
}

class NetworkScannerService {
  NetworkScannerService({
    NetworkLookup? lookup,
    NetworkConnector? connector,
    NetworkPing? ping,
    DateTime Function()? now,
  }) : _lookup = lookup ?? InternetAddress.lookup,
       _connector =
           connector ??
           ((host, port, {required timeout}) {
             return Socket.connect(host, port, timeout: timeout);
           }),
       _ping = ping ?? _defaultPing,
       _now = now ?? DateTime.now;

  final NetworkLookup _lookup;
  final NetworkConnector _connector;
  final NetworkPing _ping;
  final DateTime Function() _now;
  final StreamController<NetworkScanProgress> _progress =
      StreamController<NetworkScanProgress>.broadcast();

  var _cancelled = false;

  static const List<NetworkScanProfile> profiles = [
    NetworkScanProfile(
      name: 'Quick LAN',
      description: 'Ping plus common web, SSH, SMB, and RDP ports',
      ports: [22, 80, 443, 445, 3389, 8080],
      timeout: Duration(milliseconds: 450),
      concurrency: 64,
      maxHosts: 512,
    ),
    NetworkScanProfile(
      name: 'Web Devices',
      description: 'Routers, dashboards, cameras, and local web UIs',
      ports: [80, 443, 8000, 8080, 8443, 8888, 9000],
      timeout: Duration(milliseconds: 600),
      concurrency: 48,
      maxHosts: 512,
    ),
    NetworkScanProfile(
      name: 'Admin Services',
      description: 'Remote login, file sharing, and management surfaces',
      ports: [22, 23, 445, 548, 5900, 5985, 5986, 3389],
      timeout: Duration(milliseconds: 700),
      concurrency: 40,
      maxHosts: 512,
    ),
    NetworkScanProfile(
      name: 'Deep LAN',
      description: 'Broader device discovery with more TCP probes',
      ports: [
        21,
        22,
        23,
        53,
        80,
        135,
        139,
        443,
        445,
        548,
        631,
        3306,
        3389,
        5000,
        5432,
        5900,
        6379,
        8000,
        8080,
        8443,
        9100,
      ],
      timeout: Duration(milliseconds: 700),
      concurrency: 36,
      maxHosts: 512,
    ),
  ];

  Stream<NetworkScanProgress> get progress => _progress.stream;

  static NetworkScanProfile profileByName(String name) {
    return profiles.firstWhere(
      (profile) => profile.name == name,
      orElse: () => profiles.first,
    );
  }

  static List<int> parsePorts(String input) {
    return PortScannerService.parsePorts(input);
  }

  static NetworkRange parseNetwork(String input) {
    var value = input.trim().toLowerCase();
    if (value.isEmpty) {
      throw const FormatException(
        'Enter a CIDR network, such as 192.168.1.0/24.',
      );
    }
    value = value.replaceFirst(RegExp(r'^https?://'), '');
    final slashAfterHost = value.indexOf('/');
    if (slashAfterHost >= 0 &&
        !value.substring(slashAfterHost + 1).contains('/')) {
      // Keep CIDR suffix intact. A pasted URL path is handled below.
    }
    value = value.split(RegExp(r'\s+')).first;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) value = uri.host;
    value = value.replaceAll(RegExp(r'^\[|\]$'), '');

    if (!value.contains('/') &&
        RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(value)) {
      value = '$value.0/24';
    }
    if (!value.contains('/')) value = '$value/32';

    final parts = value.split('/');
    if (parts.length != 2) {
      throw const FormatException('Enter a valid IPv4 CIDR network.');
    }
    final ip = parts[0].trim();
    final prefix = int.tryParse(parts[1].trim());
    if (prefix == null || prefix < 16 || prefix > 32) {
      throw const FormatException('CIDR prefix must be between /16 and /32.');
    }

    final ipValue = _ipv4ToInt(ip);
    final mask = prefix == 0 ? 0 : ((0xffffffff << (32 - prefix)) & 0xffffffff);
    final network = ipValue & mask;
    final broadcast = network | (~mask & 0xffffffff);
    final firstHost = prefix >= 31 ? network : network + 1;
    final lastHost = prefix >= 31 ? broadcast : broadcast - 1;

    return NetworkRange(
      input: input,
      networkAddress: _intToIpv4(network),
      prefixLength: prefix,
      firstHost: firstHost,
      lastHost: lastHost,
    );
  }

  static Future<List<LocalNetworkCandidate>> localNetworks() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final candidates = <LocalNetworkCandidate>[];
    final seen = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final ip = address.address;
        if (!_looksPrivateIpv4(ip)) continue;
        final octets = ip.split('.');
        final cidr = '${octets[0]}.${octets[1]}.${octets[2]}.0/24';
        if (seen.add(cidr)) {
          candidates.add(
            LocalNetworkCandidate(
              interfaceName: interface.name,
              address: ip,
              cidr: cidr,
            ),
          );
        }
      }
    }
    return candidates;
  }

  void cancel() {
    _cancelled = true;
  }

  void close() {
    _progress.close();
  }

  Future<NetworkScanSummary> scan({
    required String networkText,
    required NetworkScanProfile profile,
    List<int>? ports,
    Duration? timeout,
    int? concurrency,
    bool ping = true,
    bool tcpProbe = true,
  }) async {
    final range = parseNetwork(networkText);
    final scanTimeout = timeout ?? profile.timeout;
    final scanConcurrency = (concurrency ?? profile.concurrency).clamp(1, 96);
    final portList = List<int>.from(ports ?? profile.ports)..sort();
    if (!ping && (!tcpProbe || portList.isEmpty)) {
      throw const FormatException('Enable ping or TCP port probes.');
    }

    final hosts = range.hosts(maxHosts: profile.maxHosts);
    final startedAt = _now();
    final results = <NetworkDeviceResult>[];
    final warnings = <String>[];
    var scanned = 0;
    var cursor = 0;

    _cancelled = false;
    _emitProgress(scanned, hosts.length, true, results.length);

    Future<void> worker() async {
      while (!_cancelled) {
        final index = cursor;
        if (index >= hosts.length) break;
        cursor++;
        final host = hosts[index];
        final result = await _scanHost(
          host,
          ports: tcpProbe ? portList : const [],
          timeout: scanTimeout,
          ping: ping,
        );
        scanned++;
        if (result != null) results.add(result);
        _emitProgress(scanned, hosts.length, !_cancelled, results.length);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        min(scanConcurrency, max(hosts.length, 1)),
        (_) => worker(),
      ),
    );

    results.sort((a, b) => _ipv4ToInt(a.ip).compareTo(_ipv4ToInt(b.ip)));
    if (results.isEmpty) {
      warnings.add(
        'No responsive devices found. Some devices block ping and expose no probed TCP ports.',
      );
    }
    _emitProgress(scanned, hosts.length, false, results.length);

    return NetworkScanSummary(
      networkInput: networkText,
      cidr: range.cidr,
      profile: profile.name,
      startedAt: startedAt,
      endedAt: _now(),
      totalHosts: hosts.length,
      totalPortChecks: tcpProbe ? hosts.length * portList.length : 0,
      results: results,
      warnings: warnings,
    );
  }

  Future<NetworkDeviceResult?> _scanHost(
    String host, {
    required List<int> ports,
    required Duration timeout,
    required bool ping,
  }) async {
    final stopwatch = Stopwatch()..start();
    var pingResponded = false;
    int? latencyMs;

    if (ping) {
      try {
        pingResponded = await _ping(
          host,
          timeout: timeout,
        ).timeout(timeout + const Duration(milliseconds: 250));
        if (pingResponded) latencyMs = stopwatch.elapsedMilliseconds;
      } on Object {
        pingResponded = false;
      }
    }

    final openPorts = <NetworkDevicePort>[];
    for (final port in ports) {
      if (_cancelled) break;
      final openPort = await _probePort(host, port, timeout);
      if (openPort != null) openPorts.add(openPort);
    }

    if (!pingResponded && openPorts.isEmpty) return null;

    final hostname = await _reverseHostname(host);
    return NetworkDeviceResult(
      ip: host,
      hostname: hostname,
      pingResponded: pingResponded,
      latencyMs: latencyMs,
      openPorts: openPorts,
      timestamp: _now(),
    );
  }

  Future<NetworkDevicePort?> _probePort(
    String host,
    int port,
    Duration timeout,
  ) async {
    Socket? socket;
    try {
      socket = await _connector(host, port, timeout: timeout);
      final info =
          PortScannerService.commonServices[port] ??
          const PortServiceInfo(
            name: 'Unknown',
            protocol: 'TCP',
            category: 'Unknown',
            encrypted: false,
          );
      return NetworkDevicePort(
        port: port,
        service: info.name,
        protocol: info.protocol,
        category: info.category,
        encrypted: info.encrypted,
      );
    } on Object {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Future<String?> _reverseHostname(String ip) async {
    try {
      final result = await InternetAddress(
        ip,
      ).reverse().timeout(const Duration(milliseconds: 700));
      if (result.host == ip) return null;
      return result.host;
    } on Object {
      try {
        final addresses = await _lookup(
          ip,
        ).timeout(const Duration(milliseconds: 700));
        if (addresses.isNotEmpty && addresses.first.host != ip) {
          return addresses.first.host;
        }
      } on Object {
        return null;
      }
      return null;
    }
  }

  void _emitProgress(int scanned, int total, bool active, int deviceCount) {
    if (!_progress.isClosed) {
      _progress.add(
        NetworkScanProgress(
          scanned: scanned,
          total: total,
          active: active,
          deviceCount: deviceCount,
        ),
      );
    }
  }

  static Future<bool> _defaultPing(
    String host, {
    required Duration timeout,
  }) async {
    if (!Platform.isMacOS && !Platform.isLinux) return false;
    final timeoutArg = Platform.isMacOS
        ? timeout.inMilliseconds.clamp(100, 5000).toString()
        : max(1, timeout.inSeconds).toString();
    final args = Platform.isMacOS
        ? ['-c', '1', '-W', timeoutArg, host]
        : ['-c', '1', '-W', timeoutArg, host];
    try {
      final result = await Process.run(
        'ping',
        args,
      ).timeout(timeout + const Duration(milliseconds: 500));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }
}

int _ipv4ToInt(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) throw FormatException('Invalid IPv4 address: $ip');
  var value = 0;
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) {
      throw FormatException('Invalid IPv4 address: $ip');
    }
    value = (value << 8) + octet;
  }
  return value;
}

String _intToIpv4(int value) {
  return [
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ].join('.');
}

bool _looksPrivateIpv4(String ip) {
  try {
    final value = _ipv4ToInt(ip);
    return (value & 0xff000000) == 0x0a000000 ||
        (value & 0xfff00000) == 0xac100000 ||
        (value & 0xffff0000) == 0xc0a80000 ||
        (value & 0xffff0000) == 0xa9fe0000;
  } on Object {
    return false;
  }
}

String _csvEscape(Object? value) {
  final text = value?.toString() ?? '';
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}
