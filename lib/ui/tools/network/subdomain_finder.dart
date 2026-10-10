/// Subdomain finder tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/subdomain_lookup_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../../tool_sample_action.dart';

class _SubdomainFinderView extends StatefulWidget {
  const _SubdomainFinderView();

  @override
  State<_SubdomainFinderView> createState() => _SubdomainFinderViewState();
}

class _SubdomainFinderViewState extends State<_SubdomainFinderView> {
  final TextEditingController _domain = TextEditingController();
  final TextEditingController _results = TextEditingController();
  late final SubdomainLookupService _service = SubdomainLookupService();
  var _mode = SubdomainLookupMode.domain;
  var _loading = false;
  var _status = 'Enter a root domain to find public subdomains.';
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _requestId++;
    _service.close();
    _domain.dispose();
    _results.dispose();
    super.dispose();
  }

  bool get _isDomainMode => _mode == SubdomainLookupMode.domain;

  String get _inputHint => _isDomainMode ? 'example.com' : 'Example Inc';

  String get _emptyStatus => _isDomainMode
      ? 'Enter a root domain to find public subdomains.'
      : 'Enter an organization name to find public certificate names.';

  String get _loadingStatus => _isDomainMode
      ? 'Searching certificate transparency and DNS records...'
      : 'Searching organization certificates...';

  String get _outputPlaceholder => _isDomainMode
      ? 'Public subdomains will appear here...'
      : 'Public certificate names will appear here...';

  Future<void> _findSubdomains() async {
    final requestId = ++_requestId;
    final mode = _mode;
    setState(() {
      _loading = true;
      _error = null;
      _status = _loadingStatus;
      _results.clear();
    });

    try {
      final result = switch (mode) {
        SubdomainLookupMode.domain => await _service.lookup(_domain.text),
        SubdomainLookupMode.organization => await _service.lookupOrganization(
          _domain.text,
        ),
      };
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results.text = result.subdomains.join('\n');
        final noun = result.mode == SubdomainLookupMode.domain
            ? 'public subdomains'
            : 'public certificate names';
        final target = result.mode == SubdomainLookupMode.domain
            ? result.domain
            : '"${result.domain}"';
        if (result.subdomains.isEmpty) {
          final fallbackHint =
              result.mode == SubdomainLookupMode.domain && !result.usedSubfinder
              ? ' Install subfinder for deeper local discovery.'
              : '';
          final warningText = result.usedSubfinder && result.hasWarnings
              ? ' ${result.warnings.join(' ')}'
              : '';
          _status = 'No $noun found for $target.$fallbackHint$warningText';
        } else {
          _status = '${result.subdomains.length} $noun found for $target.';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
        _status = 'Lookup failed.';
        _loading = false;
      });
    }
  }

  void _setSample() {
    _domain.text = _isDomainMode ? 'github.com' : 'GitHub';
  }

  void _changeMode(int index) {
    final mode = index == 0
        ? SubdomainLookupMode.domain
        : SubdomainLookupMode.organization;
    setState(() {
      _requestId++;
      _mode = mode;
      _domain.clear();
      _results.clear();
      _error = null;
      _loading = false;
      _status = _emptyStatus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return ToolSampleAction(
      onPressed: _setSample,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ToolPanel(
              title: 'Search options',
              expand: false,
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SegmentedToggle(
                          options: const ['Domain', 'Organization'],
                          initialIndex: _isDomainMode ? 0 : 1,
                          onChanged: _changeMode,
                        ),
                        Text(
                          'Target',
                          style: TextStyle(
                            color: appColors.editorText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        ToolButton(
                          label: 'Find known',
                          onPressed: _loading ? null : _findSubdomains,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: toolSurfaceDecoration(context, radius: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: TextField(
                        controller: _domain,
                        enabled: !_loading,
                        onSubmitted: (_) => _findSubdomains(),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          hintText: _inputHint,
                          hintStyle: TextStyle(color: appColors.mutedText),
                        ),
                        style: TextStyle(
                          color: appColors.editorText,
                          fontFamily: 'Menlo',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_loading) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _error ?? _status,
                    style: _error == null
                        ? mutedToolTextStyle(context)
                        : errorToolTextStyle(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: EditorPane(
                label: 'Public subdomains',
                actions: [],
                controller: _results,
                readOnly: true,
                placeholder: _outputPlaceholder,
                showHeader: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget buildSubdomainFinder() {
  return const _SubdomainFinderView();
}
