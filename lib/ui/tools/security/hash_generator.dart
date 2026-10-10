/// Hash generator tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/digests/md2.dart';
import 'package:pointycastle/digests/md4.dart';
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha224.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha384.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/digests/ripemd128.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/ripemd320.dart';
import 'package:pointycastle/digests/tiger.dart';
import 'package:pointycastle/digests/whirlpool.dart';
import '../../../services/hash_lookup_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _HashGeneratorView extends StatefulWidget {
  const _HashGeneratorView();

  @override
  State<_HashGeneratorView> createState() => _HashGeneratorViewState();
}

class _HashGeneratorViewState extends State<_HashGeneratorView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _lookupInput = TextEditingController();
  final TextEditingController _wordlist = TextEditingController();
  final TextEditingController _lookupReport = TextEditingController();
  late final HashLookupService _lookupService = HashLookupService();
  bool _lowercase = false;
  bool _lookupRunning = false;
  bool _useDefaultWordlist = true;
  var _hashMode = 0;
  var _lookupStatus = 'Paste a hash, a log line, or text containing hashes.';
  final Map<String, String> _hashes = {};

  @override
  void dispose() {
    _lookupService.close();
    _input.dispose();
    _lookupInput.dispose();
    _wordlist.dispose();
    _lookupReport.dispose();
    super.dispose();
  }

  void _compute() {
    final bytes = utf8.encode(_input.text);
    final digestMap = <String, String>{
      'MD2': _digestHex(MD2Digest(), bytes),
      'MD4': _digestHex(MD4Digest(), bytes),
      'MD5': _digestHex(MD5Digest(), bytes),
      'SHA1': _digestHex(SHA1Digest(), bytes),
      'SHA224': _digestHex(SHA224Digest(), bytes),
      'SHA256': _digestHex(SHA256Digest(), bytes),
      'SHA384': _digestHex(SHA384Digest(), bytes),
      'SHA512': _digestHex(SHA512Digest(), bytes),
      'RIPEMD-128': _digestHex(RIPEMD128Digest(), bytes),
      'RIPEMD-160': _digestHex(RIPEMD160Digest(), bytes),
      'RIPEMD-320': _digestHex(RIPEMD320Digest(), bytes),
      'Tiger': _digestHex(TigerDigest(), bytes),
      'Whirlpool': _digestHex(WhirlpoolDigest(), bytes),
      'Keccak-256': _digestHex(KeccakDigest(256), bytes),
    };
    _hashes
      ..clear()
      ..addAll(
        digestMap.map(
          (key, value) =>
              MapEntry(key, _lowercase ? value.toLowerCase() : value),
        ),
      );
    setState(() {});
  }

  String _digestHex(dynamic digest, List<int> bytes) {
    final out = digest.process(Uint8List.fromList(bytes));
    return bytesToHex(out);
  }

  void _setSample() {
    setState(() => _input.text = 'Ut quidam aut expedita porro ut ipsa ea et');
    _compute();
  }

  Future<void> _copyHash(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  void _useGeneratedHash(String algorithm) {
    final hash = _hashes[algorithm];
    if (hash == null || hash.isEmpty) return;
    setState(() {
      _hashMode = 1;
      _lookupInput.text = hash;
      _lookupStatus = 'Loaded $algorithm hash for lookup.';
    });
    _analyzeLookup();
  }

  List<String> _lookupWords() {
    final words = <String>[
      if (_useDefaultWordlist) ...HashLookupService.defaultWordlist,
      ...const LineSplitter().convert(_wordlist.text),
    ];
    return words;
  }

  void _analyzeLookup() {
    final candidates = HashLookupService.extractCandidates(_lookupInput.text);
    setState(() {
      _lookupStatus = candidates.isEmpty
          ? 'No supported hex hashes found.'
          : '${candidates.length} supported hash${candidates.length == 1 ? '' : 'es'} found.';
      _lookupReport.text = _hashCandidateReport(candidates);
    });
  }

  Future<void> _crackLocal() async {
    if (_lookupRunning) return;
    setState(() {
      _lookupRunning = true;
      _lookupStatus = 'Trying local wordlist...';
    });
    final results = await _lookupService.crackWithWordlist(
      input: _lookupInput.text,
      words: _lookupWords(),
    );
    if (!mounted) return;
    setState(() {
      _lookupRunning = false;
      _lookupStatus = _resultStatus(results, source: 'local wordlist');
      _lookupReport.text = _hashResultReport(results);
    });
  }

  Future<void> _lookupOnline() async {
    if (_lookupRunning) return;
    setState(() {
      _lookupRunning = true;
      _lookupStatus = 'Checking online hash databases...';
    });
    final results = await _lookupService.lookupOnline(input: _lookupInput.text);
    if (!mounted) return;
    setState(() {
      _lookupRunning = false;
      _lookupStatus = _resultStatus(results, source: 'online lookup');
      _lookupReport.text = _hashResultReport(results);
    });
  }

  String _resultStatus(
    List<HashCrackResult> results, {
    required String source,
  }) {
    if (results.isEmpty) return 'No supported hashes found.';
    final cracked = results.where((result) => result.cracked).length;
    if (cracked == 0) return 'No matches from $source.';
    return '$cracked of ${results.length} hash${results.length == 1 ? '' : 'es'} matched from $source.';
  }

  String _hashCandidateReport(List<HashCandidate> candidates) {
    if (candidates.isEmpty) {
      return 'Supported hash lengths: MD5/MD4/MD2, SHA1, SHA224, SHA256, SHA384, SHA512, Keccak-256.';
    }
    final buffer = StringBuffer();
    for (final candidate in candidates) {
      buffer
        ..writeln(candidate.value)
        ..writeln('  possible: ${candidate.label}')
        ..writeln();
    }
    return buffer.toString().trimRight();
  }

  String _hashResultReport(List<HashCrackResult> results) {
    if (results.isEmpty) return 'No supported hashes found.';
    final buffer = StringBuffer();
    for (final result in results) {
      buffer
        ..writeln(result.hash)
        ..writeln('  algorithm: ${result.algorithm}')
        ..writeln('  source: ${result.source}')
        ..writeln('  status: ${result.status}');
      if (result.plaintext != null) {
        buffer.writeln('  plaintext: ${result.plaintext}');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final byteCount = utf8.encode(_input.text).length;
    return ToolSampleAction(
      onPressed: _setSample,
      child: buildAdaptiveSplit(
        initialRatio: 0.62,
        minSecondExtent: 360,
        first: EditorPane(
          label: 'Input',
          actions: [],
          controller: _input,
          onChanged: (_) => _compute(),
          placeholder: 'Enter text to hash...',
        ),
        second: _buildHashSidePanel(context, byteCount),
      ),
    );
  }

  Widget _buildHashSidePanel(BuildContext context, int byteCount) {
    return ToolPanel(
      title: 'Hashes',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SegmentedToggle(
                  options: const ['Generate', 'Lookup'],
                  initialIndex: _hashMode,
                  onChanged: (index) => setState(() => _hashMode = index),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _hashMode == 0
                        ? '$byteCount bytes (string)'
                        : 'Hash-Buster style lookup',
                    overflow: TextOverflow.ellipsis,
                    style: mutedToolTextStyle(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _hashMode == 0
                  ? _buildHashGeneratePanel(context)
                  : _buildHashLookupPanel(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHashGeneratePanel(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _lowercase,
                onChanged: (value) {
                  setState(() => _lowercase = value ?? false);
                  _compute();
                },
              ),
              Text(
                'lowercased',
                style: TextStyle(color: context.appColors.editorText),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _HashField(
            label: 'MD2',
            value: _hashes['MD2'] ?? '',
            onCopy: () => _copyHash(_hashes['MD2'] ?? ''),
          ),
          _HashField(
            label: 'MD4',
            value: _hashes['MD4'] ?? '',
            onCopy: () => _copyHash(_hashes['MD4'] ?? ''),
          ),
          _HashField(
            label: 'MD5',
            value: _hashes['MD5'] ?? '',
            onCopy: () => _copyHash(_hashes['MD5'] ?? ''),
            onUse: () => _useGeneratedHash('MD5'),
          ),
          _HashField(
            label: 'SHA1',
            value: _hashes['SHA1'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA1'] ?? ''),
            onUse: () => _useGeneratedHash('SHA1'),
          ),
          _HashField(
            label: 'SHA224',
            value: _hashes['SHA224'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA224'] ?? ''),
          ),
          _HashField(
            label: 'SHA256',
            value: _hashes['SHA256'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA256'] ?? ''),
            onUse: () => _useGeneratedHash('SHA256'),
          ),
          _HashField(
            label: 'SHA384',
            value: _hashes['SHA384'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA384'] ?? ''),
            onUse: () => _useGeneratedHash('SHA384'),
          ),
          _HashField(
            label: 'SHA512',
            value: _hashes['SHA512'] ?? '',
            onCopy: () => _copyHash(_hashes['SHA512'] ?? ''),
            onUse: () => _useGeneratedHash('SHA512'),
          ),
          _HashField(
            label: 'Keccak-256',
            value: _hashes['Keccak-256'] ?? '',
            onCopy: () => _copyHash(_hashes['Keccak-256'] ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _buildHashLookupPanel(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: toolSurfaceDecoration(context),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hash input',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _HashLookupTextField(
                key: const ValueKey('hash-lookup-input'),
                controller: _lookupInput,
                hint: 'Paste one hash or text containing hashes...',
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => _analyzeLookup(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(
                    value: _useDefaultWordlist,
                    onChanged: _lookupRunning
                        ? null
                        : (value) {
                            setState(() => _useDefaultWordlist = value ?? true);
                          },
                  ),
                  Expanded(
                    child: Text(
                      'Use small built-in wordlist',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: appColors.editorText),
                    ),
                  ),
                ],
              ),
              _HashLookupTextField(
                controller: _wordlist,
                hint: 'Optional wordlist, one candidate per line...',
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ToolButton(
                    label: 'Analyze',
                    onPressed: _lookupRunning ? null : _analyzeLookup,
                  ),
                  ToolButton(
                    label: 'Local crack',
                    onPressed: _lookupRunning ? null : _crackLocal,
                  ),
                  ToolButton(
                    label: 'Online lookup',
                    onPressed: _lookupRunning ? null : _lookupOnline,
                  ),
                  if (_lookupRunning)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_lookupStatus, style: mutedToolTextStyle(context)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: EditorPane(
            label: 'Result',
            controller: _lookupReport,
            readOnly: true,
            placeholder: 'Hash analysis and crack results...',
            showHeader: true,
            actions: const [],
          ),
        ),
      ],
    );
  }
}

Widget buildHashGenerator() {
  return const _HashGeneratorView();
}

class _HashField extends StatelessWidget {
  const _HashField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.onUse,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text('$label:')),
          Expanded(
            child: Container(
              decoration: toolSurfaceDecoration(context, radius: 6),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      6,
                      onUse == null ? 46 : 104,
                      6,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        value,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 11.5,
                          color: context.appColors.editorText,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onUse != null)
                          TextButton(
                            onPressed: value.isEmpty ? null : onUse,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              minimumSize: const Size(0, 22),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(fontSize: 10.5),
                            ),
                            child: const Text('Lookup'),
                          ),
                        TextButton(
                          onPressed: value.isEmpty ? null : onCopy,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            minimumSize: const Size(0, 22),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 10.5),
                          ),
                          child: const Text('Copy'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HashLookupTextField extends StatelessWidget {
  const _HashLookupTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.minLines,
    required this.maxLines,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          isDense: true,
          hintStyle: TextStyle(color: appColors.mutedText),
        ),
        style: TextStyle(
          color: appColors.editorText,
          fontFamily: 'Menlo',
          fontSize: 12.5,
        ),
      ),
    );
  }
}
