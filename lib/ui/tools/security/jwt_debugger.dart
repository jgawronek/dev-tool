/// JWT debugger tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../../tool_sample_action.dart';

String _base64UrlNoPad(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

Uint8List _base64UrlDecode(String input) {
  final normalized = base64Url.normalize(input);
  return Uint8List.fromList(base64Url.decode(normalized));
}

class _JwtDebuggerView extends StatefulWidget {
  const _JwtDebuggerView();

  @override
  State<_JwtDebuggerView> createState() => _JwtDebuggerViewState();
}

class _JwtDebuggerViewState extends State<_JwtDebuggerView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _header = TextEditingController();
  final TextEditingController _payload = TextEditingController();
  final TextEditingController _secret = TextEditingController();
  static const _supportedAlgorithms = ['HS256', 'HS384', 'HS512'];
  String _alg = 'HS256';
  String _status = 'Signature Not Verified';
  Color _statusColor = const Color(0xFFB0B0B0);
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _header.dispose();
    _payload.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _parse({bool readAlgorithm = true}) {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _header.clear();
        _payload.clear();
        _status = 'Signature Not Verified';
        _statusColor = const Color(0xFFB0B0B0);
        _error = null;
      });
      return;
    }
    final parts = raw.split('.');
    if (parts.length < 2) {
      _showParseError(
        'Invalid JWT format. Paste a token with header and payload segments.',
      );
      return;
    }
    try {
      final headerJson = utf8.decode(_base64UrlDecode(parts[0]));
      final payloadJson = utf8.decode(_base64UrlDecode(parts[1]));
      _header.text = _prettyJson(headerJson);
      _payload.text = _prettyJson(payloadJson);
      final headerMap = jsonDecode(headerJson);
      if (readAlgorithm && headerMap is Map && headerMap['alg'] is String) {
        _alg = headerMap['alg'] as String;
      }
      _verifySignature(parts);
      setState(() => _error = null);
    } catch (_) {
      _showParseError(
        'Unable to decode this token. Check its header and payload encoding.',
      );
    }
  }

  void _showParseError(String message) {
    setState(() {
      _header.clear();
      _payload.clear();
      _error = message;
      _status = 'Signature Not Verified';
      _statusColor = const Color(0xFFB0B0B0);
    });
  }

  void _verifySignature(List<String> parts) {
    if (!_supportedAlgorithms.contains(_alg)) {
      setState(() {
        _status = 'Unsupported algorithm: $_alg';
        _statusColor = const Color(0xFFB0B0B0);
      });
      return;
    }
    if (parts.length < 3 || _secret.text.isEmpty) {
      setState(() {
        _status = 'Signature Not Verified';
        _statusColor = const Color(0xFFB0B0B0);
      });
      return;
    }
    final signingInput = '${parts[0]}.${parts[1]}';
    final secret = utf8.encode(_secret.text);
    crypto.Digest digest;
    switch (_alg) {
      case 'HS384':
        digest = crypto.Hmac(
          crypto.sha384,
          secret,
        ).convert(utf8.encode(signingInput));
        break;
      case 'HS512':
        digest = crypto.Hmac(
          crypto.sha512,
          secret,
        ).convert(utf8.encode(signingInput));
        break;
      case 'HS256':
      default:
        digest = crypto.Hmac(
          crypto.sha256,
          secret,
        ).convert(utf8.encode(signingInput));
        break;
    }
    final computed = _base64UrlNoPad(digest.bytes);
    final valid = computed == parts[2];
    setState(() {
      _status = valid ? 'Signature Verified' : 'Signature Mismatch';
      _statusColor = valid ? const Color(0xFF5DBB63) : const Color(0xFFD96B6B);
    });
  }

  String _prettyJson(String input) {
    try {
      final decoded = jsonDecode(input);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return input;
    }
  }

  void _setSample() {
    const header = '{"typ":"JWT","alg":"HS256"}';
    const payload = '{"sub":"1234567890","name":"John Doe","iat":1516239022}';
    final encodedHeader = _base64UrlNoPad(utf8.encode(header));
    final encodedPayload = _base64UrlNoPad(utf8.encode(payload));
    setState(() => _input.text = '$encodedHeader.$encodedPayload.');
    _parse();
  }

  Future<void> _copyInput() async {
    await Clipboard.setData(ClipboardData(text: _input.text));
  }

  Future<void> _copyHeader() async {
    await Clipboard.setData(ClipboardData(text: _header.text));
  }

  Future<void> _copyPayload() async {
    await Clipboard.setData(ClipboardData(text: _payload.text));
  }

  Widget _framedPanel(
    BuildContext context, {
    required String title,
    required Widget body,
    required bool expand,
    VoidCallback? onCopy,
  }) {
    return ToolPanel(
      title: title,
      expand: expand,
      actions: [
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 17),
            tooltip: 'Copy $title',
            onPressed: onCopy,
            visualDensity: VisualDensity.compact,
          ),
      ],
      child: body,
    );
  }

  Widget _tokenDetails(BuildContext context, {required bool expand}) {
    final colors = context.appColors;
    final hasToken = _input.text.trim().isNotEmpty && _error == null;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Algorithm',
                      style: TextStyle(color: colors.mutedText),
                    ),
                    Container(
                      width: 180,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: toolSurfaceDecoration(context),
                      child: Semantics(
                        label: 'Signature algorithm',
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _supportedAlgorithms.contains(_alg)
                                ? _alg
                                : null,
                            hint: Text('$_alg (unsupported)'),
                            isDense: true,
                            isExpanded: true,
                            items: [
                              for (final algorithm in _supportedAlgorithms)
                                DropdownMenuItem(
                                  value: algorithm,
                                  child: Text(algorithm),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _alg = value);
                              _parse(readAlgorithm: false);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final detail in <(String, String)>[
                ('Type', hasToken ? 'JWT' : '—'),
                (
                  'Segments',
                  hasToken ? '${_input.text.trim().split('.').length}' : '—',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          detail.$1,
                          style: TextStyle(color: colors.mutedText),
                        ),
                      ),
                      Text(detail.$2),
                    ],
                  ),
                ),
              const Divider(height: 24),
              const Text('Signature status'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.circle, size: 10, color: _statusColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Enter the secret to check the token signature.',
                style: TextStyle(color: colors.mutedText, height: 1.5),
              ),
              const SizedBox(height: 20),
              const Text('Secret'),
              const SizedBox(height: 8),
              TextField(
                controller: _secret,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Enter secret key…',
                ),
                onChanged: (_) => _parse(readAlgorithm: false),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: hasToken && _secret.text.isNotEmpty
                      ? () => _parse(readAlgorithm: false)
                      : null,
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: const Text('Verify signature'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: errorToolTextStyle(context)),
              ],
            ],
          ),
        ),
      ],
    );
    return _framedPanel(
      context,
      title: 'Token details',
      expand: expand,
      body: expand ? SingleChildScrollView(child: body) : body,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: Padding(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            final header = _framedPanel(
              context,
              title: 'Header',
              expand: wide,
              onCopy: _copyHeader,
              body: EditorPane(
                label: 'Header',
                actions: const [],
                controller: _header,
                readOnly: true,
                showHeader: false,
                bordered: false,
                placeholder: 'Decoded header will appear here',
                expand: wide,
                fixedHeight: 170,
              ),
            );
            final payload = _framedPanel(
              context,
              title: 'Payload',
              expand: wide,
              onCopy: _copyPayload,
              body: EditorPane(
                label: 'Payload',
                actions: const [],
                controller: _payload,
                readOnly: true,
                showHeader: false,
                bordered: false,
                placeholder: 'Decoded payload will appear here',
                expand: wide,
                fixedHeight: 220,
              ),
            );
            final token = SizedBox(
              height: 140,
              child: EditorPane(
                label: 'Token',
                actions: [],
                controller: _input,
                onChanged: (_) => _parse(),
                placeholder: 'Paste a JWT to decode its header and payload…',
                copyAction: _copyInput,
              ),
            );
            final details = _tokenDetails(context, expand: wide);
            if (!wide) {
              return ListView(
                children: [
                  token,
                  const SizedBox(height: 16),
                  header,
                  const SizedBox(height: 16),
                  payload,
                  const SizedBox(height: 16),
                  details,
                ],
              );
            }
            return Column(
              children: [
                token,
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: header),
                      const SizedBox(width: 14),
                      Expanded(child: payload),
                      const SizedBox(width: 14),
                      SizedBox(width: 280, child: details),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Widget buildJwtDebugger() {
  return const _JwtDebuggerView();
}
