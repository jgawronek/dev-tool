/// Port scanner tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../services/port_scanner_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _PortScannerView extends StatefulWidget {
  const _PortScannerView();

  @override
  State<_PortScannerView> createState() => _PortScannerViewState();
}

class _PortScannerViewState extends State<_PortScannerView> {
  final TextEditingController _target = TextEditingController(
    text: '127.0.0.1',
  );
  final TextEditingController _ports = TextEditingController();
  final TextEditingController _timeout = TextEditingController();
  final TextEditingController _concurrency = TextEditingController();
  final TextEditingController _report = TextEditingController();
  late final PortScannerService _service = PortScannerService();
  late final StreamSubscription<ScanProgress> _progressSubscription;

  var _profileName = 'Quick Scan';
  var _reportMode = 'JSON';
  var _detailsIndex = 0;
  var _grabBanners = true;
  var _tlsDetails = true;
  var _httpProbe = true;
  var _scanning = false;
  var _reconLoading = false;
  var _status = 'Ready.';
  String? _error;
  ScanProgress? _progress;
  PortScanSummary? _summary;
  HostReconResult? _recon;
  final List<PortScanSummary> _history = [];
  int _requestId = 0;

  static const _customProfileName = 'Custom Ports';

  bool get _isCustomProfile => _profileName == _customProfileName;

  List<String> get _profileNames => [
    ...PortScannerService.profiles.map((profile) => profile.name),
    _customProfileName,
  ];

  @override
  void initState() {
    super.initState();
    _syncProfileFields();
    _progressSubscription = _service.progress.listen((progress) {
      if (!mounted) return;
      setState(() {
        _progress = progress;
        if (progress.active) {
          _status =
              'Scanning ${progress.scanned}/${progress.total} ports, ${progress.openCount} open.';
        }
      });
    });
  }

  @override
  void dispose() {
    _requestId++;
    _progressSubscription.cancel();
    _service.close();
    _target.dispose();
    _ports.dispose();
    _timeout.dispose();
    _concurrency.dispose();
    _report.dispose();
    super.dispose();
  }

