import 'package:xml/xml.dart';

/// XML formatting changes indentation, not text, CDATA, or xml:space content.
class XmlFormatService {
  static String process(
    String source, {
    required bool pretty,
    String indent = '  ',
    bool keepComments = true,
  }) {
    if (source.trim().isEmpty) return '';
    final document = XmlDocument.parse(source);
    bool preserve(XmlNode node) {
      for (final ancestor in [node, ...node.ancestors]) {
        if (ancestor is XmlElement) {
          final space = ancestor.getAttribute('xml:space');
          if (space != null) return space == 'preserve';
        }
      }
      return false;
    }

    bool textContent(XmlNode node) => node.children.any(
      (child) =>
          child is XmlCDATA ||
          (child is XmlText && child.value.trim().isNotEmpty),
    );
    void clean(XmlNode node) {
      if (node.children.isEmpty) return;
      if (!preserve(node) && !textContent(node)) {
        node.children.removeWhere(
          (child) =>
              child is XmlText &&
              child.value.trim().isEmpty &&
              child.value.contains('\n'),
        );
      }
      if (!keepComments) {
        node.children.removeWhere((child) => child is XmlComment);
      }
      for (final child in node.children.toList()) {
        clean(child);
      }
    }

    clean(document);
    return document.toXmlString(
      pretty: pretty,
      indent: indent,
      preserveWhitespace: (node) =>
          preserve(node) ||
          node.children.any((child) => child is XmlText || child is XmlCDATA),
    );
  }
}
