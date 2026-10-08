/// Color Converter tool view.
library;

import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/app_colors.dart';
import '../common/editors.dart';
import '../common/shared.dart';

int _colorComponent(double value) {
  return (value * 255.0).round().clamp(0, 255).toInt();
}

class _ColorConverterView extends StatefulWidget {
  const _ColorConverterView();

  @override
  State<_ColorConverterView> createState() => _ColorConverterViewState();
}

class _ColorConverterViewState extends State<_ColorConverterView> {
  final TextEditingController _input = TextEditingController(text: '#5CC07F');
  final TextEditingController _hex = TextEditingController();
  final TextEditingController _hexAlpha = TextEditingController();
  final TextEditingController _rgb = TextEditingController();
  final TextEditingController _rgba = TextEditingController();
  final TextEditingController _hsl = TextEditingController();
  final TextEditingController _hsla = TextEditingController();
  final TextEditingController _hsv = TextEditingController();
  final TextEditingController _hwb = TextEditingController();
  final TextEditingController _cmyk = TextEditingController();
  Color _color = const Color(0xFF5CC07F);
  String? _error;

  @override
  void initState() {
    super.initState();
    _setColor(_color);
  }

  void _updateFromInput(String text) {
    final color = _parseColorValue(text);
    if (color == null) {
      setState(() => _error = text.trim().isEmpty ? null : 'Invalid color.');
      return;
    }
    _setColor(color, updateInput: false);
  }

  void _setColor(Color color, {bool updateInput = true}) {
    _color = color;
    _error = null;
    if (updateInput) {
      _input.text = _cssHex(color).toUpperCase();
    }
    _fillFields(color);
    setState(() {});
  }

  void _fillFields(Color color) {
    final r = _colorComponent(color.r);
    final g = _colorComponent(color.g);
    final b = _colorComponent(color.b);
    final alpha = _colorComponent(color.a);
    final a = alpha / 255;
    _hex.text = _cssHex(color);
    _hexAlpha.text = _cssHex(color, includeAlpha: true);
    _rgb.text = 'rgb($r, $g, $b)';
    _rgba.text = 'rgba($r, $g, $b, ${a.toStringAsFixed(2)})';
    final hsl = _rgbToHsl(r, g, b);
    _hsl.text = 'hsl(${hsl[0]}deg, ${hsl[1]}%, ${hsl[2]}%)';
    _hsla.text =
        'hsla(${hsl[0]}deg, ${hsl[1]}%, ${hsl[2]}%, ${a.toStringAsFixed(2)})';
    final hsv = _rgbToHsv(r, g, b);
    _hsv.text = 'hsb(${hsv[0]}deg, ${hsv[1]}%, ${hsv[2]}%)';
    _hwb.text = 'hwb(${hsv[0]}deg, ${hsv[1]}%, ${100 - hsv[1]}%)';
    final cmyk = _rgbToCmyk(r, g, b);
    _cmyk.text = 'cmyk(${cmyk[0]}%, ${cmyk[1]}%, ${cmyk[2]}%, ${cmyk[3]}%)';
  }

  List<int> _rgbToHsl(int r, int g, int b) {
    final rf = r / 255;
    final gf = g / 255;
    final bf = b / 255;
    final max = [rf, gf, bf].reduce(maxOf);
    final min = [rf, gf, bf].reduce(minOf);
    var h = 0.0;
    var s = 0.0;
    final l = (max + min) / 2;
    if (max != min) {
      final d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      if (max == rf) {
        h = (gf - bf) / d + (gf < bf ? 6 : 0);
      } else if (max == gf) {
        h = (bf - rf) / d + 2;
      } else {
        h = (rf - gf) / d + 4;
      }
      h /= 6;
    }
    return [(h * 360).round(), (s * 100).round(), (l * 100).round()];
  }

  List<int> _rgbToHsv(int r, int g, int b) {
    final rf = r / 255;
    final gf = g / 255;
    final bf = b / 255;
    final max = [rf, gf, bf].reduce(maxOf);
    final min = [rf, gf, bf].reduce(minOf);
    final d = max - min;
    var h = 0.0;
    final s = max == 0 ? 0 : d / max;
    if (max != min) {
      if (max == rf) {
        h = (gf - bf) / d + (gf < bf ? 6 : 0);
      } else if (max == gf) {
        h = (bf - rf) / d + 2;
      } else {
        h = (rf - gf) / d + 4;
      }
      h /= 6;
    }
    return [(h * 360).round(), (s * 100).round(), (max * 100).round()];
  }

