/// JWT debugger tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

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

  void _parse() {
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
      setState(() => _error = 'Invalid JWT format.');
      return;
    }
    try {
      final headerJson = utf8.decode(_base64UrlDecode(parts[0]));
      final payloadJson = utf8.decode(_base64UrlDecode(parts[1]));
      _header.text = _prettyJson(headerJson);
      _payload.text = _prettyJson(payloadJson);
      final headerMap = jsonDecode(headerJson);
      if (headerMap is Map && headerMap['alg'] is String) {
        _alg = headerMap['alg'] as String;
      }
      _verifySignature(parts);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _verifySignature(List<String> parts) {
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

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() => _input.text = text);
    _parse();
  }

  void _setSample() {
    const header = '{"typ":"JWT","alg":"HS256"}';
    const payload = '{"sub":"1234567890","name":"John Doe","iat":1516239022}';
    final encodedHeader = _base64UrlNoPad(utf8.encode(header));
    final encodedPayload = _base64UrlNoPad(utf8.encode(payload));
    setState(() => _input.text = '$encodedHeader.$encodedPayload.');
    _parse();
  }

  void _clearInput() {
    setState(() {
      _input.clear();
      _header.clear();
      _payload.clear();
      _error = null;
    });
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 980;
        final inputPane = EditorPane(
          label: 'Input',
          actions: [
            ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
            ToolButton(label: 'Sample', onPressed: _setSample),
            ToolButton(label: 'Clear', onPressed: _clearInput),
            const ToolIconButton(icon: Icons.settings),
            SmallDropdown(
              items: const ['HS256', 'HS384', 'HS512'],
              initialValue: _alg,
              onChanged: (value) {
                setState(() => _alg = value);
                _parse();
              },
            ),
          ],
          controller: _input,
          onChanged: (_) => _parse(),
          placeholder: 'Paste JWT here...',
          copyAction: _copyInput,
        );
        final detailPane = ListView(
          padding: EdgeInsets.zero,
          children: [
            EditorPane(
              label: 'Header',
              actions: const [],
              controller: _header,
              readOnly: true,
              placeholder: '{ "typ": "JWT", "alg": "HS256" }',
              expand: false,
              fixedHeight: 110,
              copyAction: _copyHeader,
            ),
            const SizedBox(height: 12),
            EditorPane(
              label: 'Payload',
              actions: const [],
              controller: _payload,
              readOnly: true,
              placeholder: '{ "sub": "1234567890" }',
              expand: false,
              fixedHeight: 110,
              copyAction: _copyPayload,
            ),
            const SizedBox(height: 12),
            const Text(
              'Signature',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: toolSurfaceDecoration(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('HMACSHA256(', style: TextStyle(fontSize: 11)),
                  Text(
                    '  base64UrlEncode(header) + "." +',
                    style: TextStyle(fontSize: 11),
                  ),
                  Text(
                    '  base64UrlEncode(payload) + "." +',
                    style: TextStyle(fontSize: 11),
                  ),
                  Text('  your-secret', style: TextStyle(fontSize: 11)),
                  Text(')', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            InlineTextField(
              hintText: 'your-secret',
              controller: _secret,
              onChanged: (_) => _parse(),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  _status,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: errorToolTextStyle(context)),
            ],
          ],
        );
        return ResizableSplit(
          horizontal: horizontal,
          initialRatio: horizontal ? 0.65 : 0.5,
          minSecondExtent: horizontal ? 320 : 260,
          first: inputPane,
          second: detailPane,
        );
      },
    );
  }
}

Widget buildJwtDebugger() {
  return const _JwtDebuggerView();
}
