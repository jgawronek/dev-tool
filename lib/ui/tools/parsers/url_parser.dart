/// URL parser and HTTP request tool view.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../services/url_request_service.dart';
import '../../tool_sample_action.dart';
import '../../widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';

class _UrlParserView extends StatefulWidget {
  const _UrlParserView();

  @override
  State<_UrlParserView> createState() => _UrlParserViewState();
}

class _UrlParserViewState extends State<_UrlParserView> {
  final _input = TextEditingController();
  final _queryJson = TextEditingController();
  final _headers = TextEditingController();
  final _body = TextEditingController();
  final _response = TextEditingController();
  final _responseHeaders = TextEditingController();
  Uri? _uri;
  String _method = 'GET';
  String? _parseError;
  String? _requestError;
  UrlRequestResult? _result;
  UrlRequestService? _request;
  bool _showBody = false;
  bool _showResponseHeaders = false;

  bool get _canSend =>
      _uri != null &&
      ['http', 'https'].contains(_uri!.scheme) &&
      _uri!.host.isNotEmpty;

  @override
  void dispose() {
    _request?.close();
    for (final controller in [
      _input,
      _queryJson,
      _headers,
      _body,
      _response,
      _responseHeaders,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _parse() {
    Uri? uri;
    String? error;
    String query = '';
    if (_input.text.trim().isNotEmpty) {
      try {
        uri = Uri.parse(_input.text.trim());
        final parameters = uri.queryParametersAll.map(
          (key, values) => MapEntry<String, Object>(
            key,
            values.length == 1 ? values.first : values,
          ),
        );
        query = const JsonEncoder.withIndent('  ').convert(parameters);
      } on FormatException {
        error = 'Enter a valid URL.';
      }
    }
    setState(() {
      _uri = uri;
      _parseError = error;
      _queryJson.text = query;
    });
  }

  void _setSample() {
    _input.text = 'https://example.com/login?user=some-guy&page=news';
    _parse();
  }

  void _cancel() {
    _request?.close();
    setState(() {
      _request = null;
      _requestError = 'Request cancelled.';
    });
  }

  Future<void> _send() async {
    if (!_canSend || _request != null) return;
    final headers = <String, String>{};
    for (final line in const LineSplitter().convert(_headers.text)) {
      if (line.trim().isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon <= 0 ||
          !RegExp(
            r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$",
          ).hasMatch(line.substring(0, colon).trim())) {
        setState(() => _requestError = 'Use one header per line: Name: value');
        return;
      }
      headers[line.substring(0, colon).trim()] = line
          .substring(colon + 1)
          .trim();
    }
    final request = UrlRequestService();
    setState(() {
      _request = request;
      _requestError = null;
      _result = null;
      _response.clear();
      _responseHeaders.clear();
    });
    try {
      final result = await request.send(
        uri: _uri!,
        method: _method,
        headers: headers,
        body: ['GET', 'HEAD'].contains(_method) ? '' : _body.text,
      );
      if (!mounted || _request != request) return;
      setState(() {
        _result = result;
        _response.text = result.body;
        _responseHeaders.text = result.headers;
      });
    } catch (error) {
      if (!mounted || _request != request) return;
      setState(
        () => _requestError = error is TimeoutException
            ? 'Request timed out after 30 seconds. You can send it again.'
            : error is FormatException
            ? error.message
            : 'Could not complete the request. Check the URL and connection.',
      );
    } finally {
      request.close();
      if (mounted && _request == request) setState(() => _request = null);
    }
  }

  Widget _details() {
    final uri = _uri;
    final fields = <String, String>{
      'Scheme': uri?.scheme ?? '',
      'Host': uri?.host ?? '',
      'Port': uri != null && uri.hasPort ? '${uri.port}' : '',
      'Path': uri?.path ?? '',
      'Fragment': uri?.fragment ?? '',
    };
    return ToolPanel(
      title: 'URL details',
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        children: fields.entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        entry.key,
                        style: mutedToolTextStyle(context),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        entry.value.isEmpty ? '—' : entry.value,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _request != null;
    return ToolSampleAction(
      onPressed: busy ? null : _setSample,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          final content = Column(
            children: [
              SizedBox(
                height: 110,
                child: EditorPane(
                  label: 'URL',
                  controller: _input,
                  placeholder: 'https://example.com/path?key=value',
                  onChanged: (_) => _parse(),
                  actions: [
                    SmallDropdown(
                      items: const [
                        'GET',
                        'POST',
                        'PUT',
                        'PATCH',
                        'DELETE',
                        'HEAD',
                        'OPTIONS',
                      ],
                      initialValue: _method,
                      width: 105,
                      onChanged: (value) => setState(() => _method = value),
                    ),
                    ToolButton(
                      label: busy ? 'Cancel' : 'Send',
                      icon: busy ? Icons.close : Icons.send_outlined,
                      onPressed: busy
                          ? _cancel
                          : _canSend
                          ? _send
                          : null,
                    ),
                  ],
                ),
              ),
              if (_parseError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_parseError!, style: errorToolTextStyle(context)),
                ),
              const SizedBox(height: 14),
              SizedBox(
                height: wide ? 200 : 340,
                child: buildAdaptiveSplit(
                  initialRatio: 0.36,
                  first: _details(),
                  second: EditorPane(
                    label: 'Parameters',
                    actions: const [],
                    controller: _queryJson,
                    readOnly: true,
                    placeholder: 'Query parameters will appear here',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: buildAdaptiveSplit(
                  initialRatio: 0.36,
                  first: EditorPane(
                    key: ValueKey(_showBody),
                    label: 'Request',
                    controller: _showBody ? _body : _headers,
                    placeholder: _showBody
                        ? 'Request body…'
                        : 'Content-Type: application/json',
                    actions: [
                      SegmentedToggle(
                        options: const ['Headers', 'Body'],
                        initialIndex: _showBody ? 1 : 0,
                        onChanged: (index) =>
                            setState(() => _showBody = index == 1),
                      ),
                    ],
                  ),
                  second: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: EditorPane(
                          key: ValueKey(_showResponseHeaders),
                          label: 'Response',
                          readOnly: true,
                          controller: _showResponseHeaders
                              ? _responseHeaders
                              : _response,
                          placeholder: busy
                              ? 'Waiting for response…'
                              : _result != null
                              ? 'No response body.'
                              : 'Press Send to make a request',
                          actions: [
                            if (busy)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            if (_result != null)
                              Text(
                                '${_result!.status} · ${_result!.elapsed.inMilliseconds} ms · ${_result!.bytes} B',
                                style: mutedToolTextStyle(context),
                              ),
                            SegmentedToggle(
                              options: const ['Body', 'Headers'],
                              initialIndex: _showResponseHeaders ? 1 : 0,
                              onChanged: (index) => setState(
                                () => _showResponseHeaders = index == 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_requestError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: SelectableText(
                            _requestError!,
                            style: errorToolTextStyle(context),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
          if (constraints.maxHeight < (wide ? 620 : 920)) {
            return SingleChildScrollView(
              child: SizedBox(height: wide ? 620 : 920, child: content),
            );
          }
          return content;
        },
      ),
    );
  }
}

Widget buildUrlParser() => const _UrlParserView();
