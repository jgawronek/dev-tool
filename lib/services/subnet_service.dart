/// IPv4/IPv6 subnet math for the subnet calculator.
library;

import 'dart:math';

/// Every field of a calculated subnet, in display order.
class SubnetInfo {
  const SubnetInfo({
    required this.version,
    required this.prefixLength,
    required this.networkAddress,
    required this.netmask,
    required this.broadcastAddress,
    required this.wildcardMask,
    required this.firstHost,
    required this.lastHost,
    required this.totalAddresses,
    required this.usableHosts,
    required this.networkHosts,
    required this.broadcastHosts,
    required this.ipClass,
    required this.isPrivate,
    required this.isLoopback,
    required this.isMulticast,
    required this.isLinkLocal,
  });

  final int version;
  final int prefixLength;
  final String networkAddress;
  final String netmask;
  final String broadcastAddress;
  final String wildcardMask;
  final String firstHost;
  final String lastHost;
  final String totalAddresses;
  final String usableHosts;
  final String networkHosts;
  final String broadcastHosts;

  /// Legacy IPv4 class letter (A-E), or null for IPv6.
  final String? ipClass;
  final bool isPrivate;
  final bool isLoopback;
  final bool isMulticast;
  final bool isLinkLocal;

  /// Rendered as the panel text.
  String toReport() {
    final buffer = StringBuffer()
      ..writeln('Network address     $networkAddress/$prefixLength')
      ..writeln('Netmask             $netmask')
      ..writeln('Wildcard mask       $wildcardMask')
      ..writeln('Broadcast           $broadcastAddress')
      ..writeln('First host          $firstHost')
      ..writeln('Last host           $lastHost')
      ..writeln('Total addresses     $totalAddresses')
      ..writeln('Usable hosts        $usableHosts');
    if (ipClass != null) {
      buffer
        ..writeln('Class               $ipClass')
        ..writeln('Private             ${isPrivate ? 'yes' : 'no'}');
    }
    if (isLoopback) buffer.writeln('Loopback            yes');
    if (isMulticast) buffer.writeln('Multicast           yes');
    if (isLinkLocal) buffer.writeln('Link-local          yes');
    return buffer.toString().trimRight();
  }
}

/// Result of a subnet calculation.
class SubnetOutcome {
  const SubnetOutcome.success(this.info) : error = null;
  const SubnetOutcome.failure(this.error) : info = null;

  final SubnetInfo? info;
  final String? error;
}

/// Calculates subnet details for [address], which may include a `/prefix`
/// suffix. When no prefix is given, [defaultPrefix] is assumed.
SubnetOutcome calculateSubnet(String address, {int? defaultPrefix}) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) {
    return const SubnetOutcome.failure('Enter an IP address, e.g. 192.168.1.10/24.');
  }

  final slash = trimmed.indexOf('/');
  final host = slash < 0 ? trimmed : trimmed.substring(0, slash);
  String? prefixText = slash < 0 ? null : trimmed.substring(slash + 1).trim();

  if (host.contains(':')) {
    return _calculateV6(host, prefixText ?? '64', defaultPrefix);
  }
  return _calculateV4(host, prefixText);
}

SubnetOutcome _calculateV4(String host, String? prefixText) {
  final octets = host.split('.');
  if (octets.length != 4) {
    return SubnetOutcome.failure(
      'IPv4 addresses need four octets, got "${host.split('.').length}".',
    );
  }
  var value = 0;
  for (final octet in octets) {
    if (octet.isEmpty || int.tryParse(octet) == null) {
      return const SubnetOutcome.failure('Octets must be numbers.');
    }
    final n = int.parse(octet);
    if (n < 0 || n > 255) {
      return SubnetOutcome.failure('Octet "$n" is outside 0-255.');
    }
    value = (value << 8) | n;
  }

  var prefix = 32;
  if (prefixText != null && prefixText.isNotEmpty) {
    final parsed = int.tryParse(prefixText);
    if (parsed == null) return const SubnetOutcome.failure('Prefix must be a number.');
    if (parsed < 0 || parsed > 32) {
      return SubnetOutcome.failure('IPv4 prefix must be 0-32, got $parsed.');
    }
    prefix = parsed;
  }

  final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
  final network = value & mask;
  final broadcast = network | (~mask & 0xffffffff);

  // /31 (RFC 3021) has no network/broadcast reservation; /32 is a host route
  // whose single address is itself usable.
  final totalHosts = _formatCount(_hostCount(prefix));
  final reserved = switch (prefix) {
    31 || 32 => 0,
    _ => 2,
  };
  final usable = prefix == 32 ? 1 : max(0, _hostCount(prefix) - reserved);

  return SubnetOutcome.success(
    SubnetInfo(
      version: 4,
      prefixLength: prefix,
      networkAddress: _v4(network),
      netmask: _v4(mask),
      broadcastAddress: _v4(broadcast),
      wildcardMask: _v4(~mask & 0xffffffff),
      firstHost: _v4(network + (reserved == 0 ? 0 : 1)),
      lastHost: _v4(broadcast - (reserved == 0 ? 0 : 1)),
      totalAddresses: totalHosts,
      usableHosts: _formatCount(usable),
      networkHosts: reserved == 0 ? 'n/a (/$prefix)' : _v4(network),
      broadcastHosts: reserved == 0 ? 'n/a (/$prefix)' : _v4(broadcast),
      ipClass: _ipClass(network),
      isPrivate: _isPrivateV4(network),
      isLoopback: network >> 24 == 127,
      isMulticast: network >> 24 == 224,
      isLinkLocal: network >> 16 == 0xa9fe,
    ),
  );
}

