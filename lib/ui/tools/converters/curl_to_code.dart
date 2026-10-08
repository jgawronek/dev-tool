/// cURL to Code converter tool view.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/editors.dart';
import '../common/shared.dart';

class _CurlToCodeView extends StatefulWidget {
  const _CurlToCodeView();

  @override
  State<_CurlToCodeView> createState() => _CurlToCodeViewState();
}

class _CurlToCodeViewState extends State<_CurlToCodeView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _lang = 'NodeJS / Fetch';
  String _method = 'GET';
  final Set<String> _options = {};

  static const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'];

  // Toggleable curl building blocks → the flag(s) inserted into the command.
  static const _curlOptions = <String, String>{
    'Bearer token': "-H 'Authorization: Bearer TOKEN'",
    'JSON body': "-H 'Content-Type: application/json' -d '{\"key\": \"value\"}'",
    'Form field': "-F 'field=value'",
    'Basic auth': "-u 'user:password'",
    'Custom header': "-H 'X-Custom-Header: value'",
    'Follow redirects': '-L',
    'Insecure (skip TLS)': '-k',
    'Gzip (--compressed)': '--compressed',
  };

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  // Ensures the input is a curl command with a URL so the builder controls have
  // something to attach flags to.
  String _ensureBase(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return "curl 'https://api.example.com/endpoint'";
    if (!trimmed.startsWith('curl')) return 'curl $trimmed';
    return trimmed;
  }

  // Sets the request method by replacing the `-X`/`--request` flag (GET drops
  // it, since it's the default).
  void _setMethod(String method) {
    var text = _ensureBase(_input.text)
        .replaceAll(RegExp(r'\s+-X(\s+|=)?\S+'), '')
        .replaceAll(RegExp(r'\s+--request(\s+|=)\S+'), '')
        .trim();
    if (method != 'GET') {
      text = text.replaceFirst('curl', 'curl -X $method');
    }
    setState(() {
      _method = method;
      _input.text = text;
    });
    _run();
  }

  // Adds or removes an option's flag snippet from the command.
  void _toggleOption(String key, bool on) {
    final snippet = _curlOptions[key]!;
    var text = _ensureBase(_input.text);
    if (on) {
      if (!text.contains(snippet)) text = '$text $snippet';
      _options.add(key);
    } else {
      text = text.replaceFirst(' $snippet', '').replaceFirst(snippet, '').trim();
      _options.remove(key);
    }
    setState(() => _input.text = text);
    _run();
  }

  void _run() {
    final command = _parseCurlCommand(_input.text);
    if (command == null) {
      _output.text = '';
      setState(() {});
      return;
    }
    // Reflect the parsed method in the dropdown (e.g. after pasting a curl).
    if (_methods.contains(command.method)) _method = command.method;
    _output.text = _codeFor(command, _lang);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return buildSplitEditors(
      inputActions: [
        SmallDropdown(
          items: _methods,
          initialValue: _method,
          onChanged: _setMethod,
        ),
        _CurlOptionsMenu(
          options: _curlOptions.keys.toList(),
          active: _options,
          onToggle: _toggleOption,
        ),
        ToolButton(label: 'Go', onPressed: _run),
        ToolButton(
          label: 'Clipboard',
          onPressed: () async {
            final text = await readClipboardText();
            setState(() => _input.text = text);
            _run();
          },
        ),
        ToolButton(
          label: 'Sample',
          onPressed: () {
            setState(() => _input.text = "curl 'https://devutils.com/'");
            _run();
          },
        ),
        ToolButton(
          label: 'Clear',
          onPressed: () {
            setState(() => _input.clear());
            _output.clear();
          },
        ),
      ],
      outputActions: [
        SmallDropdown(
          items: const [
            'NodeJS / Fetch',
            'JavaScript / axios',
            'JavaScript / node:http',
            'Python / Requests',
            'PHP / cURL',
            'PHP / Guzzle',
            'Go / net/http',
            'Rust / reqwest',
            'C# / HttpClient',
            'Java / HttpClient',
            'Ruby / Net::HTTP',
            'Ruby / Faraday',
            'Swift / URLSession',
            'Dart / http',
            'Dart / dio',
            'wget',
          ],
          initialValue: _lang,
          onChanged: (value) {
            setState(() => _lang = value);
            _run();
          },
        ),
        ToolButton(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: _output.text)),
        ),
      ],
      inputController: _input,
      outputController: _output,
    );
  }

  String _codeFor(_CurlCommand command, String language) {
    final url = command.url;
    if (language == 'wget') {
      final output = command.downloadFileName;
      if (output != null) {
        return "wget -O '${_shellEscape(output)}' '${_shellEscape(url)}'";
      }
      return "wget '${_shellEscape(url)}'";
    }
    if (language == 'NodeJS / Fetch') {
      return _nodeFetchCode(command);
    }
    if (language == 'JavaScript / axios') {
      return "import axios from 'axios';\n\naxios.get('$url')\n  .then(res => console.log(res.data))\n  .catch(console.error);";
    }
    if (language == 'JavaScript / node:http') {
      final isHttps = url.startsWith('https');
      final module = isHttps ? 'https' : 'http';
      return "const $module = require('$module');\n\n$module.get('$url', res => {\n  let data = '';\n  res.on('data', chunk => data += chunk);\n  res.on('end', () => console.log(data));\n}).on('error', console.error);";
    }
    if (language == 'Python / Requests') {
      return "import requests\n\nresponse = requests.get('$url')\nprint(response.text)";
    }
    if (language == 'PHP / cURL') {
      return "<?php\n\$ch = curl_init();\ncurl_setopt(\$ch, CURLOPT_URL, '$url');\ncurl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);\n\$response = curl_exec(\$ch);\ncurl_close(\$ch);\n\necho \$response;\n";
    }
    if (language == 'PHP / Guzzle') {
      return "<?php\nrequire 'vendor/autoload.php';\n\n\$client = new GuzzleHttp\\\\Client();\n\$response = \$client->get('$url');\n\necho \$response->getBody();\n";
    }
    if (language == 'Go / net/http') {
      return "package main\n\nimport (\n  \"fmt\"\n  \"io\"\n  \"net/http\"\n)\n\nfunc main() {\n  resp, err := http.Get(\"$url\")\n  if err != nil {\n    panic(err)\n  }\n  defer resp.Body.Close()\n  body, _ := io.ReadAll(resp.Body)\n  fmt.Println(string(body))\n}\n";
    }
    if (language == 'Rust / reqwest') {
      return "use reqwest::blocking;\n\nfn main() -> Result<(), Box<dyn std::error::Error>> {\n  let body = blocking::get(\"$url\")?.text()?;\n  println!(\"{}\", body);\n  Ok(())\n}\n";
    }
    if (language == 'C# / HttpClient') {
      return "using System.Net.Http;\n\nvar client = new HttpClient();\nvar response = await client.GetStringAsync(\"$url\");\nConsole.WriteLine(response);";
    }
    if (language == 'Java / HttpClient') {
      return "import java.net.URI;\nimport java.net.http.HttpClient;\nimport java.net.http.HttpRequest;\nimport java.net.http.HttpResponse;\n\nHttpClient client = HttpClient.newHttpClient();\nHttpRequest request = HttpRequest.newBuilder()\n  .uri(URI.create(\"$url\"))\n  .build();\n\nHttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());\nSystem.out.println(response.body());";
    }
    if (language == 'Ruby / Net::HTTP') {
      return "require 'net/http'\nrequire 'uri'\n\nuri = URI.parse('$url')\nresponse = Net::HTTP.get_response(uri)\nputs response.body";
    }
    if (language == 'Ruby / Faraday') {
      return "require 'faraday'\n\nresponse = Faraday.get('$url')\nputs response.body";
    }
    if (language == 'Swift / URLSession') {
      return "import Foundation\n\nlet url = URL(string: \"$url\")!\nlet task = URLSession.shared.dataTask(with: url) { data, _, error in\n  if let error = error {\n    print(error)\n    return\n  }\n  if let data = data, let text = String(data: data, encoding: .utf8) {\n    print(text)\n  }\n}\n\ntask.resume()\n";
    }
    if (language == 'Dart / http') {
      return "import 'package:http/http.dart' as http;\n\nvoid main() async {\n  final response = await http.get(Uri.parse('$url'));\n  print(response.body);\n}\n";
    }
    if (language == 'Dart / dio') {
      return "import 'package:dio/dio.dart';\n\nvoid main() async {\n  final dio = Dio();\n  final response = await dio.get('$url');\n  print(response.data);\n}\n";
    }
    return "fetch('$url')\n  .then(res => res.text())\n  .then(console.log);";
  }
}

