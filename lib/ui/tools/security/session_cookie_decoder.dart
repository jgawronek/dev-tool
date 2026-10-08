/// Session cookie decoder tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';
import '../../../services/session_cookie_service.dart';

class _SessionCookieDecoderView extends StatefulWidget {
  const _SessionCookieDecoderView();

  @override
  State<_SessionCookieDecoderView> createState() =>
      _SessionCookieDecoderViewState();
}

class _SessionCookieDecoderViewState
    extends State<_SessionCookieDecoderView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final outcome = decodeSession(_input.text);
    _output.text = renderSessionReport(outcome);
    setState(() {});
  }

  void _setSample() {
    setState(() {
      _input.text = 'eyJfdXNlcl9pZCI6IjEiLCJjYXJ0IjpbImEiLCJiIl0s'
          'ImNzcmZfdG9rZW4iOiJ4eXoifQ.asfX7Q.59fSDM_OJOr-Ik5lbIv2TKTF2v8';
    });
    _run();
  }

  void _clear() {
    setState(() {
      _input.clear();
      _output.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final outcome = decodeSession(_input.text);
    return Column(
      children: [
        Expanded(
          child: buildSplitEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _run),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clear),
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
            inputPlaceholder: 'Paste a session cookie or token',
            outputPlaceholder: 'Decoded contents',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _input.text.isEmpty
                  ? 'Nothing to decode yet.'
                  : 'Detected: ${outcome.format.label}',
              style: mutedToolTextStyle(context),
            ),
          ),
        ),
      ],
    );
  }
}

Widget buildSessionCookieDecoder() => const _SessionCookieDecoderView();
