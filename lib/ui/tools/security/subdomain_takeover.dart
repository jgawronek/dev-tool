/// Subdomain takeover check tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/subdomain_takeover_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _SubdomainTakeoverView extends StatefulWidget {
  const _SubdomainTakeoverView();

  @override
  State<_SubdomainTakeoverView> createState() => _SubdomainTakeoverViewState();
}

class _SubdomainTakeoverViewState extends State<_SubdomainTakeoverView> {
  final TextEditingController _targets = TextEditingController();
  final TextEditingController _timeout = TextEditingController(text: '8');
  final TextEditingController _concurrency = TextEditingController(text: '8');
  final TextEditingController _details = TextEditingController();
  late final SubdomainTakeoverService _service = SubdomainTakeoverService();

  var _scanning = false;
  var _status = 'Enter subdomains to check for dangling provider mappings.';
  var _reportMode = 'Details';
  String? _error;
  TakeoverScanProgress? _progress;
  TakeoverScanSummary? _summary;
  TakeoverScanResult? _selected;
  int _requestId = 0;

  @override
  void dispose() {
    _requestId++;
    _service.close();
    _targets.dispose();
    _timeout.dispose();
    _concurrency.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;

    final requestId = ++_requestId;
    setState(() {
      _scanning = true;
      _error = null;
      _summary = null;
      _selected = null;
      _progress = null;
      _details.clear();
      _status = 'Checking DNS and provider fingerprints...';
    });

    try {
      final timeoutSeconds = double.tryParse(_timeout.text.trim()) ?? 8;
      final concurrency = int.tryParse(_concurrency.text.trim()) ?? 8;
      final summary = await _service.scanText(
        _targets.text,
        timeout: Duration(milliseconds: (timeoutSeconds * 1000).round()),
        concurrency: concurrency,
        onProgress: (progress) {
          if (!mounted || requestId != _requestId) return;
          setState(() {
            _progress = progress;
            _status =
                'Checked ${progress.scanned}/${progress.total}, ${progress.potentialCount} potential.';
          });
        },
      );

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _summary = summary;
        _selected = summary.results.isEmpty ? null : summary.results.first;
        _scanning = false;
        _progress = TakeoverScanProgress(
          scanned: summary.results.length,
          total: summary.results.length,
          potentialCount: summary.potentialCount,
        );
        _status = summary.potentialCount == 0
            ? 'No takeover fingerprints matched across ${summary.results.length} hosts.'
            : '${summary.potentialCount} potential takeover match(es) across ${summary.results.length} hosts.';
        _refreshDetails();
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error is FormatException ? error.message : error.toString();
        _status = 'Scan failed.';
        _scanning = false;
      });
    }
  }

  void _refreshDetails() {
    final summary = _summary;
    if (_reportMode == 'JSON') {
      _details.text = summary?.toJsonReport() ?? '';
      return;
    }
    if (_reportMode == 'CSV') {
      _details.text = summary?.toCsvReport() ?? '';
      return;
    }
    final selected = _selected;
    _details.text = selected == null ? '' : _formatTakeoverDetails(selected);
  }

  void _selectResult(TakeoverScanResult result) {
    setState(() {
      _selected = result;
      _reportMode = 'Details';
      _refreshDetails();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTakeoverControls(context),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_scanning) ...[
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
              if (progress != null && progress.total > 0) ...[
                SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(value: progress.ratio),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(progress.ratio * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: appColors.mutedText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ResizableSplit(
              horizontal: true,
              initialRatio: 0.5,
              minFirstExtent: 360,
              minSecondExtent: 360,
              first: _buildTakeoverResults(context),
              second: _buildTakeoverDetails(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTakeoverControls(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Targets',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              _takeoverOptionField(
                context,
                'Timeout',
                controller: _timeout,
                width: 72,
                suffix: 's',
              ),
              const SizedBox(width: 10),
              _takeoverOptionField(
                context,
                'Concurrency',
                controller: _concurrency,
                width: 72,
              ),
              const Spacer(),
              ToolButton(label: 'Scan', onPressed: _scanning ? null : _scan),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: TextField(
              key: const ValueKey('subdomain-takeover-targets'),
              controller: _targets,
              enabled: !_scanning,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'docs.example.com\nhelp.example.com',
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
    );
  }

  Widget _buildTakeoverResults(BuildContext context) {
    final results = _summary?.results ?? const <TakeoverScanResult>[];
    return Container(
      decoration: toolSurfaceDecoration(context),
      child: results.isEmpty
          ? Center(
              child: Text(
                _scanning
                    ? 'Scanning targets...'
                    : 'Potential takeover matches will appear here',
                style: mutedToolTextStyle(context),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final result = results[index];
                return _takeoverResultTile(context, result);
              },
            ),
    );
  }

  Widget _takeoverResultTile(BuildContext context, TakeoverScanResult result) {
    final appColors = context.appColors;
    final selected = identical(_selected, result);
    return InkWell(
      onTap: () => _selectResult(result),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? appColors.accent.withAlpha(24) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? appColors.accent : appColors.border,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.host,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: appColors.editorText,
                      fontFamily: 'Menlo',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _takeoverConfidenceChip(context, result.confidence),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              result.service,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appColors.editorText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.evidence,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: mutedToolTextStyle(context, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTakeoverDetails(BuildContext context) {
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SegmentedToggle(
                key: ValueKey('takeover-report-$_reportMode'),
                options: const ['Details', 'JSON', 'CSV'],
                initialIndex: switch (_reportMode) {
                  'JSON' => 1,
                  'CSV' => 2,
                  _ => 0,
                },
                onChanged: (index) {
                  setState(() {
                    _reportMode = switch (index) {
                      1 => 'JSON',
                      2 => 'CSV',
                      _ => 'Details',
                    };
                    _refreshDetails();
                  });
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selected?.host ?? 'Result details',
                  overflow: TextOverflow.ellipsis,
                  style: mutedToolTextStyle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: EditorPane(
              label: 'Takeover details',
              actions: const [],
              controller: _details,
              readOnly: true,
              placeholder: 'Select a scan result to inspect evidence...',
              showHeader: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _takeoverOptionField(
    BuildContext context,
    String label, {
    required TextEditingController controller,
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
          child: Container(
            decoration: toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              controller: controller,
              enabled: !_scanning,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
              style: TextStyle(
                color: context.appColors.editorText,
                fontFamily: 'Menlo',
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text(suffix, style: mutedToolTextStyle(context)),
        ],
      ],
    );
  }

  Widget _takeoverConfidenceChip(
    BuildContext context,
    TakeoverConfidence confidence,
  ) {
    final appColors = context.appColors;
    final color = switch (confidence) {
      TakeoverConfidence.high => appColors.error,
      TakeoverConfidence.medium => appColors.warning,
      TakeoverConfidence.low => appColors.accent,
      TakeoverConfidence.safe => appColors.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(160)),
      ),
      child: Text(
        confidence.label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _formatTakeoverDetails(TakeoverScanResult result) {
  final buffer = StringBuffer()
    ..writeln('Host: ${result.host}')
    ..writeln('Service: ${result.service}')
    ..writeln('Confidence: ${result.confidence.label}')
    ..writeln('Evidence: ${result.evidence}');

  if (result.matchedCnameIndicator != null) {
    buffer.writeln('Matched CNAME indicator: ${result.matchedCnameIndicator}');
  }
  if (result.matchedBodyIndicator != null) {
    buffer.writeln('Matched page indicator: ${result.matchedBodyIndicator}');
  }
  if (result.cnameChain.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('CNAME chain:')
      ..writeln(result.cnameChain.map((cname) => '  $cname').join('\n'));
  }
  if (result.probes.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('HTTP probes:');
    for (final probe in result.probes) {
      final status = probe.statusCode?.toString() ?? 'no response';
      final error = probe.error == null ? '' : ' (${probe.error})';
      buffer.writeln('  ${probe.url} - $status$error');
    }
  }

  buffer
    ..writeln()
    ..writeln(
      'Note: Treat this as a triage signal. Verify provider ownership before taking action.',
    );
  return buffer.toString();
}

Widget buildSubdomainTakeover() {
  return const _SubdomainTakeoverView();
}