class _CurlCommand {
  const _CurlCommand({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.body,
    this.outputFile,
    this.remoteName = false,
    this.followRedirects = false,
    this.insecure = false,
  });

  final String url;
  final String method;
  final Map<String, String> headers;
  final String? body;
  final String? outputFile;
  final bool remoteName;
  final bool followRedirects;
  final bool insecure;

  String? get downloadFileName {
    if (outputFile != null && outputFile!.isNotEmpty) return outputFile;
    if (!remoteName) return null;
    try {
      final path = Uri.parse(url).path;
      final fileName = p.basename(path);
      return fileName.isEmpty || fileName == '/' ? 'download' : fileName;
    } catch (_) {
      return 'download';
    }
  }
}

_CurlCommand? _parseCurlCommand(String input) {
  final tokens = _splitShellWords(input.trim());
  if (tokens.isEmpty) return null;
  var index = tokens.first == 'curl' ? 1 : 0;
  var method = 'GET';
  final headers = <String, String>{};
  String? body;
  String? url;
  String? outputFile;
  var remoteName = false;
  var followRedirects = false;
  var insecure = false;

  String? nextValue() {
    if (index + 1 >= tokens.length) return null;
    index += 1;
    return tokens[index];
  }

  void parseHeader(String value) {
    final separator = value.indexOf(':');
    if (separator <= 0) return;
    final name = value.substring(0, separator).trim();
    final headerValue = value.substring(separator + 1).trim();
    if (name.isNotEmpty) headers[name] = headerValue;
  }

  const optionsWithValue = {
    '--connect-timeout',
    '--max-time',
    '--retry',
    '--proxy',
    '--resolve',
    '--cacert',
    '--cert',
    '--key',
    '--interface',
    '--user-agent',
    '--referer',
    '-A',
    '-e',
  };

  while (index < tokens.length) {
    final token = tokens[index];
    if (token == '-X' || token == '--request') {
      method = (nextValue() ?? method).toUpperCase();
    } else if (token.startsWith('-X') && token.length > 2) {
      method = token.substring(2).toUpperCase();
    } else if (token == '-H' || token == '--header') {
      final value = nextValue();
      if (value != null) parseHeader(value);
    } else if (token.startsWith('--header=')) {
      parseHeader(token.substring('--header='.length));
    } else if (token == '-d' ||
        token == '--data' ||
        token == '--data-raw' ||
        token == '--data-binary' ||
        token == '--data-urlencode') {
      body = nextValue() ?? '';
      if (method == 'GET') method = 'POST';
    } else if (token.startsWith('--data=')) {
      body = token.substring('--data='.length);
      if (method == 'GET') method = 'POST';
    } else if (token == '-o' || token == '--output') {
      outputFile = nextValue();
    } else if (token.startsWith('--output=')) {
      outputFile = token.substring('--output='.length);
    } else if (token == '-O' || token == '--remote-name') {
      remoteName = true;
    } else if (token == '-I' || token == '--head') {
      method = 'HEAD';
    } else if (token == '-L' || token == '--location') {
      followRedirects = true;
    } else if (token == '-k' || token == '--insecure') {
      insecure = true;
    } else if (token == '-u' || token == '--user') {
      final value = nextValue();
      if (value != null) {
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(value))}';
      }
    } else if (token.startsWith('--user=')) {
      final value = token.substring('--user='.length);
      headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(value))}';
    } else if (optionsWithValue.contains(token)) {
      nextValue();
    } else if (!token.startsWith('-') && url == null) {
      url = token;
    }
    index += 1;
  }

  if (url == null || url.trim().isEmpty) return null;
  return _CurlCommand(
    url: url,
    method: method,
    headers: headers,
    body: body,
    outputFile: outputFile,
    remoteName: remoteName,
    followRedirects: followRedirects,
    insecure: insecure,
  );
}

