/// Auth TOTP tool view.
library;

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../ui/app_colors.dart';
import '../common/shared.dart';

class _AuthTotpView extends StatefulWidget {
  const _AuthTotpView();

  @override
  State<_AuthTotpView> createState() => _AuthTotpViewState();
}

class _AuthTotpViewState extends State<_AuthTotpView> {
  List<_TotpEntry> _entries = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('totp_entries');
      if (raw == null || raw.isEmpty) {
        setState(() {
          _entries = [
            _TotpEntry(
              name: 'twitter',
              secret: 'JBSWY3DPEHPK3PXP',
              color: const Color(0xFFE6E6E6),
            ),
          ];
        });
      } else {
        final decoded = jsonDecode(raw) as List<dynamic>;
        setState(() {
          _entries = decoded
              .map(
                (entry) => _TotpEntry(
                  name: entry['name'] as String? ?? 'New app',
                  secret: entry['secret'] as String? ?? '',
                  color: Color(entry['color'] as int? ?? 0xFFE6E6E6),
                ),
              )
              .toList();
        });
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _openAddDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => _TotpAddDialog(
        onAdd: (entry) {
          setState(() => _entries.add(entry));
          _saveEntries();
        },
      ),
    );
  }

  void _openEditDialog(int index) {
    final entry = _entries[index];
    showDialog<void>(
      context: context,
      builder: (context) => _TotpAddDialog(
        title: 'Edit application',
        actionLabel: 'Save',
        initialEntry: entry,
        onAdd: (updated) {
          setState(() => _entries[index] = updated);
          _saveEntries();
        },
      ),
    );
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _entries
          .map(
            (entry) => {
              'name': entry.name,
              'secret': entry.secret,
              'color': entry.color.toARGB32(),
            },
          )
          .toList(),
    );
    await prefs.setString('totp_entries', encoded);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (var i = 0; i < _entries.length; i++)
            _TotpCard(entry: _entries[i], onEdit: () => _openEditDialog(i)),
          _TotpAddCard(onTap: _openAddDialog),
        ],
      ),
    );
  }
}

class _TotpEntry {
  _TotpEntry({required this.name, required this.secret, required this.color});

  final String name;
  final String secret;
  final Color color;
}

class _TotpCard extends StatelessWidget {
  const _TotpCard({required this.entry, required this.onEdit});

  final _TotpEntry entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final current = _totpCode(entry.secret, now);
    final next = _totpCode(entry.secret, now + 30);
    final secondsRemaining = 30 - (now % 30);
    final warn = secondsRemaining <= 5;
    final blink = warn && (now % 2 == 0);
    final currentColor = blink ? appColors.error : appColors.editorText;
    final nextColor = blink ? appColors.error : appColors.mutedText;
    return Container(
      width: 240,
      height: 132,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: appColors.panelElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appColors.border),
        boxShadow: [
          BoxShadow(
            color: appColors.shadow.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: entry.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current',
                      style: mutedToolTextStyle(context, fontSize: 10),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        current,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: currentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next',
                      style: mutedToolTextStyle(context, fontSize: 10),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        next,
                        style: TextStyle(fontSize: 14, color: nextColor),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${secondsRemaining}s',
                    style: mutedToolTextStyle(context, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: Icon(
                      Icons.edit,
                      size: 16,
                      color: appColors.mutedText,
                    ),
                    tooltip: 'Edit entry',
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.name,
            style: TextStyle(fontSize: 13, color: appColors.editorText),
          ),
        ],
      ),
    );
  }
}

class _TotpAddCard extends StatelessWidget {
  const _TotpAddCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 240,
        height: 132,
        decoration: BoxDecoration(
          color: appColors.panelElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: appColors.border),
        ),
        child: Center(
          child: Icon(Icons.add, size: 40, color: appColors.mutedText),
        ),
      ),
    );
  }
}

class _TotpAddDialog extends StatefulWidget {
  const _TotpAddDialog({
    required this.onAdd,
    this.initialEntry,
    this.title = 'New application',
    this.actionLabel = 'Add',
  });

  final ValueChanged<_TotpEntry> onAdd;
  final _TotpEntry? initialEntry;
  final String title;
  final String actionLabel;

  @override
  State<_TotpAddDialog> createState() => _TotpAddDialogState();
}

class _TotpAddDialogState extends State<_TotpAddDialog> {
  final TextEditingController _secret = TextEditingController();
  final TextEditingController _name = TextEditingController();
  Color _selected = const Color(0xFFE6E6E6);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEntry;
    if (initial != null) {
      _secret.text = initial.secret;
      _name.text = initial.name;
      _selected = initial.color;
    }
  }

  @override
  void dispose() {
    _secret.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final secret = _secret.text.trim();
    final name = _name.text.trim().isEmpty ? 'New app' : _name.text.trim();
    if (secret.isEmpty) return;
    widget.onAdd(_TotpEntry(name: name, secret: secret, color: _selected));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: appColors.panelHeader,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Secret key',
                      style: mutedToolTextStyle(context, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    InlineTextField(
                      hintText: 'Paste or enter secret',
                      controller: _secret,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Application name',
                      style: mutedToolTextStyle(context, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    InlineTextField(
                      hintText: 'Optional label',
                      controller: _name,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Accent color',
                      style: mutedToolTextStyle(context, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _totpPalette
                          .map(
                            (color) => GestureDetector(
                              onTap: () => setState(() => _selected = color),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _selected == color
                                        ? appColors.editorText
                                        : appColors.border,
                                    width: _selected == color ? 2 : 1,
                                  ),
                                  boxShadow: _selected == color
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x22000000),
                                            blurRadius: 6,
                                            offset: Offset(0, 2),
                                          ),
                                        ]
                                      : const [],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appColors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(widget.actionLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<Color> _totpPalette = [
  Colors.white,
  Colors.black,
  Color(0xFFFF4A3D),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
  Color(0xFF673AB7),
  Color(0xFF3F51B5),
  Color(0xFF2196F3),
  Color(0xFF03A9F4),
  Color(0xFF00BCD4),
  Color(0xFF009688),
  Color(0xFF4CAF50),
  Color(0xFF8BC34A),
  Color(0xFFCDDC39),
  Color(0xFFFFEB3B),
  Color(0xFFFFC107),
  Color(0xFFFF9800),
  Color(0xFFFF5722),
  Color(0xFF795548),
  Color(0xFF9E9E9E),
  Color(0xFF607D8B),
];

String _totpCode(String secret, int timestampSeconds) {
  final key = _base32Decode(secret);
  if (key.isEmpty) return '------';
  final counter = timestampSeconds ~/ 30;
  final bytes = ByteData(8)..setInt64(0, counter);
  final hmac = crypto.Hmac(crypto.sha1, key);
  final digest = hmac.convert(bytes.buffer.asUint8List()).bytes;
  final offset = digest.last & 0x0f;
  final code =
      ((digest[offset] & 0x7f) << 24) |
      ((digest[offset + 1] & 0xff) << 16) |
      ((digest[offset + 2] & 0xff) << 8) |
      (digest[offset + 3] & 0xff);
  final otp = code % 1000000;
  return otp.toString().padLeft(6, '0');
}

List<int> _base32Decode(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final output = <int>[];
  for (final char in cleaned.split('')) {
    final index = alphabet.indexOf(char);
    if (index == -1) continue;
    buffer = (buffer << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      output.add((buffer >> bits) & 0xff);
    }
  }
  return output;
}

Widget buildAuthTotp() {
  return const _AuthTotpView();
}
