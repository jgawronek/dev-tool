/// HTML preview tool view.
library;

import 'package:flutter/material.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _HtmlPreviewView extends StatefulWidget {
  const _HtmlPreviewView();

  @override
  State<_HtmlPreviewView> createState() => _HtmlPreviewViewState();
}

class _HtmlPreviewViewState extends State<_HtmlPreviewView> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _setSample() {
    const sample = '''
<!doctype html>
<html>
<body>
  <h1>Hello from DevUtils</h1>
  <p>This is a rendered HTML preview.</p>
</body>
</html>''';
    setState(() => _input.text = sample);
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: buildAdaptiveSplit(
        initialRatio: 0.42,
        minFirstExtent: 110,
        minSecondExtent: 120,
        first: EditorPane(
          label: 'Input',
          actions: [],
          controller: _input,
          onChanged: (_) => setState(() {}),
          placeholder: '<html>...</html>',
        ),
        second: RenderedPreviewPane(
          label: 'Preview',
          html: _input.text,
          badge: 'Rendered HTML',
        ),
      ),
    );
  }
}

Widget buildHtmlPreview() {
  return const _HtmlPreviewView();
}