List<String> _splitShellWords(String input) {
  final words = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaped = false;

  for (final codeUnit in input.codeUnits) {
    final char = String.fromCharCode(codeUnit);
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == '\\') {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (RegExp(r'\s').hasMatch(char)) {
      if (buffer.isNotEmpty) {
        words.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) words.add(buffer.toString());
  return words;
}

String _nodeFetchCode(_CurlCommand command) {
  final downloadFileName = command.downloadFileName;
  final options = _nodeFetchOptions(command);
  final optionsArg = options.isEmpty ? '' : ', $options';
  final fetchLine = 'fetch(${_jsString(command.url)}$optionsArg)';
  if (downloadFileName != null) {
    return "const fs = require('node:fs');\n\n"
        '$fetchLine\n'
        '  .then(async (res) => {\n'
        r'    if (!res.ok) throw new Error(`HTTP ${res.status}`);'
        '\n'
        '    const buffer = Buffer.from(await res.arrayBuffer());\n'
        '    fs.writeFileSync(${_jsString(downloadFileName)}, buffer);\n'
        '  });';
  }
  return '$fetchLine\n'
      '  .then(async (res) => {\n'
      r'    if (!res.ok) throw new Error(`HTTP ${res.status}`);'
      '\n'
      '    return res.text();\n'
      '  })\n'
      '  .then(console.log);';
}

String _nodeFetchOptions(_CurlCommand command) {
  final lines = <String>[];
  if (command.method != 'GET') lines.add("method: '${command.method}'");
  if (command.headers.isNotEmpty) {
    final headerLines = command.headers.entries
        .map(
          (entry) => '    ${_jsString(entry.key)}: ${_jsString(entry.value)},',
        )
        .join('\n');
    lines.add('headers: {\n$headerLines\n  }');
  }
  if (command.body != null) lines.add('body: ${_jsString(command.body!)}');
  if (lines.isEmpty) return '';
  return '{\n  ${lines.join(',\n  ')}\n}';
}

String _jsString(String value) {
  return "'${value.replaceAll('\\', r'\\').replaceAll("'", r"\'")}'";
}

String _shellEscape(String value) {
  return value.replaceAll("'", "'\\''");
}

Widget buildCurlToCode() {
  return const _CurlToCodeView();
}

/// A toolbar multi-select for the cURL builder: a compact "Options" button that
/// opens a checkbox menu of common curl flags (bearer token, JSON body, …),
/// staying open while multiple options are toggled.
class _CurlOptionsMenu extends StatelessWidget {
  const _CurlOptionsMenu({
    required this.options,
    required this.active,
    required this.onToggle,
  });

  final List<String> options;
  final Set<String> active;
  final void Function(String key, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(appColors.panelElevated),
      ),
      menuChildren: [
        for (final option in options)
          CheckboxMenuButton(
            value: active.contains(option),
            // Keep the menu open so several options can be toggled at once.
            closeOnActivate: false,
            onChanged: (value) => onToggle(option, value ?? false),
            child: Text(option),
          ),
      ],
      builder: (context, controller, _) => ToolButton(
        label: 'Options',
        icon: Icons.tune,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
