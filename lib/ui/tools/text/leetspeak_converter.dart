/// Leetspeak converter tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';
import '../../../services/leetspeak_service.dart';
import '../../tool_sample_action.dart';

class _LeetspeakView extends StatefulWidget {
  const _LeetspeakView();

  @override
  State<_LeetspeakView> createState() => _LeetspeakViewState();
}

class _LeetspeakViewState extends State<_LeetspeakView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  LeetProfile _profile = LeetProfile.basic;
  bool _decode = true;
  double _intensity = 1;
  String? _counts;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text;
    if (text.isEmpty) {
      setState(() {
        _output.text = '';
        _counts = null;
      });
      return;
    }
    final result = _decode
        ? decodeLeetSync(text, _profile)
        : encodeLeetSync(text, _profile, _intensity);
    if (result.error != null) {
      setState(() {
        _output.text = '';
        _counts = result.error;
      });
      return;
    }
    _output.text = result.output;
    setState(() => _counts = result.summary);
  }

  void _setSample() {
    setState(() {
      _input.text = _decode
          ? 'H3ll0 W0rld 1337 sp34k'
          : 'Hello World leet speak';
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        children: [
          Expanded(
            child: buildSplitEditors(
              outputFirst: true,
              inputActions: [
                ToolButton(label: 'Go', onPressed: _run),

                SegmentedToggle(
                  options: const ['Leet → Text', 'Text → Leet'],
                  initialIndex: _decode ? 0 : 1,
                  onChanged: (index) {
                    setState(() => _decode = index == 0);
                    _run();
                  },
                ),
                SegmentedToggle(
                  options: const ['Basic', 'Common', 'Aggressive'],
                  initialIndex: _profile.index,
                  onChanged: (index) {
                    setState(() => _profile = LeetProfile.values[index]);
                    _run();
                  },
                ),
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
              inputPlaceholder: _decode ? 'H3ll0 W0rld' : 'Hello World',
              outputPlaceholder: _decode ? 'Hello World' : 'H3ll0 W0rld',
            ),
          ),
          if (!_decode)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Text('Intensity', style: mutedToolTextStyle(context)),
                  Expanded(
                    child: Slider(
                      value: _intensity,
                      onChanged: (value) => setState(() => _intensity = value),
                      onChangeEnd: (_) => _run(),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      _intensity.toStringAsFixed(2),
                      style: mutedToolTextStyle(context),
                    ),
                  ),
                ],
              ),
            ),
          if (_counts != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_counts!, style: mutedToolTextStyle(context)),
              ),
            ),
        ],
      ),
    );
  }
}

Widget buildLeetspeakConverter() => const _LeetspeakView();
