/// Subnet calculator tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/subnet_service.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';

class _SubnetCalculatorView extends StatefulWidget {
  const _SubnetCalculatorView();

  @override
  State<_SubnetCalculatorView> createState() => _SubnetCalculatorViewState();
}

class _SubnetCalculatorViewState extends State<_SubnetCalculatorView> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _details = TextEditingController();

  SubnetInfo? _info;
  String? _error;
  int _token = 0;

  @override
  void dispose() {
    _address.dispose();
    _details.dispose();
    super.dispose();
  }

  void _calculate() {
    final token = ++_token;
    final outcome = calculateSubnet(_address.text);
    if (token != _token) return;
    final info = outcome.info;
    setState(() {
      _error = outcome.error;
      _info = info;
      _details.text = info?.toReport() ?? '';
    });
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboardText();
    setState(() => _address.text = text.trim());
    _calculate();
  }

  void _setSample() {
    setState(() => _address.text = '192.168.1.10/24');
    _calculate();
  }

  void _clear() {
    setState(() {
      _address.clear();
      _details.clear();
      _info = null;
      _error = null;
    });
  }

  Future<void> _copyDetails() async {
    await Clipboard.setData(ClipboardData(text: _details.text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: buildVerticalEditors(
            inputActions: [
              ToolButton(label: 'Go', onPressed: _calculate),
              ToolButton(label: 'Clipboard', onPressed: _pasteClipboard),
              ToolButton(label: 'Sample', onPressed: _setSample),
              ToolButton(label: 'Clear', onPressed: _clear),
            ],
            inputController: _address,
            outputController: _details,
            onInputChanged: (_) => _calculate(),
            inputPlaceholder: '192.168.1.10/24, 2001:db8::1/64, 10.0.0.0/8...',
            outputPlaceholder: 'Subnet details...',
            showInputHeader: false,
            showOutputHeader: false,
            inputOverlay: _buildSummary(context),
            // EditorPane only renders outputActions without an overlay, so
            // Copy is composed into the overlay row rather than passed here.
            outputOverlay: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToolButton(label: 'Copy', onPressed: _copyDetails),
              ],
            ),
          ),
        ),
        if (_error != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: errorToolTextStyle(context)),
            ),
          ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final appColors = context.appColors;
    final info = _info;
    return Container(
      decoration: toolSurfaceDecoration(context, radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      // The overlay is width-constrained, so the chips wrap rather than
      // overflow when a subnet has several flags set.
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (info == null)
            Text(
              'IPv4 and IPv6',
              style: TextStyle(color: appColors.mutedText, fontSize: 11.5),
            )
          else ...[
            Text(
              'IPv${info.version}',
              style: TextStyle(
                color: appColors.editorText,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            _Chip(label: '/${info.prefixLength}'),
            _Chip(label: '${info.usableHosts} hosts'),
            if (info.ipClass != null) _Chip(label: info.ipClass!),
            if (info.isPrivate) _Chip(label: 'private', accent: true),
            if (info.isLoopback) _Chip(label: 'loopback', accent: true),
            if (info.isMulticast) _Chip(label: 'multicast', accent: true),
            if (info.isLinkLocal) _Chip(label: 'link-local', accent: true),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent
            ? appColors.accent.withAlpha(38)
            : appColors.panelElevated.withAlpha(150),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: accent ? appColors.accent : appColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: accent ? appColors.accent : appColors.mutedText,
        ),
      ),
    );
  }
}

Widget buildSubnetCalculator() {
  return const _SubnetCalculatorView();
}