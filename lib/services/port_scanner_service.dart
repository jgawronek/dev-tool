import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

typedef PortConnector =
    Future<Socket> Function(String host, int port, {required Duration timeout});

typedef InternetLookup = Future<List<InternetAddress>> Function(String host);

class PortScanProfile {
  const PortScanProfile({
    required this.name,
    required this.description,
    this.startPort,
    this.endPort,
    required this.timeout,
    required this.concurrency,
    this.ports,
  });

  final String name;
  final String description;
  final int? startPort;
  final int? endPort;
  final Duration timeout;
  final int concurrency;
  final List<int>? ports;

  List<int> resolvePorts() {
    final profilePorts = ports;
    if (profilePorts != null) return List<int>.from(profilePorts)..sort();
    final start = startPort ?? 1;
    final end = endPort ?? start;
    return List<int>.generate(end - start + 1, (index) => start + index);
  }
}

class PortServiceInfo {
  const PortServiceInfo({
    required this.name,
    required this.protocol,
    required this.category,
    required this.encrypted,
  });

  final String name;
  final String protocol;
  final String category;
  final bool encrypted;
}

class PortRiskInfo {
  const PortRiskInfo({
    required this.level,
    required this.score,
    required this.reason,
  });

  final String level;
  final int score;
  final String reason;
}

class PortTlsInfo {
  const PortTlsInfo({
    required this.attempted,
    required this.connected,
    this.protocol,
    this.subject,
    this.issuer,
    this.notBefore,
    this.notAfter,
    this.daysUntilExpiry,
    this.error,
  });

  final bool attempted;
  final bool connected;
  final String? protocol;
  final String? subject;
  final String? issuer;
  final DateTime? notBefore;
  final DateTime? notAfter;
  final int? daysUntilExpiry;
  final String? error;

  Map<String, Object?> toJson() => {
    'attempted': attempted,
    'connected': connected,
    'protocol': protocol,
    'subject': subject,
    'issuer': issuer,
    'not_before': notBefore?.toIso8601String(),
    'not_after': notAfter?.toIso8601String(),
    'days_until_expiry': daysUntilExpiry,
    'error': error,
  };
}

class PortVulnerabilityInfo {
  const PortVulnerabilityInfo({
    required this.id,
    required this.severity,
    required this.description,
  });

  final String id;
  final String severity;
  final String description;

  Map<String, Object?> toJson() => {
    'id': id,
    'severity': severity,
    'description': description,
  };
}

class PortScanResult {
  const PortScanResult({
    required this.port,
    required this.status,
    required this.service,
    required this.protocol,
    required this.category,
    required this.encrypted,
    required this.riskLevel,
    required this.riskScore,
    required this.riskReason,
    required this.vulnerabilities,
    required this.timestamp,
    required this.banner,
    this.confidence = 'Port map',
    this.httpStatus,
    this.tls,
    this.observations = const [],
  });

  final int port;
  final String status;
  final String service;
  final String protocol;
  final String category;
  final bool encrypted;
  final String riskLevel;
  final int riskScore;
  final String riskReason;
  final List<PortVulnerabilityInfo> vulnerabilities;
  final DateTime timestamp;
  final String banner;
  final String confidence;
  final String? httpStatus;
  final PortTlsInfo? tls;
  final List<String> observations;

  Map<String, Object?> toJson() => {
    'port': port,
    'status': status,
    'service': service,
    'protocol': protocol,
    'category': category,
    'encrypted': encrypted,
    'confidence': confidence,
    'risk_level': riskLevel,
    'risk_score': riskScore,
    'risk_reason': riskReason,
    'vulnerabilities': vulnerabilities.map((item) => item.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
    'banner': banner,
    'http_status': httpStatus,
    'tls': tls?.toJson(),
    'observations': observations,
  };
}

class SecurityRecommendation {
  const SecurityRecommendation({
    required this.priority,
    required this.title,
    required this.description,
    required this.port,
  });

  final String priority;
  final String title;
  final String description;
  final int port;

  Map<String, Object?> toJson() => {
    'priority': priority,
    'title': title,
    'description': description,
    'port': port,
  };
}

class SecurityScore {
  const SecurityScore({
    required this.grade,
    required this.score,
    required this.breakdown,
    required this.recommendations,
  });

  final String grade;
  final int score;
  final Map<String, int> breakdown;
  final List<SecurityRecommendation> recommendations;

  Map<String, Object?> toJson() => {
    'grade': grade,
    'score': score,
    'breakdown': breakdown,
    'recommendations': recommendations.map((item) => item.toJson()).toList(),
  };
}

class ScanProgress {
  const ScanProgress({
    required this.scanned,
    required this.total,
    required this.active,
    required this.openCount,
  });

  final int scanned;
  final int total;
  final bool active;
  final int openCount;

  double get ratio => total == 0 ? 0 : scanned / total;
}

class PortScanSummary {
  const PortScanSummary({
    required this.target,
    required this.resolvedIp,
    required this.profile,
    required this.startedAt,
    required this.endedAt,
    required this.totalPorts,
    required this.results,
    required this.securityScore,
  });

  final String target;
  final String resolvedIp;
  final String profile;
  final DateTime startedAt;
  final DateTime endedAt;
  final int totalPorts;
  final List<PortScanResult> results;
  final SecurityScore securityScore;

  Duration get duration => endedAt.difference(startedAt);

  int get highRiskPorts => results
      .where(
        (result) =>
            result.riskLevel == 'HIGH' || result.riskLevel == 'CRITICAL',
      )
      .length;

  Map<String, Object?> toJson() => {
    'target': target,
    'resolved_ip': resolvedIp,
    'profile': profile,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt.toIso8601String(),
    'duration_ms': duration.inMilliseconds,
    'total_ports': totalPorts,
    'open_ports': results.length,
    'high_risk_ports': highRiskPorts,
    'security_score': securityScore.toJson(),
    'results': results.map((result) => result.toJson()).toList(),
  };

  String toJsonReport() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  String toCsvReport() {
    final buffer = StringBuffer();
    buffer.writeln(
      'port,status,service,protocol,category,risk_level,encrypted,banner',
    );
    for (final result in results) {
      buffer.writeln(
        [
          result.port,
          result.status,
          result.service,
          result.protocol,
          result.category,
          result.riskLevel,
          result.encrypted,
          result.banner,
        ].map(_csvEscape).join(','),
      );
    }
    return buffer.toString();
  }
}

class HostReconResult {
  const HostReconResult({
    required this.target,
    required this.timestamp,
    this.resolvedIp,
    this.hostname,
    this.geolocation = const {},
    this.whois = const {},
    this.dnsRecords = const {},
    this.sslAnalysis = const {},
    this.securityHeaders = const {},
    this.technologies = const [],
    this.shodan = const {},
  });

