/// Firewall fingerprint tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/firewall_fingerprint_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _FirewallFingerprintView extends StatefulWidget {
  const _FirewallFingerprintView();

  @override
  State<_FirewallFingerprintView> createState() =>
      _FirewallFingerprintViewState();
}

class _FirewallFingerprintViewState extends State<_FirewallFingerprintView> {
  final TextEditingController _target = TextEditingController();
  final TextEditingController _timeout = TextEditingController(text: '7');
  final TextEditingController _report = TextEditingController();
  late final FirewallFingerprintService _service = FirewallFingerprintService();

  var _findAll = true;
  var _followRedirects = true;
  var _loading = false;
  var _detailsIndex = 0;
  var _reportMode = 'JSON';
  var _status = 'Ready.';
  String? _error;
  FirewallFingerprintResult? _result;
  int _requestId = 0;

  @override
  void dispose() {
    _requestId++;
    _service.close();
    _target.dispose();
    _timeout.dispose();
    _report.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_loading) return;
    final requestId = ++_requestId;
    late final Duration timeout;
    try {
      FirewallFingerprintService.normalizeUrl(_target.text);
      final seconds = int.tryParse(_timeout.text.trim());
      if (seconds == null || seconds < 1 || seconds > 30) {
        throw const FormatException(
          'Timeout must be between 1 and 30 seconds.',
        );
      }
      timeout = Duration(seconds: seconds);
    } catch (e) {
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = 'Fingerprinting target...';
      _result = null;
      _report.clear();
    });

    try {
      final result = await _service.scan(
        target: _target.text,
        findAll: _findAll,
        followRedirects: _followRedirects,
        timeout: timeout,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _result = result;
        _status = result.detected
            ? '${result.detections.length} signature match${result.detections.length == 1 ? '' : 'es'} found.'
            : 'No firewall signature detected.';
        _loading = false;
      });
      _refreshFirewallReport();
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _status = 'Fingerprint failed.';
        _loading = false;
      });
    }
  }

  void _setSample() {
    _target.text = 'https://www.cloudflare.com/';
  }

  void _refreshFirewallReport() {
    final result = _result;
    if (result == null) {
      _report.clear();
      return;
    }
    _report.text = _reportMode == 'JSON'
        ? result.toJsonReport()
        : result.toTextReport();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFirewallControls(context),
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
            child: buildAdaptiveSplit(
              initialRatio: 0.52,
              minFirstExtent: 340,
              minSecondExtent: 320,
              first: _buildFirewallResults(context),
              second: _buildFirewallDetails(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirewallControls(BuildContext context) {
    final appColors = context.appColors;
    return ToolSampleAction(
      onPressed: _loading ? null : _setSample,
      child: ToolPanel(
        title: 'Probe options',
        expand: false,
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Target',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(
                width: 330,
                child: _firewallTextField(
                  key: const ValueKey('firewall-fingerprint-target'),
                  controller: _target,
                  hint: 'https://example.com/',
                  onSubmitted: (_) => _scan(),
                ),
              ),
              _firewallMiniField(
                context,
                'Timeout',
                _timeout,
                width: 64,
                suffix: 's',
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _findAll,
                    onChanged: _loading
                        ? null
                        : (value) => setState(() => _findAll = value ?? true),
                  ),
                  Text(
                    'Find all',
                    style: TextStyle(color: appColors.editorText),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _followRedirects,
                    onChanged: _loading
                        ? null
                        : (value) {
                            setState(() => _followRedirects = value ?? true);
                          },
                  ),
                  Text(
                    'Redirects',
                    style: TextStyle(color: appColors.editorText),
                  ),
                ],
              ),

              ToolButton(
                label: 'Fingerprint',
                onPressed: _loading ? null : _scan,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFirewallResults(BuildContext context) {
    final result = _result;
    final detections = result?.detections ?? const <FirewallDetection>[];
    return ToolPanel(
      title: 'Results',
      expand: true,
      child: Container(
        child: result == null
            ? Center(
                child: Text(
                  _loading
                      ? 'Running probes...'
                      : 'Firewall matches will appear here',
                  style: mutedToolTextStyle(context),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  _firewallSummary(context, result),
                  const SizedBox(height: 10),
                  if (detections.isEmpty && result.genericDetected)
                    _genericFirewallTile(context, result.genericReason)
                  else if (detections.isEmpty)
                    Text(
                      'No WAF detected by signature or generic probes.',
                      style: mutedToolTextStyle(context),
                    )
                  else
                    for (final detection in detections)
                      _firewallDetectionTile(context, detection),
                ],
              ),
      ),
    );
  }

  Widget _firewallSummary(
    BuildContext context,
    FirewallFingerprintResult result,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _firewallPill(context, 'Detected', result.detected ? 'Yes' : 'No'),
        _firewallPill(context, 'Matches', '${result.detections.length}'),
        _firewallPill(context, 'Requests', '${result.requestCount}'),
        _firewallPill(
          context,
          'Generic',
          result.genericDetected ? 'Yes' : 'No',
        ),
      ],
    );
  }

  Widget _firewallDetectionTile(
    BuildContext context,
    FirewallDetection detection,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detection.firewall,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appColors.editorText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _firewallConfidence(context, detection.confidence),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detection.manufacturer,
            style: mutedToolTextStyle(context, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final evidence in detection.evidence.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                evidence,
                style: TextStyle(
                  color: context.appColors.mutedText,
                  fontFamily: 'Menlo',
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _genericFirewallTile(BuildContext context, String reason) {
    return Container(
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Generic firewall behavior',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(reason, style: mutedToolTextStyle(context)),
        ],
      ),
    );
  }

  Widget _buildFirewallDetails(BuildContext context) {
    return ToolPanel(
      title: 'Details',
      expand: true,
      child: Container(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SegmentedToggle(
                    options: const ['Probes', 'Report'],
                    initialIndex: _detailsIndex,
                    onChanged: (index) => setState(() => _detailsIndex = index),
                  ),
                  if (_detailsIndex == 1) ...[
                    const SizedBox(width: 10),
                    SmallDropdown(
                      key: ValueKey('firewall-report-$_reportMode'),
                      items: const ['JSON', 'Text'],
                      initialValue: _reportMode,
                      width: 90,
                      onChanged: (value) {
                        setState(() => _reportMode = value);
                        _refreshFirewallReport();
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _detailsIndex == 0
                  ? _buildProbeList(context)
                  : EditorPane(
                      label: 'Report',
                      actions: const [],
                      controller: _report,
                      readOnly: true,
                      placeholder:
                          'Run a fingerprint scan to generate a report...',
                      showHeader: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProbeList(BuildContext context) {
    final probes = _result?.probes ?? const <FirewallProbeResponse>[];
    if (probes.isEmpty) {
      return Center(
        child: Text(
          'Probe results will appear here',
          style: mutedToolTextStyle(context),
        ),
      );
    }
    return ListView.separated(
      itemCount: probes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final probe = probes[index];
        return Container(
          decoration: toolSurfaceDecoration(context, radius: 6),
          child: ExpansionTile(
            key: PageStorageKey('firewall-$_requestId-$index-${probe.url}'),
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            title: Text(
              probe.name,
              style: TextStyle(
                color: context.appColors.editorText,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'HTTP ${probe.statusCode} ${probe.reasonPhrase}',
              style: mutedToolTextStyle(context, fontSize: 11),
            ),
            children: [
              _probeDetail(context, 'Request URL', probe.url.toString()),
              const SizedBox(height: 10),
              _probeDetail(
                context,
                'Response headers',
                probe.headers.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join('\n'),
                maxHeight: 180,
              ),
              const SizedBox(height: 10),
              _probeDetail(
                context,
                'Response body snippet',
                probe.bodySnippet,
                maxHeight: 220,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _probeDetail(
    BuildContext context,
    String label,
    String value, {
    double maxHeight = 110,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.appColors.editorText,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: SelectableText(
              value.isEmpty ? 'None returned.' : value,
              style: TextStyle(
                color: context.appColors.mutedText,
                fontFamily: 'Menlo',
                fontSize: 11,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _firewallPill(BuildContext context, String label, String value) {
    return Container(
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: mutedToolTextStyle(context, fontSize: 12)),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _firewallConfidence(BuildContext context, int confidence) {
    final appColors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: appColors.accent.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appColors.accent.withAlpha(150)),
      ),
      child: Text(
        '$confidence%',
        style: TextStyle(
          color: appColors.accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _firewallMiniField(
    BuildContext context,
    String label,
    TextEditingController controller, {
    required double width,
    String? suffix,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: mutedToolTextStyle(context)),
        const SizedBox(width: 6),
        SizedBox(
          width: width,
          child: _firewallTextField(controller: controller, hint: ''),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text(suffix, style: mutedToolTextStyle(context)),
        ],
      ],
    );
  }

  Widget _firewallTextField({
    Key? key,
    required TextEditingController controller,
    required String hint,
    ValueChanged<String>? onSubmitted,
  }) {
    final appColors = context.appColors;
    return Container(
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: TextField(
        key: key,
        controller: controller,
        enabled: !_loading,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: appColors.mutedText),
        ),
        style: TextStyle(
          color: appColors.editorText,
          fontFamily: 'Menlo',
          fontSize: 13,
        ),
      ),
    );
  }
}

Widget buildFirewallFingerprint() {
  return const _FirewallFingerprintView();
}
