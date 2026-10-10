/// Network scanner tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/network_scanner_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _NetworkScannerView extends StatefulWidget {
  const _NetworkScannerView();

  @override
  State<_NetworkScannerView> createState() => _NetworkScannerViewState();
}

class _NetworkScannerViewState extends State<_NetworkScannerView> {
  final TextEditingController _targets = TextEditingController(
    text: '192.168.1.0/24',
  );
  final TextEditingController _ports = TextEditingController();
  final TextEditingController _timeout = TextEditingController();
  final TextEditingController _concurrency = TextEditingController();
  final TextEditingController _report = TextEditingController();
  late final NetworkScannerService _service = NetworkScannerService();
  late final StreamSubscription<NetworkScanProgress> _progressSubscription;

  var _profileName = 'Quick LAN';
  var _reportMode = 'JSON';
  var _detailsIndex = 0;
  var _ping = true;
  var _tcpProbe = true;
  var _scanning = false;
  var _status = 'Ready. Enter a CIDR range or detect the current LAN.';
  String? _error;
  NetworkScanProgress? _progress;
  NetworkScanSummary? _summary;
  NetworkDeviceResult? _selected;
  List<LocalNetworkCandidate> _localNetworks = const [];
  int _requestId = 0;

  static const _customProfileName = 'Custom Ports';

  bool get _isCustomProfile => _profileName == _customProfileName;

  List<String> get _profileNames => [
    ...NetworkScannerService.profiles.map((profile) => profile.name),
    _customProfileName,
  ];

  @override
  void initState() {
    super.initState();
    _syncProfileFields();
    _loadLocalNetworks();
    _progressSubscription = _service.progress.listen((progress) {
      if (!mounted) return;
      setState(() {
        _progress = progress;
        if (progress.active) {
          _status =
              'Scanned ${progress.scanned}/${progress.total} hosts, ${progress.deviceCount} device(s) found.';
        }
      });
    });
  }

  @override
  void dispose() {
    _requestId++;
    _progressSubscription.cancel();
    _service.close();
    _targets.dispose();
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
      _concurrency.text = '48';
      return;
    }

