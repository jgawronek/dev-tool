/// XML beautify/minify tool view.
library;

import 'package:flutter/material.dart';

import '../../../services/markup_format_service.dart';
import '../common/shared.dart';

String _beautifyXml(String source, String indent) =>
    XmlFormatService.process(source, pretty: true, indent: indent);

String _minifyXml(String source, bool keepComments) =>
    XmlFormatService.process(source, pretty: false, keepComments: keepComments);

Widget buildXmlBeautifyMinify() {
  return const MarkupBeautifyMinifyView(
    language: 'XML',
    beautify: _beautifyXml,
    minify: _minifyXml,
    showComments: true,
  );
}