  void _syncProfileFields() {
    if (_isCustomProfile) {
      if (_ports.text.trim().isEmpty) {
        _ports.text = '22,80,443,8080,8443';
      }
      _timeout.text = '1.0';
      _concurrency.text = '50';
      return;
    }

    final profile = PortScannerService.profileByName(_profileName);
    _ports.text = _describePorts(profile);
    _timeout.text = _secondsLabel(profile.timeout);
    _concurrency.text = profile.concurrency.toString();
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    final requestId = ++_requestId;
    late final PortScanProfile profile;
    late final List<int>? customPorts;
    late final Duration timeout;
    late final int concurrency;

    try {
      timeout = _parseTimeout();
      concurrency = _parseConcurrency();
      if (_isCustomProfile) {
        customPorts = PortScannerService.parsePorts(_ports.text);
        profile = PortScanProfile(
          name: _customProfileName,
          description: 'Custom port list',
          timeout: timeout,
          concurrency: concurrency,
          ports: customPorts,
        );
      } else {
        customPorts = null;
        profile = PortScannerService.profileByName(_profileName);
      }
      PortScannerService.normalizeTarget(_target.text);
    } catch (e) {
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
      });
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
      _progress = const ScanProgress(
        scanned: 0,
        total: 0,
        active: true,
        openCount: 0,
      );
      _status = 'Resolving target...';
      _summary = null;
      _report.clear();
    });

    try {
      final summary = await _service.scan(
        target: _target.text,
        profile: profile,
        ports: customPorts,
        timeout: timeout,
        concurrency: concurrency,
        grabBanners: _grabBanners,
        tlsDetails: _tlsDetails,
        httpProbe: _httpProbe,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _summary = summary;
        _history.insert(0, summary);
        if (_history.length > 20) _history.removeLast();
        _status =
            '${summary.results.length} open of ${summary.totalPorts} ports. Grade ${summary.securityScore.grade}.';
        _scanning = false;
      });
      _refreshReport();
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
        _status = 'Scan failed.';
        _scanning = false;
      });
    }
  }

  Future<void> _runRecon() async {
    if (_reconLoading) return;
    final requestId = ++_requestId;
    try {
      PortScannerService.normalizeTarget(_target.text);
    } catch (e) {
      setState(() {
        _error = e is FormatException ? e.message : e.toString();
      });
      return;
    }

    setState(() {
      _reconLoading = true;
      _error = null;
      _status = 'Collecting host details...';
      _detailsIndex = 1;
    });

    try {
      final recon = await _service.reconnaissance(_target.text);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _recon = recon;
        _status = 'Recon complete for ${recon.target}.';
        _reconLoading = false;
      });
      _refreshReport();
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _status = 'Recon failed.';
        _reconLoading = false;
      });
    }
  }

  void _stopScan() {
    _service.cancel();
    setState(() {
      _requestId++;
      _scanning = false;
      _status = 'Stopping scan...';
    });
  }

  void _setSample() {
    setState(() {
      _target.text = 'scanme.nmap.org';
      _profileName = 'Web Ports';
      _syncProfileFields();
    });
  }

  Duration _parseTimeout() {
    final seconds = double.tryParse(_timeout.text.trim());
    if (seconds == null || seconds <= 0 || seconds > 30) {
      throw const FormatException(
        'Timeout must be between 0.1 and 30 seconds.',
      );
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  int _parseConcurrency() {
    final value = int.tryParse(_concurrency.text.trim());
    if (value == null || value < 1 || value > 100) {
      throw const FormatException('Concurrency must be between 1 and 100.');
    }
    return value;
  }

  void _refreshReport() {
    final summary = _summary;
    final recon = _recon;
    if (_reportMode == 'CSV') {
      _report.text = summary?.toCsvReport() ?? '';
      return;
    }
    final payload = <String, Object?>{
      if (summary != null) 'scan': summary.toJson(),
      if (recon != null) 'recon': recon.toJson(),
    };
    _report.text = payload.isEmpty
        ? ''
        : const JsonEncoder.withIndent('  ').convert(payload);
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
          _buildControls(context),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_scanning || _reconLoading) ...[
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
                  width: 180,
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
              initialRatio: 0.56,
              minFirstExtent: 360,
              minSecondExtent: 320,
              first: _buildPortsPanel(context),
              second: _buildDetailsPanel(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
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
                width: 280,
                child: _compactTextField(
                  key: const ValueKey('port-scanner-target'),
                  controller: _target,
                  hint: 'example.com or 192.0.2.10',
                  enabled: !_scanning,
                  onSubmitted: (_) => _startScan(),
                ),
              ),
              SmallDropdown(
                key: ValueKey('port-profile-$_profileName'),
                items: _profileNames,
                initialValue: _profileName,
                width: 180,
                onChanged: (value) {
                  setState(() {
                    _profileName = value;
                    _syncProfileFields();
                  });
                },
              ),
              SizedBox(
                width: 250,
                child: _compactTextField(
                  controller: _ports,
                  hint: '22,80,443 or 8000-8010',
                  enabled: _isCustomProfile && !_scanning,
                ),
              ),
              ToolButton(
                label: 'Sample',
                onPressed: _scanning ? null : _setSample,
              ),
              ToolButton(
                label: 'Scan',
                onPressed: _scanning ? null : _startScan,
              ),
              ToolButton(
                label: 'Recon',
                onPressed: _reconLoading ? null : _runRecon,
              ),
              ToolButton(
                label: 'Stop',
                onPressed: _scanning ? _stopScan : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _miniLabeledField(
                context,
                'Timeout',
                width: 84,
                controller: _timeout,
                suffix: 's',
                enabled: !_scanning,
              ),
              _miniLabeledField(
                context,
                'Concurrency',
                width: 76,
                controller: _concurrency,
                enabled: !_scanning,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _grabBanners,
                    onChanged: _scanning
                        ? null
                        : (value) {
                            setState(() => _grabBanners = value ?? true);
                          },
                  ),
                  Text(
                    'Banners',
                    style: TextStyle(color: appColors.editorText),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _tlsDetails,
                    onChanged: _scanning
                        ? null
                        : (value) {
                            setState(() => _tlsDetails = value ?? true);
                          },
                  ),
                  Text(
                    'TLS details',
                    style: TextStyle(color: appColors.editorText),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _httpProbe,
                    onChanged: _scanning
                        ? null
                        : (value) {
                            setState(() => _httpProbe = value ?? true);
                          },
                  ),
                  Text(
                    'HTTP HEAD',
                    style: TextStyle(color: appColors.editorText),
                  ),
                ],
              ),
              Text(
                _isCustomProfile
                    ? 'Custom list'
                    : PortScannerService.profileByName(
                        _profileName,
                      ).description,
                style: mutedToolTextStyle(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortsPanel(BuildContext context) {
    final summary = _summary;
    final results = summary?.results ?? const <PortScanResult>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final showStats = constraints.maxHeight >= 120;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showStats) ...[
              _buildScanStats(context, summary),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: Container(
                decoration: toolSurfaceDecoration(context),
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          _scanning
                              ? 'Scanning...'
                              : 'Open ports will appear here',
                          style: mutedToolTextStyle(context),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _portResultRow(context, results[index]);
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScanStats(BuildContext context, PortScanSummary? summary) {
    final open = summary?.results.length ?? 0;
    final total = summary?.totalPorts ?? _progress?.total ?? 0;
    final highRisk = summary?.highRiskPorts ?? 0;
    final score = summary?.securityScore.score ?? 100;
    final grade = summary?.securityScore.grade ?? 'A';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _statPill(context, 'Open', '$open'),
        _statPill(context, 'Scanned', '$total'),
        _statPill(context, 'High risk', '$highRisk'),
        _statPill(context, 'Score', '$score / $grade'),
      ],
    );
  }

  Widget _statPill(BuildContext context, String label, String value) {
    final appColors = context.appColors;
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
              color: appColors.editorText,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _portResultRow(BuildContext context, PortScanResult result) {
    final appColors = context.appColors;
    return Container(
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  result.port.toString(),
                  style: TextStyle(
                    color: appColors.editorText,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '${result.service} · ${result.protocol} · ${result.confidence}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: appColors.editorText),
                ),
              ),
              _riskChip(context, result.riskLevel),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.riskReason,
            style: mutedToolTextStyle(context, fontSize: 12),
          ),
          if (result.httpStatus != null ||
              (result.tls?.connected ?? false)) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (result.httpStatus != null) result.httpStatus,
                if (result.tls?.connected ?? false)
                  'TLS ${result.tls?.daysUntilExpiry == null ? 'ok' : '${result.tls!.daysUntilExpiry}d left'}',
              ].join(' · '),
              style: TextStyle(
                color: appColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (result.banner.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              result.banner,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appColors.mutedText,
                fontFamily: 'Menlo',
                fontSize: 11,
              ),
            ),
          ],
          if (result.vulnerabilities.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${result.vulnerabilities.length} known CVE/reference checks',
              style: TextStyle(
                color: appColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _riskChip(BuildContext context, String riskLevel) {
    final appColors = context.appColors;
    final color = switch (riskLevel) {
      'CRITICAL' => appColors.error,
      'HIGH' => appColors.warning,
      'MEDIUM' => appColors.accent,
      _ => appColors.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(160)),
      ),
      child: Text(
        riskLevel,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildDetailsPanel(BuildContext context) {
    return Container(
      decoration: toolSurfaceDecoration(context),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SegmentedToggle(
                  options: const ['Details', 'Recon', 'Report', 'History'],
                  initialIndex: _detailsIndex,
                  onChanged: (index) => setState(() => _detailsIndex = index),
                ),
                if (_detailsIndex == 2) ...[
                  const SizedBox(width: 10),
                  SmallDropdown(
                    key: ValueKey('port-report-$_reportMode'),
                    items: const ['JSON', 'CSV'],
                    initialValue: _reportMode,
                    width: 90,
                    onChanged: (value) {
                      setState(() => _reportMode = value);
                      _refreshReport();
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: switch (_detailsIndex) {
              0 => _buildScoreDetails(context),
              1 => _buildReconDetails(context),
              2 => _buildReportPanel(context),
              _ => _buildHistoryPanel(context),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScoreDetails(BuildContext context) {
    final summary = _summary;
    if (summary == null) {
      return Center(
        child: Text(
          'Scan details will appear here',
          style: mutedToolTextStyle(context),
        ),
      );
    }
    final score = summary.securityScore;
    return ListView(
      children: [
        _detailRow(
          context,
          'Target',
          '${summary.target} (${summary.resolvedIp})',
        ),
        _detailRow(context, 'Profile', summary.profile),
        _detailRow(
          context,
          'Duration',
          '${summary.duration.inMilliseconds} ms',
        ),
        _detailRow(
          context,
          'Security grade',
          '${score.grade} (${score.score}/100)',
        ),
        const SizedBox(height: 10),
        Text(
          'Penalty breakdown',
          style: TextStyle(
            color: context.appColors.editorText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        for (final entry in score.breakdown.entries)
          _detailRow(
            context,
            _sentenceLabel(entry.key),
            entry.value.toString(),
          ),
        const SizedBox(height: 10),
        Text(
          'Recommendations',
          style: TextStyle(
            color: context.appColors.editorText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        if (score.recommendations.isEmpty)
          Text(
            'No high-priority recommendations.',
            style: mutedToolTextStyle(context),
          )
        else
          for (final recommendation in score.recommendations)
            _recommendationTile(context, recommendation),
        if (summary.results.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Service evidence',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final result in summary.results)
            _portEvidenceTile(context, result),
        ],
      ],
    );
  }

  Widget _portEvidenceTile(BuildContext context, PortScanResult result) {
    final appColors = context.appColors;
    final tls = result.tls;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${result.port} · ${result.service} · ${result.confidence}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: appColors.editorText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _riskChip(context, result.riskLevel),
            ],
          ),
          if (result.httpStatus != null)
            _detailRow(context, 'HTTP status', result.httpStatus!),
          if (tls != null) ...[
            _detailRow(context, 'TLS', tls.connected ? 'Connected' : 'Failed'),
            if (tls.protocol != null)
              _detailRow(context, 'Protocol', tls.protocol!),
            if (tls.subject != null)
              _detailRow(context, 'Subject', tls.subject!),
            if (tls.issuer != null) _detailRow(context, 'Issuer', tls.issuer!),
            if (tls.daysUntilExpiry != null)
              _detailRow(context, 'Days left', '${tls.daysUntilExpiry}'),
            if (tls.error != null) _detailRow(context, 'TLS error', tls.error!),
          ],
          if (result.banner.isNotEmpty)
            _detailRow(context, 'Banner', result.banner),
          for (final observation in result.observations)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '- $observation',
                style: mutedToolTextStyle(context, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReconDetails(BuildContext context) {
    final recon = _recon;
    if (_reconLoading) {
      return Center(
        child: Text('Collecting recon...', style: mutedToolTextStyle(context)),
      );
    }
    if (recon == null) {
      return Center(
        child: Text(
          'Run recon to collect host details',
          style: mutedToolTextStyle(context),
        ),
      );
    }

    return ListView(
      children: [
        _detailRow(context, 'Target', recon.target),
        if (recon.resolvedIp != null)
          _detailRow(context, 'Resolved IP', recon.resolvedIp!),
        if (recon.hostname != null)
          _detailRow(context, 'Hostname', recon.hostname!),
        _sectionBlock(context, 'Geolocation', recon.geolocation),
        _sectionBlock(context, 'Whois', recon.whois),
        _dnsBlock(context, recon.dnsRecords),
        _sectionBlock(context, 'SSL/TLS', recon.sslAnalysis),
        _sectionBlock(context, 'Security headers', recon.securityHeaders),
        _technologiesBlock(context, recon.technologies),
        _sectionBlock(context, 'Shodan', recon.shodan),
      ],
    );
  }

  Widget _buildReportPanel(BuildContext context) {
    return EditorPane(
      label: 'Report',
      actions: const [],
      controller: _report,
      readOnly: true,
      placeholder: 'Run a scan or recon to generate a report...',
      showHeader: false,
    );
  }

  Widget _buildHistoryPanel(BuildContext context) {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          'Recent scans will appear here',
          style: mutedToolTextStyle(context),
        ),
      );
    }
    return ListView.separated(
      itemCount: _history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _history[index];
        return Container(
          decoration: toolSurfaceDecoration(context, radius: 6),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.target,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appColors.editorText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${item.results.length}/${item.totalPorts} open',
                style: mutedToolTextStyle(context),
              ),
              const SizedBox(width: 10),
              _riskChip(
                context,
                item.securityScore.grade == 'F' ? 'HIGH' : 'LOW',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionBlock(
    BuildContext context,
    String title,
    Map<String, Object?> values,
  ) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in values.entries)
                  _detailRow(
                    context,
                    _sentenceLabel(entry.key),
                    '${entry.value}',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dnsBlock(BuildContext context, Map<String, List<String>> records) {
    if (records.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DNS records',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in records.entries)
                  _detailRow(context, entry.key, entry.value.join('\n')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _technologiesBlock(
    BuildContext context,
    List<Map<String, Object?>> technologies,
  ) {
    if (technologies.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Technologies',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: toolSurfaceDecoration(context, radius: 6),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tech in technologies)
                  _detailRow(
                    context,
                    '${tech['name'] ?? 'Technology'}',
                    [
                      if (tech['value'] != null) tech['value'],
                      if (tech['category'] != null) tech['category'],
                    ].join(' · '),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationTile(
    BuildContext context,
    SecurityRecommendation recommendation,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _riskChip(context, recommendation.priority),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  recommendation.title,
                  style: TextStyle(
                    color: context.appColors.editorText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            recommendation.description,
            style: mutedToolTextStyle(context, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: TextStyle(
                color: appColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: appColors.editorText,
                fontFamily: value.length > 24 ? 'Menlo' : null,
                fontSize: value.length > 24 ? 11.5 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniLabeledField(
    BuildContext context,
    String label, {
    required double width,
    required TextEditingController controller,
    String? suffix,
    required bool enabled,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: mutedToolTextStyle(context)),
        const SizedBox(width: 6),
        SizedBox(
          width: width,
          child: _compactTextField(
            controller: controller,
            hint: '',
            enabled: enabled,
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text(suffix, style: mutedToolTextStyle(context)),
        ],
      ],
    );
  }

  Widget _compactTextField({
    Key? key,
    required TextEditingController controller,
    required String hint,
    bool enabled = true,
    ValueChanged<String>? onSubmitted,
  }) {
    final appColors = context.appColors;
    return Container(
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: TextField(
        key: key,
        controller: controller,
        enabled: enabled,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
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

  String _describePorts(PortScanProfile profile) {
    final ports = profile.ports;
    if (ports != null) return ports.join(',');
    return '${profile.startPort}-${profile.endPort}';
  }

  String _secondsLabel(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return seconds == seconds.roundToDouble()
        ? seconds.toStringAsFixed(0)
        : seconds.toStringAsFixed(1);
  }

  String _sentenceLabel(String key) {
    final normalized = key.replaceAll('_', ' ');
    return normalized.isEmpty
        ? normalized
        : normalized[0].toUpperCase() + normalized.substring(1);
  }
}

Widget buildPortScanner() {
  return const _PortScannerView();
}