    final profile = NetworkScannerService.profileByName(_profileName);
    _ports.text = profile.ports.join(',');
    _timeout.text = _secondsLabel(profile.timeout);
    _concurrency.text = profile.concurrency.toString();
  }

  Future<void> _loadLocalNetworks() async {
    final networks = await NetworkScannerService.localNetworks();
    if (!mounted) return;
    setState(() {
      _localNetworks = networks;
      if (networks.isNotEmpty && _targets.text == '192.168.1.0/24') {
        _targets.text = networks.first.cidr;
      }
    });
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    final requestId = ++_requestId;
    late final NetworkScanProfile profile;
    late final List<int>? customPorts;
    late final Duration timeout;
    late final int concurrency;

    try {
      timeout = _parseTimeout();
      concurrency = _parseConcurrency();
      NetworkScannerService.parseNetwork(_targets.text);
      if (_isCustomProfile) {
        customPorts = NetworkScannerService.parsePorts(_ports.text);
        profile = NetworkScanProfile(
          name: _customProfileName,
          description: 'Custom LAN discovery ports',
          ports: customPorts,
          timeout: timeout,
          concurrency: concurrency,
          maxHosts: 512,
        );
      } else {
        customPorts = null;
        profile = NetworkScannerService.profileByName(_profileName);
      }
    } catch (error) {
      setState(() {
        _error = error is FormatException ? error.message : error.toString();
      });
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
      _status = 'Scanning network...';
      _progress = const NetworkScanProgress(
        scanned: 0,
        total: 0,
        active: true,
        deviceCount: 0,
      );
      _summary = null;
      _selected = null;
      _report.clear();
    });

    try {
      final summary = await _service.scan(
        networkText: _targets.text,
        profile: profile,
        ports: customPorts,
        timeout: timeout,
        concurrency: concurrency,
        ping: _ping,
        tcpProbe: _tcpProbe,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _summary = summary;
        _selected = summary.results.isEmpty ? null : summary.results.first;
        _status =
            '${summary.results.length} device(s) found across ${summary.totalHosts} host(s).';
        if (summary.warnings.isNotEmpty) {
          _status = 'Completed with ${summary.warnings.length} warning(s).';
        }
        _scanning = false;
      });
      _refreshReport();
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error is FormatException ? error.message : error.toString();
        _status = 'Scan failed.';
        _scanning = false;
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
    if (value == null || value < 1 || value > 96) {
      throw const FormatException('Concurrency must be between 1 and 96.');
    }
    return value;
  }

  void _selectResult(NetworkDeviceResult result) {
    setState(() {
      _selected = result;
      _detailsIndex = 0;
    });
  }

  void _refreshReport() {
    final summary = _summary;
    if (summary == null) {
      _report.clear();
      return;
    }
    _report.text = _reportMode == 'CSV'
        ? summary.toCsvReport()
        : summary.toJsonReport();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final progress = _progress;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildControls(context),
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
            child: buildAdaptiveSplit(
              initialRatio: 0.54,
              minFirstExtent: 360,
              minSecondExtent: 320,
              first: _buildResultsPanel(context),
              second: _buildDetailsPanel(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final appColors = context.appColors;
    return ToolPanel(
      title: 'Scan options',
      expand: false,
      child: Container(
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
                  'Network',
                  style: TextStyle(
                    color: appColors.editorText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: _networkTextField(
                    key: const ValueKey('network-scanner-targets'),
                    controller: _targets,
                    hint: '192.168.1.0/24',
                    enabled: !_scanning,
                    onSubmitted: (_) => _startScan(),
                  ),
                ),
                ToolButton(
                  label: 'Detect LAN',
                  onPressed: _scanning || _localNetworks.isEmpty
                      ? null
                      : () {
                          setState(
                            () => _targets.text = _localNetworks.first.cidr,
                          );
                        },
                ),
                SmallDropdown(
                  key: ValueKey('network-profile-$_profileName'),
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
                  width: 260,
                  child: _networkTextField(
                    controller: _ports,
                    hint: '22,80,443 or 8000-8010',
                    enabled: _isCustomProfile && !_scanning && _tcpProbe,
                  ),
                ),
                ToolButton(
                  label: 'Scan',
                  onPressed: _scanning ? null : _startScan,
                ),
                ToolButton(
                  label: 'Stop',
                  onPressed: _scanning ? _stopScan : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _networkMiniField(
                  context,
                  'Timeout',
                  controller: _timeout,
                  width: 74,
                  suffix: 's',
                  enabled: !_scanning,
                ),
                _networkMiniField(
                  context,
                  'Concurrency',
                  controller: _concurrency,
                  width: 70,
                  enabled: !_scanning,
                ),
                _networkCheckbox(
                  context,
                  label: 'Ping',
                  value: _ping,
                  onChanged: _scanning
                      ? null
                      : (value) => setState(() => _ping = value ?? true),
                ),
                _networkCheckbox(
                  context,
                  label: 'TCP ports',
                  value: _tcpProbe,
                  onChanged: _scanning
                      ? null
                      : (value) => setState(() => _tcpProbe = value ?? true),
                ),
                Text(
                  _isCustomProfile
                      ? 'Custom device discovery'
                      : NetworkScannerService.profileByName(
                          _profileName,
                        ).description,
                  style: mutedToolTextStyle(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsPanel(BuildContext context) {
    final summary = _summary;
    final results = summary?.results ?? const <NetworkDeviceResult>[];
    return ToolPanel(
      title: 'Devices',
      expand: true,
      child: Container(
        child: results.isEmpty && (summary?.warnings.isEmpty ?? true)
            ? Center(
                child: Text(
                  _scanning
                      ? 'Scanning network...'
                      : 'Responsive devices will appear here',
                  style: mutedToolTextStyle(context),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  _buildNetworkStats(context, summary),
                  if (summary != null && summary.warnings.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final warning in summary.warnings)
                      _networkWarningTile(context, warning),
                  ],
                  const SizedBox(height: 8),
                  for (final result in results)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _networkResultTile(context, result),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildNetworkStats(BuildContext context, NetworkScanSummary? summary) {
    final total = summary?.totalHosts ?? _progress?.total ?? 0;
    final open = summary?.results.length ?? 0;
    final ping = summary?.pingCount ?? 0;
    final ports = summary?.openPortCount ?? 0;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _networkPill(context, 'Devices', '$open'),
        _networkPill(context, 'Hosts', '$total'),
        _networkPill(context, 'Ping', '$ping'),
        _networkPill(context, 'Ports', '$ports'),
      ],
    );
  }

  Widget _networkResultTile(BuildContext context, NetworkDeviceResult result) {
    final appColors = context.appColors;
    final selected = identical(_selected, result);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _selectResult(result),
      child: Container(
        decoration: BoxDecoration(
          color: appColors.panelElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? appColors.accent : appColors.border,
            width: selected ? 1.5 : 1,
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
                    result.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: appColors.editorText,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  result.evidenceLabel,
                  style: mutedToolTextStyle(context, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              result.openPorts.isEmpty
                  ? 'No probed TCP ports open'
                  : result.openPorts
                        .map((port) => '${port.port}/${port.service}')
                        .join('  '),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appColors.editorText),
            ),
            if (result.latencyMs != null) ...[
              const SizedBox(height: 6),
              Text(
                '${result.latencyMs} ms ping response',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: appColors.mutedText,
                  fontFamily: 'Menlo',
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _networkWarningTile(BuildContext context, String warning) {
    final appColors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: appColors.warning.withAlpha(24),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.warning.withAlpha(120)),
      ),
      padding: const EdgeInsets.all(10),
      child: Text(
        warning,
        style: TextStyle(color: appColors.editorText, fontSize: 12),
      ),
    );
  }

  Widget _buildDetailsPanel(BuildContext context) {
    return ToolPanel(
      title: 'Device details',
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
                    options: const ['Evidence', 'Report'],
                    initialIndex: _detailsIndex,
                    onChanged: (index) => setState(() => _detailsIndex = index),
                  ),
                  if (_detailsIndex == 1) ...[
                    const SizedBox(width: 10),
                    SmallDropdown(
                      key: ValueKey('network-report-$_reportMode'),
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
              child: _detailsIndex == 0
                  ? _buildEvidencePanel(context)
                  : EditorPane(
                      label: 'Report',
                      actions: const [],
                      controller: _report,
                      readOnly: true,
                      placeholder: 'Run a network scan to generate a report...',
                      showHeader: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvidencePanel(BuildContext context) {
    final selected = _selected;
    if (selected == null) {
      return Center(
        child: Text(
          'Select a device to inspect discovery evidence',
          style: mutedToolTextStyle(context),
        ),
      );
    }

    return ListView(
      children: [
        _networkDetailRow(context, 'IP address', selected.ip),
        if (selected.hostname != null)
          _networkDetailRow(context, 'Hostname', selected.hostname!),
        _networkDetailRow(
          context,
          'Ping',
          selected.pingResponded ? 'Responded' : 'No response',
        ),
        if (selected.latencyMs != null)
          _networkDetailRow(context, 'Latency', '${selected.latencyMs} ms'),
        _networkDetailRow(
          context,
          'Open ports',
          selected.openPorts.isEmpty
              ? 'None found in the selected probe set'
              : selected.openPorts.map((port) => port.port).join(', '),
        ),
        const SizedBox(height: 12),
        Text(
          'Services',
          style: TextStyle(
            color: context.appColors.editorText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        if (selected.openPorts.isEmpty)
          Text(
            'The device responded to ping but did not expose any probed TCP ports.',
            style: mutedToolTextStyle(context),
          )
        else
          for (final port in selected.openPorts)
            _networkServiceRow(context, port),
        if (_summary?.warnings.isNotEmpty ?? false) ...[
          const SizedBox(height: 12),
          Text(
            'Warnings',
            style: TextStyle(
              color: context.appColors.editorText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final warning in _summary!.warnings)
            _networkBullet(context, warning),
        ],
      ],
    );
  }

  Widget _networkServiceRow(BuildContext context, NetworkDevicePort port) {
    final appColors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              port.port.toString(),
              style: TextStyle(
                color: appColors.editorText,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${port.service} · ${port.protocol} · ${port.category}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: appColors.editorText),
            ),
          ),
          if (port.encrypted)
            Text(
              'encrypted',
              style: TextStyle(
                color: appColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _networkPill(BuildContext context, String label, String value) {
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
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkDetailRow(BuildContext context, String label, String value) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
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
                fontFamily: value.length > 22 ? 'Menlo' : null,
                fontSize: value.length > 22 ? 11.5 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkBullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('- ', style: TextStyle(color: context.appColors.mutedText)),
          Expanded(
            child: Text(text, style: mutedToolTextStyle(context, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _networkCheckbox(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool?>? onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: onChanged),
        Text(label, style: TextStyle(color: context.appColors.editorText)),
      ],
    );
  }

  Widget _networkMiniField(
    BuildContext context,
    String label, {
    required TextEditingController controller,
    required double width,
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
          child: _networkTextField(
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

  Widget _networkTextField({
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

  String _secondsLabel(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return seconds == seconds.roundToDouble()
        ? seconds.toStringAsFixed(0)
        : seconds.toStringAsFixed(1);
  }
}

Widget buildNetworkScanner() {
  return const _NetworkScannerView();
}