  final String target;
  final DateTime timestamp;
  final String? resolvedIp;
  final String? hostname;
  final Map<String, Object?> geolocation;
  final Map<String, Object?> whois;
  final Map<String, List<String>> dnsRecords;
  final Map<String, Object?> sslAnalysis;
  final Map<String, Object?> securityHeaders;
  final List<Map<String, Object?>> technologies;
  final Map<String, Object?> shodan;

  Map<String, Object?> toJson() => {
    'target': target,
    'timestamp': timestamp.toIso8601String(),
    'resolved_ip': resolvedIp,
    'hostname': hostname,
    'geolocation': geolocation,
    'whois': whois,
    'dns_records': dnsRecords,
    'ssl_analysis': sslAnalysis,
    'security_headers': securityHeaders,
    'technologies': technologies,
    'shodan': shodan,
  };

  String toJsonReport() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }
}

class PortScannerService {
  PortScannerService({
    http.Client? client,
    InternetLookup? lookup,
    PortConnector? connector,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _lookup = lookup ?? InternetAddress.lookup,
       _connector =
           connector ??
           ((host, port, {required timeout}) {
             return Socket.connect(host, port, timeout: timeout);
           }),
       _now = now ?? DateTime.now;

  final http.Client _client;
  final InternetLookup _lookup;
  final PortConnector _connector;
  final DateTime Function() _now;
  final StreamController<ScanProgress> _progress =
      StreamController<ScanProgress>.broadcast();

  var _cancelled = false;

  static const List<PortScanProfile> profiles = [
    PortScanProfile(
      name: 'Quick Scan',
      description: 'Ports 1-100',
      startPort: 1,
      endPort: 100,
      timeout: Duration(milliseconds: 500),
      concurrency: 50,
    ),
    PortScanProfile(
      name: 'Standard Scan',
      description: 'Ports 1-1000',
      startPort: 1,
      endPort: 1000,
      timeout: Duration(seconds: 1),
      concurrency: 50,
    ),
    PortScanProfile(
      name: 'Full Scan',
      description: 'Ports 1-65535',
      startPort: 1,
      endPort: 65535,
      timeout: Duration(seconds: 1),
      concurrency: 100,
    ),
    PortScanProfile(
      name: 'Slow Scan',
      description: 'Ports 1-1000, lower concurrency',
      startPort: 1,
      endPort: 1000,
      timeout: Duration(seconds: 2),
      concurrency: 10,
    ),
    PortScanProfile(
      name: 'Web Ports',
      description: 'Common web services',
      timeout: Duration(milliseconds: 500),
      concurrency: 50,
      ports: [80, 443, 8080, 8443, 8000, 8888, 3000, 5000, 9000, 9443],
    ),
    PortScanProfile(
      name: 'Database Ports',
      description: 'Common database services',
      timeout: Duration(milliseconds: 500),
      concurrency: 50,
      ports: [3306, 5432, 1433, 1521, 27017, 6379, 9200, 5984, 11211],
    ),
    PortScanProfile(
      name: 'Critical Services',
      description: 'Common externally exposed risks',
      timeout: Duration(milliseconds: 500),
      concurrency: 50,
      ports: [
        21,
        22,
        23,
        25,
        53,
        110,
        135,
        139,
        143,
        445,
        993,
        995,
        3389,
        5900,
      ],
    ),
    PortScanProfile(
      name: 'IoT/SCADA',
      description: 'Industrial and IoT ports',
      timeout: Duration(seconds: 1),
      concurrency: 30,
      ports: [502, 102, 44818, 47808, 20000, 4840, 1911, 9600],
    ),
  ];

  static final Map<int, PortServiceInfo> commonServices = {
    20: const PortServiceInfo(
      name: 'FTP Data',
      protocol: 'TCP',
      category: 'File Transfer',
      encrypted: false,
    ),
    21: const PortServiceInfo(
      name: 'FTP Control',
      protocol: 'TCP',
      category: 'File Transfer',
      encrypted: false,
    ),
    22: const PortServiceInfo(
      name: 'SSH',
      protocol: 'TCP',
      category: 'Remote Access',
      encrypted: true,
    ),
    23: const PortServiceInfo(
      name: 'Telnet',
      protocol: 'TCP',
      category: 'Remote Access',
      encrypted: false,
    ),
    25: const PortServiceInfo(
      name: 'SMTP',
      protocol: 'TCP',
      category: 'Email',
      encrypted: false,
    ),
    53: const PortServiceInfo(
      name: 'DNS',
      protocol: 'TCP/UDP',
      category: 'Network',
      encrypted: false,
    ),
    80: const PortServiceInfo(
      name: 'HTTP',
      protocol: 'TCP',
      category: 'Web',
      encrypted: false,
    ),
    110: const PortServiceInfo(
      name: 'POP3',
      protocol: 'TCP',
      category: 'Email',
      encrypted: false,
    ),
    111: const PortServiceInfo(
      name: 'RPCbind',
      protocol: 'TCP',
      category: 'Network',
      encrypted: false,
    ),
    135: const PortServiceInfo(
      name: 'RPC',
      protocol: 'TCP',
      category: 'Windows',
      encrypted: false,
    ),
    139: const PortServiceInfo(
      name: 'NetBIOS',
      protocol: 'TCP',
      category: 'Windows',
      encrypted: false,
    ),
    143: const PortServiceInfo(
      name: 'IMAP',
      protocol: 'TCP',
      category: 'Email',
      encrypted: false,
    ),
    161: const PortServiceInfo(
      name: 'SNMP',
      protocol: 'UDP',
      category: 'Network Management',
      encrypted: false,
    ),
    389: const PortServiceInfo(
      name: 'LDAP',
      protocol: 'TCP',
      category: 'Directory',
      encrypted: false,
    ),
    443: const PortServiceInfo(
      name: 'HTTPS',
      protocol: 'TCP',
      category: 'Web',
      encrypted: true,
    ),
    445: const PortServiceInfo(
      name: 'SMB',
      protocol: 'TCP',
      category: 'File Sharing',
      encrypted: false,
    ),
    465: const PortServiceInfo(
      name: 'SMTPS',
      protocol: 'TCP',
      category: 'Email',
      encrypted: true,
    ),
    587: const PortServiceInfo(
      name: 'SMTP Submission',
      protocol: 'TCP',
      category: 'Email',
      encrypted: false,
    ),
    636: const PortServiceInfo(
      name: 'LDAPS',
      protocol: 'TCP',
      category: 'Directory',
      encrypted: true,
    ),
    993: const PortServiceInfo(
      name: 'IMAPS',
      protocol: 'TCP',
      category: 'Email',
      encrypted: true,
    ),
    995: const PortServiceInfo(
      name: 'POP3S',
      protocol: 'TCP',
      category: 'Email',
      encrypted: true,
    ),
    1433: const PortServiceInfo(
      name: 'MSSQL',
      protocol: 'TCP',
      category: 'Database',
      encrypted: false,
    ),
    1521: const PortServiceInfo(
      name: 'Oracle',
      protocol: 'TCP',
      category: 'Database',
      encrypted: false,
    ),
    2049: const PortServiceInfo(
      name: 'NFS',
      protocol: 'TCP',
      category: 'File Sharing',
      encrypted: false,
    ),
    3306: const PortServiceInfo(
      name: 'MySQL',
      protocol: 'TCP',
      category: 'Database',
      encrypted: false,
    ),
    3389: const PortServiceInfo(
      name: 'RDP',
      protocol: 'TCP',
      category: 'Remote Access',
      encrypted: true,
    ),
    5432: const PortServiceInfo(
      name: 'PostgreSQL',
      protocol: 'TCP',
      category: 'Database',
      encrypted: false,
    ),
    5900: const PortServiceInfo(
      name: 'VNC',
      protocol: 'TCP',
      category: 'Remote Access',
      encrypted: false,
    ),
    5984: const PortServiceInfo(
      name: 'CouchDB',
      protocol: 'TCP',
      category: 'Database',
      encrypted: false,
    ),
    6379: const PortServiceInfo(
      name: 'Redis',
      protocol: 'TCP',
      category: 'Database',
      encrypted: false,
    ),
    8080: const PortServiceInfo(
      name: 'HTTP Proxy',
      protocol: 'TCP',
      category: 'Web',
      encrypted: false,
    ),
    8443: const PortServiceInfo(
      name: 'HTTPS Alt',
      protocol: 'TCP',
      category: 'Web',
      encrypted: true,
    ),
    9200: const PortServiceInfo(
      name: 'Elasticsearch',
      protocol: 'TCP',
      category: 'Database',
      encrypted: false,
    ),
    11211: const PortServiceInfo(
      name: 'Memcached',
      protocol: 'TCP',
      category: 'Database',
      encrypted: false,
    ),
    27017: const PortServiceInfo(
      name: 'MongoDB',
      protocol: 'TCP',
      category: 'Database',
      encrypted: false,
    ),
    502: const PortServiceInfo(
      name: 'Modbus',
      protocol: 'TCP',
      category: 'Industrial',
      encrypted: false,
    ),
    102: const PortServiceInfo(
      name: 'S7comm',
      protocol: 'TCP',
      category: 'Industrial',
      encrypted: false,
    ),
    44818: const PortServiceInfo(
      name: 'EtherNet/IP',
      protocol: 'TCP',
      category: 'Industrial',
      encrypted: false,
    ),
    47808: const PortServiceInfo(
      name: 'BACnet',
      protocol: 'UDP',
      category: 'Industrial',
      encrypted: false,
    ),
    1883: const PortServiceInfo(
      name: 'MQTT',
      protocol: 'TCP',
      category: 'IoT',
      encrypted: false,
    ),
    8883: const PortServiceInfo(
      name: 'MQTT/TLS',
      protocol: 'TCP',
      category: 'IoT',
      encrypted: true,
    ),
    5683: const PortServiceInfo(
      name: 'CoAP',
      protocol: 'UDP',
      category: 'IoT',
      encrypted: false,
    ),
  };

  static final Map<int, PortRiskInfo> riskyPorts = {
    23: const PortRiskInfo(
      level: 'CRITICAL',
      score: 10,
      reason: 'Telnet transmits all data, including passwords, in cleartext.',
    ),
    135: const PortRiskInfo(
      level: 'HIGH',
      score: 8,
      reason: 'RPC is a common Windows remote access attack surface.',
    ),
    139: const PortRiskInfo(
      level: 'HIGH',
      score: 8,
      reason: 'NetBIOS is a legacy protocol with many known weaknesses.',
    ),
    445: const PortRiskInfo(
      level: 'CRITICAL',
      score: 10,
      reason: 'SMB is a common target for wormable remote exploits.',
    ),
    1433: const PortRiskInfo(
      level: 'HIGH',
      score: 7,
      reason:
          'MSSQL is commonly targeted when exposed beyond trusted networks.',
    ),
    3389: const PortRiskInfo(
      level: 'HIGH',
      score: 8,
      reason: 'RDP is frequently targeted for brute force and remote access.',
    ),
    5900: const PortRiskInfo(
      level: 'HIGH',
      score: 7,
      reason: 'VNC is often configured without encryption.',
    ),
    6379: const PortRiskInfo(
      level: 'HIGH',
      score: 8,
      reason: 'Redis is frequently exposed without authentication.',
    ),
    27017: const PortRiskInfo(
      level: 'HIGH',
      score: 8,
      reason: 'MongoDB is often misconfigured without authentication.',
    ),
    11211: const PortRiskInfo(
      level: 'HIGH',
      score: 7,
      reason: 'Memcached typically has no authentication.',
    ),
    502: const PortRiskInfo(
      level: 'CRITICAL',
      score: 9,
      reason: 'Modbus is an industrial protocol with no built-in security.',
    ),
    9200: const PortRiskInfo(
      level: 'HIGH',
      score: 7,
      reason: 'Elasticsearch is often exposed without authentication.',
    ),
    21: const PortRiskInfo(
      level: 'MEDIUM',
      score: 5,
      reason: 'FTP can expose cleartext credentials unless FTPS is enforced.',
    ),
    25: const PortRiskInfo(
      level: 'MEDIUM',
      score: 4,
      reason: 'SMTP can be abused when relay controls are weak.',
    ),
    53: const PortRiskInfo(
      level: 'MEDIUM',
      score: 4,
      reason: 'DNS can contribute to amplification when misconfigured.',
    ),
    161: const PortRiskInfo(
      level: 'HIGH',
      score: 6,
      reason: 'SNMP often uses default community strings.',
    ),
  };

  static final Map<int, List<PortVulnerabilityInfo>> vulnerabilityDatabase = {
    21: const [
      PortVulnerabilityInfo(
        id: 'CVE-2011-2523',
        severity: 'CRITICAL',
        description: 'vsftpd backdoor affected exposed FTP services.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2015-3306',
        severity: 'HIGH',
        description: 'ProFTPD mod_copy arbitrary file operation issue.',
      ),
    ],
    22: const [
      PortVulnerabilityInfo(
        id: 'CVE-2018-15473',
        severity: 'MEDIUM',
        description: 'OpenSSH user enumeration issue.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2016-20012',
        severity: 'MEDIUM',
        description: 'OpenSSH username enumeration issue.',
      ),
    ],
    23: const [
      PortVulnerabilityInfo(
        id: 'CVE-2020-10188',
        severity: 'CRITICAL',
        description: 'Telnet remote code execution in affected daemons.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2011-4862',
        severity: 'CRITICAL',
        description: 'Telnet daemon buffer overflow in affected versions.',
      ),
    ],
    80: const [
      PortVulnerabilityInfo(
        id: 'CVE-2021-41773',
        severity: 'CRITICAL',
        description: 'Apache path traversal and RCE in vulnerable versions.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2017-5638',
        severity: 'CRITICAL',
        description: 'Apache Struts remote code execution.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2021-44228',
        severity: 'CRITICAL',
        description: 'Log4Shell remote code execution in affected apps.',
      ),
    ],
    443: const [
      PortVulnerabilityInfo(
        id: 'CVE-2014-0160',
        severity: 'CRITICAL',
        description: 'Heartbleed affected vulnerable OpenSSL deployments.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2014-3566',
        severity: 'MEDIUM',
        description: 'POODLE affected SSLv3 deployments.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2021-44228',
        severity: 'CRITICAL',
        description: 'Log4Shell remote code execution in affected apps.',
      ),
    ],
    445: const [
      PortVulnerabilityInfo(
        id: 'CVE-2017-0144',
        severity: 'CRITICAL',
        description: 'EternalBlue affected vulnerable SMB services.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2020-0796',
        severity: 'CRITICAL',
        description: 'SMBGhost affected vulnerable SMB services.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2017-0145',
        severity: 'CRITICAL',
        description: 'EternalRomance affected vulnerable SMB services.',
      ),
    ],
    3389: const [
      PortVulnerabilityInfo(
        id: 'CVE-2019-0708',
        severity: 'CRITICAL',
        description: 'BlueKeep affected vulnerable RDP services.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2019-1181',
        severity: 'CRITICAL',
        description: 'DejaBlue affected vulnerable RDP services.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2019-1182',
        severity: 'CRITICAL',
        description: 'DejaBlue variant affected vulnerable RDP services.',
      ),
    ],
    6379: const [
      PortVulnerabilityInfo(
        id: 'CVE-2022-0543',
        severity: 'CRITICAL',
        description: 'Redis Lua sandbox escape in vulnerable builds.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2015-8080',
        severity: 'HIGH',
        description: 'Redis integer overflow in affected versions.',
      ),
    ],
    27017: const [
      PortVulnerabilityInfo(
        id: 'CVE-2017-2665',
        severity: 'HIGH',
        description: 'MongoDB authentication bypass in affected versions.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2019-2389',
        severity: 'MEDIUM',
        description: 'MongoDB information disclosure issue.',
      ),
    ],
    9200: const [
      PortVulnerabilityInfo(
        id: 'CVE-2015-1427',
        severity: 'CRITICAL',
        description: 'Elasticsearch Groovy RCE in vulnerable versions.',
      ),
      PortVulnerabilityInfo(
        id: 'CVE-2014-3120',
        severity: 'CRITICAL',
        description: 'Elasticsearch MVEL RCE in vulnerable versions.',
      ),
    ],
    502: const [
      PortVulnerabilityInfo(
        id: 'CVE-2017-9310',
        severity: 'HIGH',
        description: 'Modbus denial of service in affected products.',
      ),
      PortVulnerabilityInfo(
        id: 'N/A',
        severity: 'CRITICAL',
        description: 'Modbus has no authentication by design.',
      ),
    ],
    11211: const [
      PortVulnerabilityInfo(
        id: 'CVE-2018-1000001',
        severity: 'HIGH',
        description: 'Memcached DDoS amplification risk.',
      ),
      PortVulnerabilityInfo(
        id: 'N/A',
        severity: 'HIGH',
        description: 'Memcached typically has no authentication.',
      ),
    ],
  };

  static const List<String> securityHeaders = [
    'Strict-Transport-Security',
    'Content-Security-Policy',
    'X-Content-Type-Options',
    'X-Frame-Options',
    'X-XSS-Protection',
    'Referrer-Policy',
    'Permissions-Policy',
    'Cross-Origin-Opener-Policy',
    'Cross-Origin-Resource-Policy',
    'Cross-Origin-Embedder-Policy',
  ];

  Stream<ScanProgress> get progress => _progress.stream;

  static PortScanProfile profileByName(String name) {
    return profiles.firstWhere(
      (profile) => profile.name == name,
      orElse: () => profiles.first,
    );
  }

  static String normalizeTarget(String input) {
    var value = input.trim();
    if (value.isEmpty) throw const FormatException('Enter a host or IP.');
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      value = uri.host;
    }
    value = value.replaceAll(RegExp(r'^\[|\]$'), '');
    if (value.length > 255 || value.contains(RegExp(r'\s'))) {
      throw const FormatException('Enter a valid host or IP.');
    }
    return value.toLowerCase();
  }

  static List<int> parsePorts(String input) {
    final value = input.trim();
    if (value.isEmpty) throw const FormatException('Enter one or more ports.');
    final ports = <int>{};
    for (final part in value.split(',')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      if (token.contains('-')) {
        final bounds = token.split('-').map((item) => item.trim()).toList();
        if (bounds.length != 2) {
          throw FormatException('Invalid port range: $token');
        }
        final start = int.tryParse(bounds[0]);
        final end = int.tryParse(bounds[1]);
        if (start == null || end == null || start > end) {
          throw FormatException('Invalid port range: $token');
        }
        _validatePort(start);
        _validatePort(end);
        for (var port = start; port <= end; port++) {
          ports.add(port);
        }
      } else {
        final port = int.tryParse(token);
        if (port == null) throw FormatException('Invalid port: $token');
        _validatePort(port);
        ports.add(port);
      }
    }
    if (ports.isEmpty) throw const FormatException('Enter one or more ports.');
    return ports.toList()..sort();
  }

  static SecurityScore calculateSecurityScore(List<PortScanResult> results) {
    if (results.isEmpty) {
      return const SecurityScore(
        grade: 'A',
        score: 100,
        breakdown: {
          'open_ports_penalty': 0,
          'critical_ports_penalty': 0,
          'high_risk_penalty': 0,
          'unencrypted_penalty': 0,
          'vulnerability_penalty': 0,
        },
        recommendations: [],
      );
    }

    final breakdown = {
      'open_ports_penalty': 0,
      'critical_ports_penalty': 0,
      'high_risk_penalty': 0,
      'unencrypted_penalty': 0,
      'vulnerability_penalty': 0,
    };

    final openCount = results.length;
    if (openCount > 20) {
      breakdown['open_ports_penalty'] = 15;
    } else if (openCount > 10) {
      breakdown['open_ports_penalty'] = 10;
    } else if (openCount > 5) {
      breakdown['open_ports_penalty'] = 5;
    }

    for (final result in results) {
      if (result.riskLevel == 'CRITICAL') {
        breakdown['critical_ports_penalty'] =
            breakdown['critical_ports_penalty']! + 15;
      } else if (result.riskLevel == 'HIGH') {
        breakdown['high_risk_penalty'] = breakdown['high_risk_penalty']! + 8;
      }

      if (!result.encrypted &&
          const {'Remote Access', 'Email', 'Web'}.contains(result.category)) {
        breakdown['unencrypted_penalty'] =
            breakdown['unencrypted_penalty']! + 5;
      }

      breakdown['vulnerability_penalty'] =
          breakdown['vulnerability_penalty']! +
          (result.vulnerabilities.length * 3);
    }

    breakdown['critical_ports_penalty'] = min(
      breakdown['critical_ports_penalty']!,
      40,
    );
    breakdown['high_risk_penalty'] = min(breakdown['high_risk_penalty']!, 25);
    breakdown['unencrypted_penalty'] = min(
      breakdown['unencrypted_penalty']!,
      15,
    );
    breakdown['vulnerability_penalty'] = min(
      breakdown['vulnerability_penalty']!,
      20,
    );

    final penalty = breakdown.values.fold<int>(0, (sum, item) => sum + item);
    final finalScore = max(0, 100 - penalty);
    final grade = switch (finalScore) {
      >= 90 => 'A',
      >= 80 => 'B',
      >= 70 => 'C',
      >= 60 => 'D',
      _ => 'F',
    };

    return SecurityScore(
      grade: grade,
      score: finalScore,
      breakdown: breakdown,
      recommendations: _recommendations(results),
    );
  }

  void cancel() {
    _cancelled = true;
  }

  void close() {
    _client.close();
    _progress.close();
  }

  Future<PortScanSummary> scan({
    required String target,
    required PortScanProfile profile,
    List<int>? ports,
    Duration? timeout,
    int? concurrency,
    bool grabBanners = true,
    bool tlsDetails = true,
    bool httpProbe = true,
  }) async {
    final normalizedTarget = normalizeTarget(target);
    final resolved = await _resolveTarget(normalizedTarget);
    final resolvedIp = resolved.address;
    final portList = ports ?? profile.resolvePorts();
    final scanTimeout = timeout ?? profile.timeout;
    final scanConcurrency = (concurrency ?? profile.concurrency).clamp(1, 100);
    final startedAt = _now();
    final results = <PortScanResult>[];
    var scanned = 0;
    var cursor = 0;

    _cancelled = false;
    _emitProgress(scanned, portList.length, true, results.length);

    Future<void> worker() async {
      while (!_cancelled) {
        final currentIndex = cursor;
        if (currentIndex >= portList.length) break;
        cursor++;
        final port = portList[currentIndex];
        final result = await _scanPort(
          target: normalizedTarget,
          resolvedIp: resolvedIp,
          port: port,
          timeout: scanTimeout,
          grabBanner: grabBanners,
          tlsDetails: tlsDetails,
          httpProbe: httpProbe,
        );
        scanned++;
        if (result != null) {
          results.add(result);
        }
        _emitProgress(scanned, portList.length, !_cancelled, results.length);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        min(scanConcurrency, portList.length),
        (_) => worker(),
      ),
    );

    results.sort((a, b) => a.port.compareTo(b.port));
    final endedAt = _now();
    final score = calculateSecurityScore(results);
    _emitProgress(scanned, portList.length, false, results.length);

    return PortScanSummary(
      target: normalizedTarget,
      resolvedIp: resolvedIp,
      profile: profile.name,
      startedAt: startedAt,
      endedAt: endedAt,
      totalPorts: portList.length,
      results: results,
      securityScore: score,
    );
  }

  Future<HostReconResult> reconnaissance(String target) async {
    final normalizedTarget = normalizeTarget(target);
    String? resolvedIp;
    String? hostname;

    try {
      final resolved = await _resolveTarget(normalizedTarget);
      resolvedIp = resolved.address;
      hostname = await _reverseHostname(resolvedIp);
    } on Object {
      resolvedIp = null;
    }

    final isIp = InternetAddress.tryParse(normalizedTarget) != null;
    final dnsHost = isIp ? null : normalizedTarget;
    final shodanKey = Platform.environment['SHODAN_API_KEY'] ?? '';

    final geolocationFuture = resolvedIp == null
        ? Future<Map<String, Object?>>.value({})
        : _getGeolocation(resolvedIp);
    final whoisFuture = resolvedIp == null
        ? Future<Map<String, Object?>>.value({})
        : _getWhoisInfo(resolvedIp);
    final shodanFuture = resolvedIp == null
        ? Future<Map<String, Object?>>.value({})
        : _getShodanInfo(resolvedIp, shodanKey);
    final dnsFuture = dnsHost == null
        ? Future<Map<String, List<String>>>.value({})
        : _getDnsRecords(dnsHost);
    final sslFuture = dnsHost == null
        ? Future<Map<String, Object?>>.value({})
        : _analyzeSslCertificate(dnsHost);
    final headersAndTechFuture = dnsHost == null
        ? Future<_WebReconResult>.value(const _WebReconResult())
        : _analyzeWebTarget(dnsHost);

    final geolocation = await geolocationFuture;
    final whois = await whoisFuture;
    final shodan = await shodanFuture;
    final dnsRecords = await dnsFuture;
    final sslAnalysis = await sslFuture;
    final webRecon = await headersAndTechFuture;

    return HostReconResult(
      target: normalizedTarget,
      timestamp: _now(),
      resolvedIp: resolvedIp,
      hostname: hostname,
      geolocation: geolocation,
      whois: whois,
      dnsRecords: dnsRecords,
      sslAnalysis: sslAnalysis,
      securityHeaders: webRecon.securityHeaders,
      technologies: webRecon.technologies,
      shodan: shodan,
    );
  }

  Future<InternetAddress> _resolveTarget(String target) async {
    final parsed = InternetAddress.tryParse(target);
    if (parsed != null) return parsed;
    final addresses = await _lookup(target).timeout(const Duration(seconds: 5));
    if (addresses.isEmpty) {
      throw const SocketException('Could not resolve hostname.');
    }
    return addresses.first;
  }

  Future<PortScanResult?> _scanPort({
    required String target,
    required String resolvedIp,
    required int port,
    required Duration timeout,
    required bool grabBanner,
    required bool tlsDetails,
    required bool httpProbe,
  }) async {
    Socket? socket;
    try {
      socket = await _connector(resolvedIp, port, timeout: timeout);
      final serviceInfo =
          commonServices[port] ??
          const PortServiceInfo(
            name: 'Unknown',
            protocol: 'TCP',
            category: 'Unknown',
            encrypted: false,
          );
      final tls = tlsDetails && _shouldAttemptTls(port, serviceInfo)
          ? await _inspectTls(target, port, timeout)
          : null;
      final banner = grabBanner
          ? await _grabBanner(
              socket,
              target: target,
              port: port,
              timeout: timeout,
              httpProbe: httpProbe,
            )
          : 'Not requested';
      final fingerprint = _fingerprint(port, serviceInfo, banner, tls);
      final riskInfo = _riskFor(port, tls);
      return PortScanResult(
        port: port,
        status: 'OPEN',
        service: fingerprint.service,
        protocol: fingerprint.protocol,
        category: fingerprint.category,
        encrypted: fingerprint.encrypted,
        riskLevel: riskInfo.level,
        riskScore: riskInfo.score,
        riskReason: riskInfo.reason,
        vulnerabilities: vulnerabilityDatabase[port] ?? const [],
        timestamp: _now(),
        banner: banner,
        confidence: fingerprint.confidence,
        httpStatus: _httpStatusLine(banner),
        tls: tls,
        observations: fingerprint.observations,
      );
    } on Object {
      socket?.destroy();
      return null;
    }
  }

  Future<String> _grabBanner(
    Socket socket, {
    required String target,
    required int port,
    required Duration timeout,
    required bool httpProbe,
  }) async {
    try {
      if (httpProbe && _shouldProbeHttp(port)) {
        socket.write('HEAD / HTTP/1.1\r\nHost: $target\r\n\r\n');
      } else if (!_oftenSendsPassiveBanner(port)) {
        socket.write('\r\n');
      }

      final banner = await socket
          .timeout(timeout)
          .take(1)
          .map((chunk) => utf8.decode(chunk, allowMalformed: true))
          .join()
          .timeout(timeout);
      socket.destroy();
      final cleaned = banner.replaceAll(RegExp(r'\s+'), ' ').trim();
      return cleaned.isEmpty ? 'No banner' : _truncate(cleaned, 300);
    } on Object {
      socket.destroy();
      return 'No banner';
    }
  }

  Future<PortTlsInfo> _inspectTls(
    String target,
    int port,
    Duration timeout,
  ) async {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        target,
        port,
        timeout: timeout,
        onBadCertificate: (_) => true,
      );
      final certificate = socket.peerCertificate;
      final daysUntilExpiry = certificate?.endValidity
          .difference(_now())
          .inDays;
      return PortTlsInfo(
        attempted: true,
        connected: true,
        protocol: socket.selectedProtocol ?? 'TLS',
        subject: certificate?.subject,
        issuer: certificate?.issuer,
        notBefore: certificate?.startValidity,
        notAfter: certificate?.endValidity,
        daysUntilExpiry: daysUntilExpiry,
      );
    } on Object catch (error) {
      return PortTlsInfo(
        attempted: true,
        connected: false,
        error: error.toString(),
      );
    } finally {
      socket?.destroy();
    }
  }

  _PortFingerprint _fingerprint(
    int port,
    PortServiceInfo serviceInfo,
    String banner,
    PortTlsInfo? tls,
  ) {
    final lower = banner.toLowerCase();
    final observations = <String>['TCP connection accepted.'];
    var service = serviceInfo.name;
    var protocol = serviceInfo.protocol;
    var category = serviceInfo.category;
    var encrypted = serviceInfo.encrypted;
    var confidence = service == 'Unknown' ? 'Connect' : 'Port map';

    if (tls?.connected ?? false) {
      encrypted = true;
      confidence = 'TLS';
      protocol = protocol == 'TCP' ? 'TLS' : protocol;
      observations.add('TLS handshake completed.');
      if (tls?.subject != null) {
        observations.add('Certificate subject: ${tls!.subject}');
      }
      final days = tls?.daysUntilExpiry;
      if (days != null) observations.add('Certificate expires in $days days.');
    } else if (tls?.attempted ?? false) {
      observations.add(
        'TLS handshake failed: ${tls!.error ?? 'unknown error'}',
      );
    }

    if (banner.startsWith('SSH-')) {
      service = 'SSH';
      protocol = 'SSH';
      category = 'Remote Access';
      encrypted = true;
      confidence = 'Banner';
      observations.add('SSH version banner received.');
    } else if (banner.startsWith('HTTP/')) {
      service = port == 443 || encrypted ? 'HTTPS' : 'HTTP';
      protocol = encrypted ? 'HTTPS' : 'HTTP';
      category = 'Web';
      confidence = 'HTTP';
      observations.add('HTTP status line received.');
    } else if (lower.contains('ftp')) {
      service = 'FTP';
      protocol = 'FTP';
      category = 'File Transfer';
      confidence = 'Banner';
      observations.add('FTP banner indicator received.');
    } else if (lower.contains('smtp') ||
        (port == 25 && banner.startsWith('220'))) {
      service = 'SMTP';
      protocol = 'SMTP';
      category = 'Email';
      confidence = 'Banner';
      observations.add('SMTP banner indicator received.');
    } else if (lower.contains('redis')) {
      service = 'Redis';
      protocol = 'Redis';
      category = 'Database';
      confidence = 'Banner';
      observations.add('Redis banner indicator received.');
    } else if (lower.contains('mysql')) {
      service = 'MySQL';
      protocol = 'MySQL';
      category = 'Database';
      confidence = 'Banner';
      observations.add('MySQL banner indicator received.');
    }

    if (banner == 'No banner') {
      observations.add('No readable banner was returned before timeout.');
    } else if (banner != 'Not requested' && !banner.startsWith('HTTP/')) {
      observations.add('Readable banner captured.');
    }

    return _PortFingerprint(
      service: service,
      protocol: protocol,
      category: category,
      encrypted: encrypted,
      confidence: confidence,
      observations: observations,
    );
  }

  PortRiskInfo _riskFor(int port, PortTlsInfo? tls) {
    if (tls?.connected ?? false) {
      final days = tls?.daysUntilExpiry;
      if (days != null && days < 0) {
        return const PortRiskInfo(
          level: 'HIGH',
          score: 7,
          reason: 'TLS is present, but the certificate is expired.',
        );
      }
      if (days != null && days < 30) {
        return const PortRiskInfo(
          level: 'MEDIUM',
          score: 4,
          reason: 'TLS is present, but the certificate expires soon.',
        );
      }
    }
    return riskyPorts[port] ??
        const PortRiskInfo(
          level: 'LOW',
          score: 1,
          reason: 'Open TCP service. Review exposure against intended access.',
        );
  }

  bool _shouldAttemptTls(int port, PortServiceInfo serviceInfo) {
    return serviceInfo.encrypted ||
        const {443, 465, 636, 993, 995, 8443, 8883, 9443, 5986}.contains(port);
  }

  bool _shouldProbeHttp(int port) {
    return const {
      80,
      443,
      8080,
      8443,
      8000,
      8888,
      3000,
      5000,
      9000,
      9443,
      5985,
      5986,
    }.contains(port);
  }

  bool _oftenSendsPassiveBanner(int port) {
    return const {21, 22, 25, 110, 143, 587}.contains(port);
  }

  String? _httpStatusLine(String banner) {
    if (!banner.startsWith('HTTP/')) return null;
    return banner.split(' ').take(3).join(' ');
  }

  void _emitProgress(int scanned, int total, bool active, int openCount) {
    if (!_progress.isClosed) {
      _progress.add(
        ScanProgress(
          scanned: scanned,
          total: total,
          active: active,
          openCount: openCount,
        ),
      );
    }
  }

  Future<String?> _reverseHostname(String ip) async {
    try {
      final result = await InternetAddress(
        ip,
      ).reverse().timeout(const Duration(seconds: 3));
      return result.host;
    } on Object {
      return null;
    }
  }

  Future<Map<String, Object?>> _getGeolocation(String ip) async {
    try {
      final response = await _client
          .get(Uri.parse('http://ip-api.com/json/$ip'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return {};
      final data = jsonDecode(response.body);
      if (data is! Map || data['status'] != 'success') return {};
      return {
        'country': data['country'],
        'countryCode': data['countryCode'],
        'region': data['regionName'],
        'city': data['city'],
        'zip': data['zip'],
        'lat': data['lat'],
        'lon': data['lon'],
        'timezone': data['timezone'],
        'isp': data['isp'],
        'org': data['org'],
        'as': data['as'],
      };
    } on Object {
      return {};
    }
  }

  Future<Map<String, Object?>> _getWhoisInfo(String ip) async {
    try {
      final response = await _client
          .get(Uri.parse('https://ipwhois.app/json/$ip'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return {};
      final data = jsonDecode(response.body);
      if (data is! Map) return {};
      return {
        'asn': data['asn'],
        'org': data['org'],
        'isp': data['isp'],
        'country': data['country'],
        'region': data['region'],
        'city': data['city'],
      };
    } on Object {
      return {};
    }
  }

  Future<Map<String, Object?>> _getShodanInfo(String ip, String key) async {
    if (key.isEmpty) return {'message': 'No Shodan API key configured'};
    try {
      final uri = Uri.https('api.shodan.io', '/shodan/host/$ip', {'key': key});
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) {
        return {'message': 'Host not found in Shodan database'};
      }
      if (response.statusCode != 200) {
        return {'error': 'Shodan returned HTTP ${response.statusCode}'};
      }
      final data = jsonDecode(response.body);
      if (data is! Map) return {};
      final services = <Map<String, Object?>>[];
      final dataRows = data['data'];
      if (dataRows is List) {
        for (final row in dataRows.take(10)) {
          if (row is! Map) continue;
          services.add({
            'port': row['port'],
            'transport': row['transport'],
            'product': row['product'],
            'version': row['version'],
            'banner': _truncate((row['data'] ?? '').toString(), 200),
          });
        }
      }
      return {
        'ports': data['ports'] is List ? data['ports'] : const [],
        'hostnames': data['hostnames'] is List ? data['hostnames'] : const [],
        'country': data['country_name'],
        'city': data['city'],
        'org': data['org'],
        'isp': data['isp'],
        'asn': data['asn'],
        'os': data['os'],
        'vulns': data['vulns'] is List ? data['vulns'] : const [],
        'tags': data['tags'] is List ? data['tags'] : const [],
        'last_update': data['last_update'],
        'services': services,
      };
    } on Object catch (error) {
      return {'error': error.toString()};
    }
  }

  Future<Map<String, List<String>>> _getDnsRecords(String domain) async {
    final records = <String, List<String>>{};
    for (final type in const ['A', 'AAAA', 'MX', 'NS', 'TXT', 'SOA', 'CNAME']) {
      try {
        final uri = Uri.https('dns.google', '/resolve', {
          'name': domain,
          'type': type,
        });
        final response = await _client
            .get(uri, headers: {'accept': 'application/dns-json'})
            .timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        if (data is! Map) continue;
        final answers = data['Answer'];
        if (answers is! List) continue;
        final values = <String>[];
        for (final answer in answers) {
          if (answer is Map && answer['data'] != null) {
            values.add(answer['data'].toString());
          }
        }
        if (values.isNotEmpty) records[type] = values;
      } on Object {
        continue;
      }
    }
    return records;
  }

  Future<Map<String, Object?>> _analyzeSslCertificate(
    String host, {
    int port = 443,
  }) async {
    final result = <String, Object?>{
      'valid': false,
      'grade': 'F',
      'issues': <String>[],
      'details': <String, Object?>{},
    };
    final issues = result['issues']! as List<String>;
    final details = result['details']! as Map<String, Object?>;

    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
        onBadCertificate: (_) => true,
      );
      final cert = socket.peerCertificate;
      details['protocol'] = socket.selectedProtocol ?? 'TLS';
      details['subject'] = cert?.subject;
      details['issuer'] = cert?.issuer;
      details['not_before'] = cert?.startValidity.toIso8601String();
      details['not_after'] = cert?.endValidity.toIso8601String();
      if (cert == null) {
        issues.add('No certificate presented.');
      } else {
        final now = _now();
        final daysLeft = cert.endValidity.difference(now).inDays;
        details['days_until_expiry'] = daysLeft;
        if (now.isBefore(cert.startValidity)) {
          issues.add('Certificate is not valid yet.');
        }
        if (daysLeft < 0) {
          issues.add('Certificate has expired.');
        } else if (daysLeft < 30) {
          issues.add('Certificate expires in $daysLeft days.');
        }
      }
      result['valid'] = issues.isEmpty;
      result['grade'] = issues.isEmpty ? 'A' : (issues.length == 1 ? 'B' : 'F');
    } on Object catch (error) {
      result['error'] = error.toString();
      issues.add('SSL connection failed: $error');
    } finally {
      socket?.destroy();
    }
    return result;
  }

  Future<_WebReconResult> _analyzeWebTarget(String host) async {
    for (final scheme in const ['https', 'http']) {
      try {
        final uri = Uri.parse('$scheme://$host');
        final response = await _client
            .get(uri)
            .timeout(const Duration(seconds: 5));
        return _WebReconResult(
          securityHeaders: _checkSecurityHeaders(response.headers),
          technologies: _detectTechnologies(response),
        );
      } on Object {
        continue;
      }
    }
    return const _WebReconResult(
      securityHeaders: {'error': 'No HTTP or HTTPS response received.'},
    );
  }

  Map<String, Object?> _checkSecurityHeaders(Map<String, String> headers) {
    final normalized = {
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
    final present = <String>[];
    final missing = <String>[];
    final details = <String, String>{};
    for (final header in securityHeaders) {
      final lower = header.toLowerCase();
      if (normalized.containsKey(lower)) {
        present.add(header);
        details[header] = normalized[lower]!;
      } else {
        missing.add(header);
      }
    }

    final infoDisclosure = <Map<String, String>>[];
    for (final header in const [
      'server',
      'x-powered-by',
      'x-aspnet-version',
      'x-aspnetmvc-version',
    ]) {
      final value = normalized[header];
      if (value != null) infoDisclosure.add({header: value});
    }

    return {
      'present': present,
      'missing': missing,
      'score': present.length * 10,
      'details': details,
      'info_disclosure': infoDisclosure,
    };
  }

  List<Map<String, Object?>> _detectTechnologies(http.Response response) {
    final technologies = <Map<String, Object?>>[];
    final headers = {
      for (final entry in response.headers.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final body = response.body.toLowerCase();

    final server = headers['server'];
    if (server != null && server.isNotEmpty) {
      technologies.add({
        'name': 'Server',
        'value': server,
        'category': 'Server',
      });
    }

    final poweredBy = headers['x-powered-by'];
    if (poweredBy != null && poweredBy.isNotEmpty) {
      technologies.add({
        'name': 'Powered By',
        'value': poweredBy,
        'category': 'Framework',
      });
    }

    final signatures = {
      'WordPress': ['wp-content', 'wp-includes', 'wordpress'],
      'Drupal': ['drupal.js', 'drupal.css', '/sites/default/'],
      'Joomla': ['joomla', '/media/system/'],
      'Django': ['csrfmiddlewaretoken', '__admin_media_prefix__'],
      'Laravel': ['laravel_session', 'laravel'],
      'React': ['react', '_reactroot', 'data-reactroot'],
      'Vue.js': ['vue.js', 'v-cloak', '__vue__'],
      'Angular': ['ng-version', 'ng-app', 'angular'],
      'jQuery': ['jquery'],
      'Bootstrap': ['bootstrap.css', 'bootstrap.min.css'],
    };

    for (final entry in signatures.entries) {
      if (entry.value.any((signature) => body.contains(signature))) {
        technologies.add({'name': entry.key, 'category': 'Technology'});
      }
    }

    final cookieHeader = headers['set-cookie'];
    if (cookieHeader != null &&
        cookieHeader.toLowerCase().contains('session')) {
      technologies.add({
        'name': 'Session Cookie',
        'value': cookieHeader.split(';').first,
        'category': 'Cookie',
      });
    }

    return technologies;
  }

  static void _validatePort(int port) {
    if (port < 1 || port > 65535) {
      throw FormatException('Port must be between 1 and 65535: $port');
    }
  }

  static List<SecurityRecommendation> _recommendations(
    List<PortScanResult> results,
  ) {
    final recommendations = <SecurityRecommendation>[];
    for (final result in results) {
      final port = result.port;
      final service = result.service;
      if (port == 23) {
        recommendations.add(
          SecurityRecommendation(
            priority: 'CRITICAL',
            title: 'Disable Telnet',
            description:
                'Port $port ($service) transmits data in cleartext. Replace it with SSH.',
            port: port,
          ),
        );
      } else if (port == 21) {
        recommendations.add(
          SecurityRecommendation(
            priority: 'HIGH',
            title: 'Secure FTP',
            description:
                'Port $port ($service) uses cleartext. Consider SFTP or FTPS.',
            port: port,
          ),
        );
      } else if (port == 139 || port == 445) {
        recommendations.add(
          SecurityRecommendation(
            priority: 'CRITICAL',
            title: 'Secure SMB',
            description:
                'Port $port ($service) is a common attack vector. Patch and restrict access.',
            port: port,
          ),
        );
      } else if (port == 3389) {
        recommendations.add(
          SecurityRecommendation(
            priority: 'HIGH',
            title: 'Secure RDP',
            description:
                'Port $port ($service) should use NLA and be behind VPN.',
            port: port,
          ),
        );
      } else if (const {6379, 27017, 9200, 11211}.contains(port)) {
        recommendations.add(
          SecurityRecommendation(
            priority: 'CRITICAL',
            title: 'Secure $service',
            description:
                'Port $port ($service) should not be publicly exposed. Enable authentication and firewall rules.',
            port: port,
          ),
        );
      } else if (port == 502) {
        recommendations.add(
          SecurityRecommendation(
            priority: 'CRITICAL',
            title: 'Isolate Industrial Protocol',
            description:
                'Port $port ($service) is an industrial protocol and should be isolated from the internet.',
            port: port,
          ),
        );
      }
    }
    return recommendations;
  }
}

class _PortFingerprint {
  const _PortFingerprint({
    required this.service,
    required this.protocol,
    required this.category,
    required this.encrypted,
    required this.confidence,
    required this.observations,
  });

  final String service;
  final String protocol;
  final String category;
  final bool encrypted;
  final String confidence;
  final List<String> observations;
}

class _WebReconResult {
  const _WebReconResult({
    this.securityHeaders = const {},
    this.technologies = const [],
  });

  final Map<String, Object?> securityHeaders;
  final List<Map<String, Object?>> technologies;
}

String _csvEscape(Object? value) {
  final text = value?.toString() ?? '';
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String _truncate(String value, int maxLength) {
  if (value.length <= maxLength) return value;
  return value.substring(0, maxLength);
}
