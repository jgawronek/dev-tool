/// ASN.1 / TLV decoder tool view.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';
import '../../../services/asn1_service.dart';
import '../../tool_sample_action.dart';

class _Asn1DecoderView extends StatefulWidget {
  const _Asn1DecoderView();

  @override
  State<_Asn1DecoderView> createState() => _Asn1DecoderViewState();
}

class _Asn1DecoderViewState extends State<_Asn1DecoderView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  Asn1DecodeMode _mode = Asn1DecodeMode.der;
  bool _pem = true;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  /// Accepts PEM, bare Base64, and hex so a user can paste whatever they have.
  List<int> _decodeInput(String raw, String input) {
    var text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('Paste a certificate, DER blob, or hex.');
    }
    if (_pem && text.contains('-----BEGIN')) {
      final match = RegExp(
        r'-----BEGIN [^-]+-----(.*?)-----END [^-]+-----',
        dotAll: true,
      ).firstMatch(text);
      if (match == null) {
        throw const FormatException('PEM markers are present but malformed.');
      }
      text = match.group(1)!.replaceAll(RegExp(r'\s'), '');
      return base64Decode(text);
    }
    if (_pem) {
      final compact = text.replaceAll(RegExp(r'\s'), '');
      if (RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(compact)) {
        try {
          return base64Decode(compact);
        } on FormatException {
          // Fall through to the hex path.
        }
      }
    }
    final cleaned = text
        .replaceAll(RegExp(r'0x'), '')
        .replaceAll(RegExp(r'[\s:,_-]'), '');
    if (cleaned.isEmpty) {
      throw const FormatException('No hex digits found in the input.');
    }
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) {
      throw const FormatException('Input is neither PEM, Base64, nor hex.');
    }
    if (cleaned.length.isOdd) {
      throw const FormatException(
        'Hex input has an odd number of digits; a byte needs two.',
      );
    }
    return [
      for (var i = 0; i < cleaned.length; i += 2)
        int.parse(cleaned.substring(i, i + 2), radix: 16),
    ];
  }

  void _run() {
    try {
      final bytes = _decodeInput(_input.text, _input.text);
      final outcome = decodeAsn1(bytes, mode: _mode);
      _output.text = renderAsn1Report(outcome);
      setState(() {
        _error = outcome.error;
        _status = outcome.error != null
            ? 'Could not decode ${bytes.length} byte(s).'
            : '${bytes.length} byte(s) decoded into ${outcome.nodeCount} '
                  'node(s).';
      });
    } on FormatException catch (error) {
      _output.clear();
      setState(() {
        _error = error.message;
        _status = null;
      });
    }
  }

  void _setSample() {
    setState(() {
      _input.text = _mode == Asn1DecodeMode.der
          // SEQUENCE { INTEGER 5, UTF8String "Hi" }
          ? '30 07 02 01 05 0C 02 48 69'
          // EMV-style TLV: nested templates under 0x6F.
          : '6F 0B 84 01 01 02 01 1E 5F 03 A0 01 41';
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        children: [
          Expanded(
            child: buildSplitEditors(
              inputActions: [
                ToolButton(label: 'Go', onPressed: _run),

                SegmentedToggle(
                  options: const ['ASN.1 (DER)', 'Generic TLV'],
                  initialIndex: _mode.index,
                  onChanged: (index) {
                    setState(() => _mode = Asn1DecodeMode.values[index]);
                    _run();
                  },
                ),
                ToolButton(
                  label: _pem ? 'Input: PEM/Base64/hex' : 'Input: hex only',
                  onPressed: () {
                    setState(() => _pem = !_pem);
                    _run();
                  },
                ),
              ],
              outputActions: [
                ToolButton(
                  label: 'Copy',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _output.text)),
                ),
              ],
              inputController: _input,
              outputController: _output,
              inputPlaceholder: 'Paste a PEM certificate or DER/hex bytes',
              outputPlaceholder: 'Tag tree',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!, style: errorToolTextStyle(context)),
              ),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_status!, style: mutedToolTextStyle(context)),
              ),
            ),
        ],
      ),
    );
  }
}

Widget buildAsn1Decoder() => const _Asn1DecoderView();
