/// XML beautify/minify tool view.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../common/shared.dart';

String _beautifyXml(String xml, String indent) {
  final trimmed = xml.trim();
  if (trimmed.isEmpty) return '';
  final tokens = RegExp(
    r'<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<[^>]+>|[^<]+',
  ).allMatches(trimmed);
  final lines = <String>[];
  var level = 0;
  String pad() => List.filled(level, indent).join();
  for (final match in tokens) {
    final token = match.group(0) ?? '';
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) continue;
    if (trimmedToken.startsWith('<')) {
      final isComment = trimmedToken.startsWith('<!--');
      final isCdata = trimmedToken.startsWith('<![CDATA[');
      final isDeclaration =
          trimmedToken.startsWith('<?') || trimmedToken.startsWith('<!');
      final isClosing = trimmedToken.startsWith('</');
      final isSelfClosing =
          trimmedToken.endsWith('/>') || isComment || isCdata || isDeclaration;
      if (isClosing) level = max(0, level - 1);
      lines.add('${pad()}$trimmedToken');
      if (!isClosing && !isSelfClosing) level += 1;
    } else {
      final text = trimmedToken.replaceAll(RegExp(r'\s+'), ' ');
      if (text.isNotEmpty) lines.add('${pad()}$text');
    }
  }
  return lines.join('\n');
}

String _minifyXml(String xml, bool keepComments) {
  var output = xml;
  if (!keepComments) {
    output = output.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  }
  output = output.replaceAll(RegExp(r'>\s+<'), '><');
  output = output.replaceAll(RegExp(r'\s{2,}'), ' ');
  return output.trim();
}

Widget buildXmlBeautifyMinify() {
  return const MarkupBeautifyMinifyView(
    language: 'XML',
    beautify: _beautifyXml,
    minify: _minifyXml,
    showComments: true,
  );
}
