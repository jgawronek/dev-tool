/// Lorem ipsum generator tool view.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';

class _LoremIpsumView extends StatefulWidget {
  const _LoremIpsumView();

  @override
  State<_LoremIpsumView> createState() => _LoremIpsumViewState();
}

class _LoremIpsumViewState extends State<_LoremIpsumView> {
  final TextEditingController _output = TextEditingController();
  String _count = 'x1';
  String _mode = 'Replace';

  @override
  void dispose() {
    _output.dispose();
    super.dispose();
  }

  void _addText(String text) {
    final count = int.tryParse(_count.replaceAll('x', '')) ?? 1;
    final repeated = List<String>.filled(count, text).join('\n\n');
    if (_mode == 'Append' && _output.text.isNotEmpty) {
      _output.text = '${_output.text}\n$repeated';
    } else {
      _output.text = repeated;
    }
    setState(() {});
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
  }

  @override
  Widget build(BuildContext context) {
    return ResizableSplit(
      horizontal: true,
      initialRatio: 0.34,
      minFirstExtent: 300,
      minSecondExtent: 420,
      first: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LoremControlRow(
                label: 'Count',
                child: SmallDropdown(
                  items: const ['x1', 'x5', 'x10'],
                  initialValue: _count,
                  width: 104,
                  onChanged: (value) => setState(() => _count = value),
                ),
              ),
              const SizedBox(height: 8),
              _LoremControlRow(
                label: 'Mode',
                child: SmallDropdown(
                  items: const ['Replace', 'Append'],
                  initialValue: _mode,
                  width: 124,
                  onChanged: (value) => setState(() => _mode = value),
                ),
              ),
              const SizedBox(height: 18),
              _LoremSection(
                title: 'Text',
                children: [
                  _LoremActionButton(
                    label: 'Paragraph',
                    onPressed: () => _addText(_paragraph()),
                  ),
                  _LoremActionButton(
                    label: 'Sentence',
                    onPressed: () => _addText('Lorem ipsum dolor sit amet.'),
                  ),
                  _LoremActionButton(
                    label: 'Word',
                    onPressed: () => _addText('Lorem'),
                  ),
                  _LoremActionButton(
                    label: 'Title',
                    onPressed: () => _addText('Lorem Ipsum Title'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _LoremSection(
                title: 'Identity',
                children: [
                  _LoremActionButton(
                    label: 'First name',
                    onPressed: () => _addText('Alex'),
                  ),
                  _LoremActionButton(
                    label: 'Last name',
                    onPressed: () => _addText('Johnson'),
                  ),
                  _LoremActionButton(
                    label: 'Full name',
                    onPressed: () => _addText('Alex Johnson'),
                  ),
                  _LoremActionButton(
                    label: 'Email',
                    onPressed: () => _addText('hello@example.com'),
                  ),
                  _LoremActionButton(
                    label: 'URL',
                    onPressed: () => _addText('https://example.com'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _LoremSection(
                title: 'Social',
                children: [
                  _LoremActionButton(
                    label: 'Short tweet',
                    onPressed: () => _addText('Building tools offline.'),
                  ),
                  _LoremActionButton(
                    label: 'Long tweet',
                    onPressed: () => _addText(
                      'DevUtils helps you with daily tasks, offline and fast.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      second: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Output',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              ToolButton(
                label: 'Reset output',
                onPressed: () => setState(() => _output.clear()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EditorPane(
              label: '',
              actions: const [],
              controller: _output,
              placeholder: 'Generated text...',
              copyAction: _copyOutput,
              showHeader: false,
            ),
          ),
        ],
      ),
    );
  }

  String _paragraph() {
    return 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.';
  }
}

class _LoremControlRow extends StatelessWidget {
  const _LoremControlRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: context.appColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _LoremSection extends StatelessWidget {
  const _LoremSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.appColors.editorText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }
}

class _LoremActionButton extends StatelessWidget {
  const _LoremActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return SizedBox(
      width: 132,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          minimumSize: const Size(0, 34),
          side: BorderSide(color: appColors.border),
          backgroundColor: appColors.panelElevated,
          foregroundColor: appColors.editorText,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 12.5),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

Widget buildLoremIpsum() {
  return const _LoremIpsumView();
}
