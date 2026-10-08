import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/tool_harness.dart';

/// Runs [body] against a fresh harness with [toolId] already open.
void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body,
) {
  testWidgets(description, (tester) async {
    final h = ToolHarness(tester);
    await h.open(toolId);
    await body(h);
  });
}

void main() {
  group('Base64 String Encode/Decode', () {
    const tool = 'base64_string_encode_decode';
    // Placeholders flip with the direction toggle:
    // Encode: input 'Hello from DevUtils' → output 'SGVsbG8='
    // Decode: input 'SGVsbG8=' → output 'Hello'

    toolTest('encodes ASCII text', tool, (h) async {
      await h.tap('Encode');
      await h.enter('Hello from DevUtils', text: 'Hello, DevUtils!');
      expect(h.text('SGVsbG8='), 'SGVsbG8sIERldlV0aWxzIQ==');
    });

    toolTest('decodes base64 back to text', tool, (h) async {
      await h.enter('SGVsbG8=', text: 'SGVsbG8sIERldlV0aWxzIQ==');
      expect(h.text('Hello'), 'Hello, DevUtils!');
    });

    toolTest('roundtrips unicode through encode then decode', tool, (h) async {
      await h.tap('Encode');
      await h.enter('Hello from DevUtils', text: 'héllo wörld — ünïcode ✓');
      final encoded = h.text('SGVsbG8=');
      expect(encoded, isNot(contains('héllo')));
      expect(utf8.decode(base64Decode(encoded)), 'héllo wörld — ünïcode ✓');

      await h.tap('Decode');
      await h.enter('SGVsbG8=', text: encoded);
      expect(h.text('Hello'), 'héllo wörld — ünïcode ✓');
    });

    toolTest('decodes base64 without trailing padding', tool, (h) async {
      await h.enter('SGVsbG8=', text: 'SGVsbG8');
      expect(h.text('Hello'), 'Hello');
    });

    toolTest('invalid base64 leaves output empty and reports an error', tool, (
      h,
    ) async {
      await h.enter('SGVsbG8=', text: 'not!valid@base64');
      expect(h.text('Hello'), isEmpty);
      expect(find.textContaining('FormatException'), findsOneWidget);
    });

    toolTest('empty input clears output', tool, (h) async {
      await h.enter('SGVsbG8=', text: 'SGVsbG8sIERldlV0aWxzIQ==');
      await h.enter('SGVsbG8=', text: '');
      expect(h.text('Hello'), '');
    });

    toolTest('use as input feeds output back through the pipeline', tool, (
      h,
    ) async {
      await h.tap('Encode');
      await h.enter('Hello from DevUtils', text: 'roundtrip');
      await h.tap('Use as input');
      expect(h.text('Hello from DevUtils'), 'cm91bmR0cmlw');
    });
  });

  group('URL Encode/Decode', () {
    const tool = 'url_encode_decode';
    // Encode: input r'abc 0123 !@#$' → output 'abc%200123'
    // Decode: input 'abc%200123' → output 'abc 0123'

    toolTest('encodes spaces and reserved characters', tool, (h) async {
      await h.enter(r'abc 0123 !@#$', text: 'hello world & more?');
      expect(h.text('abc%200123'), 'hello%20world%20%26%20more%3F');
    });

    toolTest('leaves unreserved characters untouched', tool, (h) async {
      await h.enter(r'abc 0123 !@#$', text: 'abc-1.2~_zz');
      expect(h.text('abc%200123'), 'abc-1.2~_zz');
    });

    toolTest('encodes unicode as UTF-8 percent escapes', tool, (h) async {
      await h.enter(r'abc 0123 !@#$', text: 'é');
      expect(h.text('abc%200123'), '%C3%A9');
    });

    toolTest('decodes percent escapes', tool, (h) async {
      await h.tap('Decode');
      await h.enter('abc%200123', text: 'a%20b%2Fc%3Fd');
      expect(h.text('abc 0123'), 'a b/c?d');
    });

    toolTest('decodes plus as literal plus (not space)', tool, (h) async {
      await h.tap('Decode');
      await h.enter('abc%200123', text: 'a+b');
      expect(h.text('abc 0123'), 'a+b');
    });

    toolTest('invalid escape surfaces an error', tool, (h) async {
      await h.tap('Decode');
      await h.enter('abc%200123', text: '%ZZ');
      expect(h.text('abc 0123'), isEmpty);
      expect(find.textContaining('Invalid URL encoding'), findsOneWidget);
    });
  });

  group('HTML Entity Encode/Decode', () {
    const tool = 'html_entity_encode_decode';

    toolTest('encodes the five XML-critical characters', tool, (h) async {
      await h.enter('<h1>Hello</h1>', text: '<h1 class="a">Hi & \'bye\'</h1>');
      expect(
        h.text('&lt;h1&gt;Hello&lt;/h1&gt;'),
        '&lt;h1 class=&quot;a&quot;&gt;Hi &amp; &#39;bye&#39;&lt;/h1&gt;',
      );
    });

    toolTest('decodes named entities', tool, (h) async {
      await h.tap('Decode');
      await h.enter('<h1>Hello</h1>', text: '&lt;div&gt;&amp;&quot;&apos;');
      expect(h.text('&lt;h1&gt;Hello&lt;/h1&gt;'), '<div>&"\'');
    });

    toolTest('decodes decimal and hex numeric entities', tool, (h) async {
      await h.tap('Decode');
      await h.enter('<h1>Hello</h1>', text: '&#65;&#x42;&#X43;');
      expect(h.text('&lt;h1&gt;Hello&lt;/h1&gt;'), 'ABC');
    });

    toolTest('leaves unknown entities untouched', tool, (h) async {
      await h.tap('Decode');
      await h.enter('<h1>Hello</h1>', text: '&nosuchentity; &amp;');
      expect(h.text('&lt;h1&gt;Hello&lt;/h1&gt;'), '&nosuchentity; &');
    });

    toolTest('roundtrips through encode and decode', tool, (h) async {
      const original = '<p>"Quotes" & \'apostrophes\'</p>';
      await h.enter('<h1>Hello</h1>', text: original);
      final encoded = h.text('&lt;h1&gt;Hello&lt;/h1&gt;');
      await h.tap('Decode');
      await h.enter('<h1>Hello</h1>', text: encoded);
      expect(h.text('&lt;h1&gt;Hello&lt;/h1&gt;'), original);
    });
  });

  group('Backslash Escape/Unescape', () {
    const tool = 'backslash_escape_unescape';
    // Input hint is the literal `Line 1\nLine 2`; output hint is the same
    // text with a real newline.
    const inputHint = 'Line 1\\nLine 2';
    const outputHint = 'Line 1\nLine 2';

    toolTest('escapes newlines, tabs, quotes, backslashes', tool, (h) async {
      await h.tap('Escape');
      await h.enter(inputHint, text: 'a\nb\tc"d\\e');
      expect(h.text(outputHint), r'a\nb\tc\"d\\e');
    });

    toolTest('unescapes standard C-style escapes', tool, (h) async {
      await h.enter(inputHint, text: r'a\nb\tc\"d\\e');
      expect(h.text(outputHint), 'a\nb\tc"d\\e');
    });

    toolTest('escape then unescape is the identity', tool, (h) async {
      await h.tap('Escape');
      const original = 'line\nbreak\ttab"quote\\slash';
      await h.enter(inputHint, text: original);
      final escaped = h.text(outputHint);
      await h.tap('Unescape');
      await h.enter(inputHint, text: escaped);
      expect(h.text(outputHint), original);
    });
  });

  group('Base64 Image Encode/Decode', () {
    const tool = 'base64_image_encode_decode';

    Uint8List minimalPng() => Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
          0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
          0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00,
        ]);

    toolTest('reports byte count for valid base64 image data', tool, (
      h,
    ) async {
      final b64 = base64Encode(minimalPng());
      await h.enter('', label: 'String', text: b64);
      expect(find.text('${minimalPng().length} bytes'), findsOneWidget);
    });

    toolTest('accepts a data URL prefix', tool, (h) async {
      final b64 = 'data:image/png;base64,${base64Encode(minimalPng())}';
      await h.enter('', label: 'String', text: b64);
      expect(find.text('${minimalPng().length} bytes'), findsOneWidget);
    });

    toolTest('flags invalid image data', tool, (h) async {
      await h.enter('', label: 'String', text: '!!!not base64!!!');
      expect(find.text('Invalid image data'), findsOneWidget);
    });

    toolTest('empty input resets the preview', tool, (h) async {
      await h.enter('', label: 'String', text: base64Encode(minimalPng()));
      await h.enter('', label: 'String', text: '');
      expect(find.text('Image preview (base64 only)'), findsOneWidget);
    });
  });
}
