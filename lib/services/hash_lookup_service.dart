import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/digests/md2.dart';
import 'package:pointycastle/digests/md4.dart';
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha224.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha384.dart';
import 'package:pointycastle/digests/sha512.dart';

class HashAlgorithmInfo {
  const HashAlgorithmInfo({
    required this.name,
    required this.hexLength,
    required this.digest,
    this.onlineLookup = false,
  });

  final String name;
  final int hexLength;
  final String Function(String value) digest;
  final bool onlineLookup;
}

class HashCandidate {
  const HashCandidate({required this.value, required this.algorithms});

  final String value;
  final List<HashAlgorithmInfo> algorithms;

  String get label => algorithms.isEmpty
      ? 'Unsupported'
      : algorithms.map((algorithm) => algorithm.name).join(', ');
}

class HashCrackResult {
  const HashCrackResult({
    required this.hash,
    required this.algorithm,
    required this.plaintext,
    required this.source,
    required this.status,
  });

  final String hash;
  final String algorithm;
  final String? plaintext;
  final String source;
  final String status;

  bool get cracked => plaintext != null && plaintext!.isNotEmpty;
}

class HashLookupService {
  HashLookupService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final List<HashAlgorithmInfo> algorithms = [
    HashAlgorithmInfo(name: 'MD2', hexLength: 32, digest: _md2Hex),
    HashAlgorithmInfo(name: 'MD4', hexLength: 32, digest: _md4Hex),
    HashAlgorithmInfo(
      name: 'MD5',
      hexLength: 32,
      digest: _md5Hex,
      onlineLookup: true,
    ),
    HashAlgorithmInfo(name: 'SHA1', hexLength: 40, digest: _sha1Hex),
    HashAlgorithmInfo(name: 'SHA224', hexLength: 56, digest: _sha224Hex),
    HashAlgorithmInfo(name: 'SHA256', hexLength: 64, digest: _sha256Hex),
    HashAlgorithmInfo(name: 'Keccak-256', hexLength: 64, digest: _keccak256Hex),
    HashAlgorithmInfo(name: 'SHA384', hexLength: 96, digest: _sha384Hex),
    HashAlgorithmInfo(name: 'SHA512', hexLength: 128, digest: _sha512Hex),
  ];

  static const List<String> defaultWordlist = [
    'admin',
    'password',
    'password1',
    'letmein',
    'welcome',
    'devutils',
    'test',
    'hello',
    'abc',
    'qwerty',
    'secret',
    'changeme',
    'root',
    'toor',
  ];

  static List<HashCandidate> extractCandidates(String input) {
    final seen = <String>{};
    final candidates = <HashCandidate>[];
    final matches = RegExp(
      r'(?:^|[^a-fA-F0-9])([a-fA-F0-9]{128}|[a-fA-F0-9]{96}|[a-fA-F0-9]{64}|[a-fA-F0-9]{56}|[a-fA-F0-9]{40}|[a-fA-F0-9]{32})(?=$|[^a-fA-F0-9])',
    ).allMatches(input);

    for (final match in matches) {
      final value = match.group(1)!.toLowerCase();
      if (seen.add(value)) candidates.add(identify(value));
    }

    final compact = input.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (candidates.isEmpty &&
        RegExp(r'^[a-f0-9]+$').hasMatch(compact) &&
        seen.add(compact)) {
      candidates.add(identify(compact));
    }

    return candidates;
  }

  static HashCandidate identify(String hash) {
    final normalized = hash.trim().toLowerCase();
    final matches = algorithms
        .where((algorithm) => algorithm.hexLength == normalized.length)
        .toList();
    return HashCandidate(value: normalized, algorithms: matches);
  }

  Future<List<HashCrackResult>> crackWithWordlist({
    required String input,
    required List<String> words,
    int maxWords = 10000,
  }) async {
    final candidates = extractCandidates(input);
    if (candidates.isEmpty) return const [];

    final wordlist = _cleanWordlist(words).take(maxWords).toList();
    final results = <HashCrackResult>[];

    for (final candidate in candidates) {
      HashCrackResult? found;
      for (final algorithm in candidate.algorithms) {
        for (final word in wordlist) {
          if (algorithm.digest(word) == candidate.value) {
            found = HashCrackResult(
              hash: candidate.value,
              algorithm: algorithm.name,
              plaintext: word,
              source: 'Local wordlist',
              status: 'Matched',
            );
            break;
          }
        }
        if (found != null) break;
      }
      results.add(
        found ??
            HashCrackResult(
              hash: candidate.value,
              algorithm: candidate.label,
              plaintext: null,
              source: 'Local wordlist',
              status: wordlist.isEmpty ? 'No words to try' : 'Not found',
            ),
      );
    }

    return results;
  }

  Future<List<HashCrackResult>> lookupOnline({
    required String input,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    final candidates = extractCandidates(input);
    if (candidates.isEmpty) return const [];

    final results = <HashCrackResult>[];
    for (final candidate in candidates) {
      final md5Algorithms = candidate.algorithms.where(
        (algorithm) => algorithm.name == 'MD5',
      );
      final md5 = md5Algorithms.isEmpty ? null : md5Algorithms.first;
      if (md5 == null) {
        results.add(
          HashCrackResult(
            hash: candidate.value,
            algorithm: candidate.label,
            plaintext: null,
            source: 'Online lookup',
            status: 'No configured online source for this hash length',
          ),
        );
        continue;
      }

      final found = await _lookupNitrxgenMd5(candidate.value, timeout);
      results.add(
        HashCrackResult(
          hash: candidate.value,
          algorithm: md5.name,
          plaintext: found,
          source: 'nitrxgen MD5 DB',
          status: found == null ? 'Not found' : 'Matched',
        ),
      );
    }

    return results;
  }

  void close() {
    _client.close();
  }

  Future<String?> _lookupNitrxgenMd5(String hash, Duration timeout) async {
    try {
      final response = await _client
          .get(Uri.parse('https://www.nitrxgen.net/md5db/$hash'))
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = response.body.trim();
      return body.isEmpty ? null : body;
    } on Object {
      return null;
    }
  }

  static List<String> _cleanWordlist(List<String> words) {
    final seen = <String>{};
    final output = <String>[];
    for (final word in words) {
      final value = word.trim();
      if (value.isEmpty) continue;
      if (seen.add(value)) output.add(value);
    }
    return output;
  }

  static String _md2Hex(String value) => _digestHex(MD2Digest(), value);
  static String _md4Hex(String value) => _digestHex(MD4Digest(), value);
  static String _md5Hex(String value) => _digestHex(MD5Digest(), value);
  static String _sha1Hex(String value) => _digestHex(SHA1Digest(), value);
  static String _sha224Hex(String value) => _digestHex(SHA224Digest(), value);
  static String _sha256Hex(String value) => _digestHex(SHA256Digest(), value);
  static String _sha384Hex(String value) => _digestHex(SHA384Digest(), value);
  static String _sha512Hex(String value) => _digestHex(SHA512Digest(), value);
  static String _keccak256Hex(String value) =>
      _digestHex(KeccakDigest(256), value);

  static String _digestHex(dynamic digest, String value) {
    final bytes = Uint8List.fromList(utf8.encode(value));
    return _bytesToHex(digest.process(bytes)).toLowerCase();
  }

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