SubnetOutcome _calculateV6(String host, String prefixText, int? fallback) {
  final expanded = _expandV6(host);
  if (expanded == null) {
    return const SubnetOutcome.failure(
      'Not a valid IPv6 address (check for "::" compression or embedded IPv4).',
    );
  }

  var prefix = fallback ?? 64;
  if (prefixText.isNotEmpty) {
    final parsed = int.tryParse(prefixText);
    if (parsed == null) {
      return const SubnetOutcome.failure('Prefix must be a number.');
    }
    if (parsed < 0 || parsed > 128) {
      return SubnetOutcome.failure('IPv6 prefix must be 0-128, got $parsed.');
    }
    prefix = parsed;
  }

  final groups = List<int>.from(expanded);
  final networkGroups = List<int>.from(groups);
  for (var i = 0; i < 8; i++) {
    final bitsBefore = i * 16;
    if (prefix >= bitsBefore + 16) continue;
    if (prefix <= bitsBefore) {
      networkGroups[i] = 0;
      continue;
    }
    final keep = prefix - bitsBefore;
    networkGroups[i] = groups[i] & ((1 << keep) - 1) << (16 - keep);
  }

  final maskGroups = _maskGroups(prefix);
  final network = _compressV6(networkGroups);
  final mask = _compressV6(maskGroups);
  final wildcard = _compressV6([
    for (final g in maskGroups) (~g) & 0xffff,
  ]);

  final total = _hostCountV6(prefix);
  final usable = total <= 2 ? total : total - 2;

  return SubnetOutcome.success(
    SubnetInfo(
      version: 6,
      prefixLength: prefix,
      networkAddress: network,
      netmask: mask,
      broadcastAddress: 'n/a (IPv6)',
      wildcardMask: wildcard,
      firstHost: network,
      lastHost: '...${_compressV6([
            for (var i = 0; i < 8; i++)
              networkGroups[i] == 0xffff ? 0xffff : 0xffff,
          ])} (end of range)',
      totalAddresses: _formatCount(total),
      usableHosts: _formatCount(usable),
      networkHosts: 'n/a (IPv6)',
      broadcastHosts: 'n/a (IPv6)',
      ipClass: null,
      isPrivate: _isUniqueLocal(networkGroups),
      isLoopback: _isV6Loopback(networkGroups),
      isMulticast: networkGroups[0] == 0xff00,
      isLinkLocal: networkGroups[0] == 0xfe80,
    ),
  );
}

List<int> _maskGroups(int prefix) {
  final groups = <int>[];
  var remaining = prefix;
  for (var i = 0; i < 8; i++) {
    if (remaining >= 16) {
      groups.add(0xffff);
      remaining -= 16;
    } else if (remaining > 0) {
      groups.add(((1 << remaining) - 1) << (16 - remaining));
      remaining = 0;
    } else {
      groups.add(0);
    }
  }
  return groups;
}

/// Expands `::` notation into eight 16-bit groups, or null if malformed.
List<int>? _expandV6(String input) {
  var text = input.trim();
  if (text.isEmpty || text.length > 45) return null;

  // A trailing dotted-quad (::ffff:192.168.1.1) becomes two hex groups.
  final lastColon = text.lastIndexOf(':');
  final tail = text.substring(lastColon + 1);
  if (tail.contains('.')) {
    final v4 = _calculateV4(tail, '32');
    final info = v4.info;
    if (info == null) return null;
    final octets = info.networkAddress.split('.').map(int.parse).toList();
    final high = (octets[0] << 8) | octets[1];
    final low = (octets[2] << 8) | octets[3];
    text = '${text.substring(0, lastColon + 1)}${high.toRadixString(16)}:'
        '${low.toRadixString(16)}';
  }

  final doubleColon = text.indexOf('::');
  final groups = <int>[];
  if (doubleColon >= 0) {
    if (text.indexOf('::', doubleColon + 1) >= 0) return null;
    final head = text.substring(0, doubleColon);
    final rest = text.substring(doubleColon + 2);
    final headGroups = _hexGroups(head);
    final restGroups = _hexGroups(rest);
    if (headGroups == null || restGroups == null) return null;
    final missing = 8 - headGroups.length - restGroups.length;
    if (missing < 1) return null;
    groups
      ..addAll(headGroups)
      ..addAll(List<int>.filled(missing, 0))
      ..addAll(restGroups);
  } else {
    final parsed = _hexGroups(text);
    if (parsed == null) return null;
    groups.addAll(parsed);
  }
  if (groups.length != 8) return null;
  return groups;
}