  List<int> _rgbToCmyk(int r, int g, int b) {
    final rf = r / 255;
    final gf = g / 255;
    final bf = b / 255;
    final k = 1 - [rf, gf, bf].reduce(maxOf);
    if (k == 1) return [0, 0, 0, 100];
    final c = (1 - rf - k) / (1 - k);
    final m = (1 - gf - k) / (1 - k);
    final y = (1 - bf - k) / (1 - k);
    return [
      (c * 100).round(),
      (m * 100).round(),
      (y * 100).round(),
      (k * 100).round(),
    ];
  }

  double maxOf(double a, double b) => a > b ? a : b;
  double minOf(double a, double b) => a < b ? a : b;

  @override
  Widget build(BuildContext context) {
    return ResizableSplit(
      horizontal: true,
      initialRatio: 0.74,
      minFirstExtent: 420,
      minSecondExtent: 280,
      first: _buildColorDetails(context),
      second: _ColorPalettePanel(
        color: _color,
        hex: _hex.text,
        rgb: _rgb.text,
        onColorChanged: _setColor,
      ),
    );
  }

  Widget _buildColorDetails(BuildContext context) {
    final appColors = context.appColors;
    final rows = [
      ('Hex', _hex.text),
      ('Hex alpha', _hexAlpha.text),
      ('RGB', _rgb.text),
      ('RGBA', _rgba.text),
      ('HSL', _hsl.text),
      ('HSLA', _hsla.text),
      ('HSB (HSV)', _hsv.text),
      ('HWB', _hwb.text),
      ('CMYK', _cmyk.text),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: toolSurfaceDecoration(context),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Input',
                  style: TextStyle(
                    color: appColors.editorText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InlineTextField(
                    hintText: '#5CC07F, rgb(92, 192, 127)',
                    controller: _input,
                    onChanged: _updateFromInput,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: errorToolTextStyle(context)),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return _ColorValueRow(label: row.$1, value: row.$2);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Color?> _showColorPickerDialog(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _ColorPickerDialog(initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexField;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexField = TextEditingController(
      text: _cssHex(widget.initial).toUpperCase(),
    );
  }

  @override
  void dispose() {
    _hexField.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  void _update(HSVColor next) {
    setState(() {
      _hsv = next;
      _hexField.text = _cssHex(next.toColor()).toUpperCase();
    });
  }

  void _applyHex(String text) {
    final parsed = _parseColorValue(text);
    if (parsed != null) {
      setState(() => _hsv = HSVColor.fromColor(parsed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Dialog(
      backgroundColor: appColors.panelElevated,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.5,
                child: _SvPicker(hsv: _hsv, onChanged: _update),
              ),
              const SizedBox(height: 12),
              _HueBar(
                hue: _hsv.hue,
                onChanged: (hue) => _update(_hsv.withHue(hue)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: appColors.border),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _hexField,
                      onChanged: _applyHex,
                      onSubmitted: _applyHex,
                      style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_color),
                    child: const Text('Select'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SvPicker extends StatelessWidget {
  const _SvPicker({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        void handle(Offset position) {
          final saturation = (position.dx / width).clamp(0.0, 1.0);
          final value = (1 - position.dy / height).clamp(0.0, 1.0);
          onChanged(hsv.withSaturation(saturation).withValue(value));
        }

        return GestureDetector(
          onPanDown: (details) => handle(details.localPosition),
          onPanUpdate: (details) => handle(details.localPosition),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: hueColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.white, Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: hsv.saturation * width - 8,
                top: (1 - hsv.value) * height - 8,
                child: _PickerThumb(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void handle(Offset position) {
          onChanged((position.dx / width * 360).clamp(0.0, 360.0));
        }

        return GestureDetector(
          onPanDown: (details) => handle(details.localPosition),
          onPanUpdate: (details) => handle(details.localPosition),
          child: SizedBox(
            height: 18,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF0000),
                          Color(0xFFFFFF00),
                          Color(0xFF00FF00),
                          Color(0xFF00FFFF),
                          Color(0xFF0000FF),
                          Color(0xFFFF00FF),
                          Color(0xFFFF0000),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: hue / 360 * width - 8,
                  top: 1,
                  child: _PickerThumb(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PickerThumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
      ),
    );
  }
}

class _ColorPalettePanel extends StatelessWidget {
  const _ColorPalettePanel({
    required this.color,
    required this.hex,
    required this.rgb,
    required this.onColorChanged,
  });

  final Color color;
  final String hex;
  final String rgb;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final hsv = HSVColor.fromColor(color);
    final alpha = _colorComponent(color.a);
    final textColor = _readableTextColor(color);
    final presets = const [
      Color(0xFFE11D48),
      Color(0xFFF97316),
      Color(0xFFEAB308),
      Color(0xFF22C55E),
      Color(0xFF14B8A6),
      Color(0xFF06B6D4),
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFF111827),
      Color(0xFF6B7280),
      Color(0xFFF8FAFC),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
      child: Container(
        key: const ValueKey('color-converter-swatch-panel'),
        decoration: toolSurfaceDecoration(context),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Palette',
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () async {
                    final picked = await _showColorPickerDialog(context, color);
                    if (picked != null) onColorChanged(picked);
                  },
                  child: Tooltip(
                    message: 'Click to pick a color',
                    child: Container(
                      height: 104,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: appColors.border),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            hex.isEmpty ? '#000000' : hex.toUpperCase(),
                            style: TextStyle(
                              color: textColor,
                              fontFamily: 'Menlo',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rgb,
                            style: TextStyle(
                              color: textColor.withAlpha(225),
                              fontFamily: 'Menlo',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ColorSlider(
                label: 'Hue',
                value: hsv.hue,
                min: 0,
                max: 360,
                divisions: 360,
                displayValue: '${hsv.hue.round()}deg',
                onChanged: (value) {
                  onColorChanged(hsv.withHue(value).toColor());
                },
              ),
              _ColorSlider(
                label: 'Saturation',
                value: hsv.saturation * 100,
                min: 0,
                max: 100,
                divisions: 100,
                displayValue: '${(hsv.saturation * 100).round()}%',
                onChanged: (value) {
                  onColorChanged(hsv.withSaturation(value / 100).toColor());
                },
              ),
              _ColorSlider(
                label: 'Value',
                value: hsv.value * 100,
                min: 0,
                max: 100,
                divisions: 100,
                displayValue: '${(hsv.value * 100).round()}%',
                onChanged: (value) {
                  onColorChanged(hsv.withValue(value / 100).toColor());
                },
              ),
              _ColorSlider(
                label: 'Alpha',
                value: alpha.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                displayValue: alpha.toString(),
                onChanged: (value) {
                  onColorChanged(
                    Color.fromARGB(
                      value.round(),
                      _colorComponent(color.r),
                      _colorComponent(color.g),
                      _colorComponent(color.b),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Presets',
                style: TextStyle(
                  color: appColors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in presets)
                    _PaletteChip(
                      color: preset,
                      selected: _sameColorIgnoringAlpha(color, preset),
                      onTap: () {
                        onColorChanged(
                          Color.fromARGB(
                            alpha,
                            _colorComponent(preset.r),
                            _colorComponent(preset.g),
                            _colorComponent(preset.b),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: appColors.editorText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                displayValue,
                style: TextStyle(
                  color: appColors.mutedText,
                  fontFamily: 'Menlo',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Semantics(
      button: true,
      label: 'Pick ${_cssHex(color).toUpperCase()}',
      child: InkWell(
        key: ValueKey('color-preset-${_cssHex(color)}'),
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? appColors.accent : appColors.border,
              width: selected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorValueRow extends StatelessWidget {
  const _ColorValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Listener(
      onPointerDown: (event) {
        if ((event.buttons & kSecondaryMouseButton) != 0) {
          showMenu<String>(
            context: context,
            color: appColors.panelElevated,
            position: RelativeRect.fromLTRB(
              event.position.dx,
              event.position.dy,
              event.position.dx,
              event.position.dy,
            ),
            items: const [
              PopupMenuItem(value: 'copy', child: Text('Copy value')),
            ],
          ).then((selected) {
            if (selected == 'copy') {
              Clipboard.setData(ClipboardData(text: value));
            }
          });
        }
      },
      child: Container(
        decoration: toolSurfaceDecoration(context, radius: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: Text(
                label,
                style: TextStyle(
                  color: appColors.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  value,
                  style: TextStyle(
                    color: appColors.editorText,
                    fontFamily: 'Menlo',
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color? _parseColorValue(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;

  final rgbMatch = RegExp(
    r'^rgba?\(([^)]+)\)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (rgbMatch != null) {
    final parts = rgbMatch
        .group(1)!
        .split(RegExp(r'\s*,\s*|\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3 || parts.length > 4) return null;
    final r = _parseColorByte(parts[0]);
    final g = _parseColorByte(parts[1]);
    final b = _parseColorByte(parts[2]);
    if (r == null || g == null || b == null) return null;
    final alpha = parts.length == 4 ? _parseAlpha(parts[3]) : 255;
    if (alpha == null) return null;
    return Color.fromARGB(alpha, r, g, b);
  }

  if (value.startsWith('#')) {
    value = value.substring(1);
  } else if (value.toLowerCase().startsWith('0x')) {
    final hex = value.substring(2).replaceAll(RegExp(r'[\s_]+'), '');
    if (hex.length != 8) return null;
    final argb = int.tryParse(hex, radix: 16);
    return argb == null ? null : Color(argb);
  }

  final hex = value.replaceAll(RegExp(r'[\s_]+'), '');
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;

  String expandShort(String input) =>
      input.split('').map((char) => '$char$char').join();

  final normalized = switch (hex.length) {
    3 => '${expandShort(hex)}ff',
    4 => expandShort(hex),
    6 => '${hex}ff',
    8 => hex,
    _ => '',
  };
  if (normalized.isEmpty) return null;
  final r = int.parse(normalized.substring(0, 2), radix: 16);
  final g = int.parse(normalized.substring(2, 4), radix: 16);
  final b = int.parse(normalized.substring(4, 6), radix: 16);
  final a = int.parse(normalized.substring(6, 8), radix: 16);
  return Color.fromARGB(a, r, g, b);
}

int? _parseColorByte(String text) {
  if (text.endsWith('%')) {
    final percent = double.tryParse(text.substring(0, text.length - 1));
    if (percent == null || percent < 0 || percent > 100) return null;
    return (percent * 2.55).round().clamp(0, 255);
  }
  final value = int.tryParse(text);
  if (value == null || value < 0 || value > 255) return null;
  return value;
}

int? _parseAlpha(String text) {
  if (text.endsWith('%')) {
    final percent = double.tryParse(text.substring(0, text.length - 1));
    if (percent == null || percent < 0 || percent > 100) return null;
    return (percent * 2.55).round().clamp(0, 255);
  }
  final decimal = double.tryParse(text);
  if (decimal == null) return null;
  if (decimal >= 0 && decimal <= 1) return (decimal * 255).round();
  if (decimal >= 0 && decimal <= 255) return decimal.round();
  return null;
}

String _cssHex(Color color, {bool includeAlpha = false}) {
  final values = [
    _colorComponent(color.r),
    _colorComponent(color.g),
    _colorComponent(color.b),
    if (includeAlpha) _colorComponent(color.a),
  ];
  return '#${bytesToHex(values, lower: true)}';
}

bool _sameColorIgnoringAlpha(Color a, Color b) {
  return _colorComponent(a.r) == _colorComponent(b.r) &&
      _colorComponent(a.g) == _colorComponent(b.g) &&
      _colorComponent(a.b) == _colorComponent(b.b);
}

Color _readableTextColor(Color color) {
  final r = _colorComponent(color.r);
  final g = _colorComponent(color.g);
  final b = _colorComponent(color.b);
  final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.58 ? const Color(0xFF111827) : Colors.white;
}

Widget buildColorConverter() {
  return const _ColorConverterView();
}
