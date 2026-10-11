import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/registry/tool_registry.dart';

import '../helpers/tool_harness.dart';

/// Tools whose source requests a Copy button, and so must render one.
///
/// Guards the EditorPane fixes that stopped silently dropping it. Tools are
/// listed explicitly rather than derived so the list stays reviewable.
const _expectCopy = <String>[
  'base64_string_encode_decode',
  'base64_image_encode_decode',
  'base_encodings',
  'url_encode_decode',
  'backslash_escape_unescape',
  'html_entity_encode_decode',
  'hex_ascii_converter',
  'curl_to_code',
  'php_to_js',
  'json_to_code',
  'yaml_json_converter',
  'sql_formatter',
  'html_beautify_minify',
  'css_beautify_minify',
  'rb_beautify_minify',
  'js_beautify_minify',
  'xml_beautify_minify',
  'string_case_converter',
  'line_sort_dedupe',
  'text_diff_checker',
  'certificate_decoder_x509',
  'user_agent_tool',
  'antibot_detection',
  'cipher_decoder',
  'file_checksum',
  'password_hashing',
  'text_encryption',
  'subnet_calculator',
  'uuid_ulid_generate_decode',
  'compression_codecs',
  'php_serializer',
];

/// Tools whose source requests a paste button.
const _expectPaste = <String>[
  'base64_string_encode_decode',
  'url_encode_decode',
  'html_entity_encode_decode',
  'backslash_escape_unescape',
  'hex_ascii_converter',
  'curl_to_code',
  'yaml_json_converter',
  'sql_formatter',
  'string_case_converter',
  'line_sort_dedupe',
  'certificate_decoder_x509',
  'user_agent_tool',
  'cipher_decoder',
  'subnet_calculator',
  'compression_codecs',
];

void main() {
  group('tools that request Copy render it', () {
    for (final toolId in _expectCopy) {
      testWidgets(toolId, (tester) async {
        final h = ToolHarness(tester);
        await h.open(toolId, surface: const Size(1600, 1200));
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Icon && {Icons.copy, Icons.copy_outlined}.contains(w.icon),
          ),
          findsWidgets,
          reason: '$toolId requests a Copy action but renders none',
        );
      });
    }
  });

  group('tools have no paste icons', () {
    for (final toolId in _expectPaste) {
      testWidgets(toolId, (tester) async {
        final h = ToolHarness(tester);
        await h.open(toolId, surface: const Size(1600, 1200));
        expect(
          find.byIcon(Icons.content_paste),
          findsNothing,
          reason: '$toolId must not show removed paste icons',
        );
      });
    }
  });

  group('registry stays consistent', () {
    test('every listed tool id exists', () {
      for (final id in {..._expectCopy, ..._expectPaste}) {
        expect(ToolRegistry.byId(id), isNotNull, reason: 'no such tool: $id');
      }
    });

    test('tool ids are unique', () {
      final ids = ToolRegistry.tools.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
