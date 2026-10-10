/// PHP to JS converter tool view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/php_to_js_service.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _PhpToJsView extends StatefulWidget {
  const _PhpToJsView();

  @override
  State<_PhpToJsView> createState() => _PhpToJsViewState();
}

class _PhpToJsViewState extends State<_PhpToJsView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _output.clear();
        _error = null;
      });
      return;
    }
    try {
      _output.text = PhpToJsConverter.convert(_input.text);
      _error = null;
    } catch (error) {
      _output.clear();
      _error = 'Could not convert: $error';
    }
    setState(() {});
  }

  void _setSample() {
    setState(() {
      _input.text = r'''<?php

class UserCard {
    public $name;
    private $createdAt;

    public function __construct($name) {
        $this->name = $name;
        $this->createdAt = new Date();
    }

    public function greet($times = 1) {
        $message = "";
        foreach ($this->items as $key => $item) {
            $message .= "Hello $item! ";
        }
        return $message;
    }
}
''';
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return ToolSampleAction(
      onPressed: _setSample,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(_error!, style: errorToolTextStyle(context)),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: buildSplitEditors(
              inputController: _input,
              outputController: _output,
              onInputChanged: (_) => _run(),
              inputActions: [],
              outputActions: [
                ToolButton(
                  label: 'Copy',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _output.text)),
                ),
              ],
              inputPlaceholder:
                  '<?php\n\$name = "DevUtils";\necho "Hello \$name";',
              outputPlaceholder: 'JavaScript output...',
              showInputHeader: true,
              showOutputHeader: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Heuristic transpile (token state machine, ported from '
            'Danack/PHP-to-Javascript) — review output for complex code.',
            style: mutedToolTextStyle(context, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

Widget buildPhpToJs() {
  return const _PhpToJsView();
}