List<int>? _hexGroups(String text) {
  if (text.isEmpty) return const [];
  final out = <int>[];
  for (final part in text.split(':')) {
    if (part.isEmpty || part.length > 4) return null;
    final value = int.tryParse(part, radix: 16);
    if (value == null) return null;
    out.add(value);
  }
  return out;
}

/// Renders groups with the longest run of zeroes replaced by `::`.
///
/// Follows RFC 5952: lowercase hex, no leading zeros, leftmost longest run,
/// and a single zero group written out rather than compressed.
String _compressV6(List<int> groups) {
  var bestStart = -1;
  var bestLength = 0;
  var index = 0;
  while (index < groups.length) {
    if (groups[index] != 0) {
      index++;
      continue;
    }
    var end = index;
    while (end < groups.length && groups[end] == 0) {
      end++;
    }
    if (end - index > bestLength) {
      bestLength = end - index;
      bestStart = index;
    }
    index = end;
  }
  final hex = groups.map((g) => g.toRadixString(16)).toList();
  if (bestLength < 2) {
    return hex.join(':');
  }
  final head = hex.sublist(0, bestStart).join(':');
  final tail = hex.sublist(bestStart + bestLength).join(':');
  return '$head::$tail';
}

/// IPv6 loopback is `::1`, so the unit lives in the final group.
bool _isV6Loopback(List<int> groups) {
  if (groups.length != 8 || groups[7] != 1) return false;
  for (var i = 0; i < 7; i++) {
    if (groups[i] != 0) return false;
  }
  return true;
}

bool _isUniqueLocal(List<int> groups) => (groups[0] & 0xfe00) == 0xfc00;

String _v4(int value) =>
    '${(value >> 24) & 0xff}.${(value >> 16) & 0xff}.'
    '${(value >> 8) & 0xff}.${value & 0xff}';

String _ipClass(int network) {
  final first = (network >> 24) & 0xff;
  final second = (network >> 16) & 0xff;
  if (first == 0) return 'reserved (0)';
  if (first < 127) return 'A (1-126)';
  if (first == 127) return 'loopback (127)';
  if (first < 192) return 'B (128-191)';
  if (first == 192 && second == 168) return 'C private (192.168)';
  if (first < 224) return 'C (192-223)';
  if (first < 240) return 'D multicast (224-239)';
  return 'E reserved (240-255)';
}

bool _isPrivateV4(int network) {
  final a = (network >> 24) & 0xff;
  final b = (network >> 16) & 0xff;
  return a == 10 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b <= 127) ||
      (a == 169 && b == 254);
}

int _hostCount(int prefix) => prefix == 0 ? 0x100000000 : 1 << (32 - prefix);

int _hostCountV6(int prefix) {
  if (prefix >= 128) return 1;
  // Beyond 2^32 the value no longer fits in an int, so describe it in words.
  return 1 << (128 - prefix);
}

String _formatCount(int count) {
  if (count >= 0x100000000) return '2^${_log2(count)} (very large)';
  final text = count.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

int _log2(int value) {
  var bits = 0;
  var n = value;
  while (n > 1) {
    n >>= 1;
    bits++;
  }
  return bits;
}

/// Splits a subnet into the next size /24 blocks, up to [limit] of them.
///
/// Handy for turning a scan result into a concrete list of targets.
List<String> enumerateSubnets(SubnetInfo info, {int limit = 256}) {
  final octets = info.networkAddress.split('.').map(int.parse).toList();
  final isShortPrefix = info.prefixLength <= 16;
  if (isShortPrefix) {
    // Too many /24s to enumerate; describe the range instead.
    return [
      'Prefix /${info.prefixLength} is too large to enumerate. '
          'Narrow it to /${info.prefixLength > 20 ? 20 : info.prefixLength + 4} or smaller.',
    ];
  }
  final out = <String>[];
  for (var third = 0; third < 256 && out.length < limit; third++) {
    for (var fourth = 0; fourth < 256 && out.length < limit; fourth++) {
      out.add('${octets[0]}.${octets[1]}.$third.$fourth/24');
    }
    if (octets[2] == third && info.prefixLength >= 24) break;
  }
  return out;
}