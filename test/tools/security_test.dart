import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crypto/crypto.dart' as crypto;

import 'package:dev_tool/ui/tools/common/shared.dart';

import '../helpers/tool_harness.dart';

void toolTest(
  String description,
  String toolId,
  Future<void> Function(ToolHarness h) body, {
  Size? surface,
}) {
  testWidgets(description, (tester) async {
    final h = ToolHarness(tester);
    await h.open(toolId, surface: surface);
    await body(h);
  });
}

Future<void> setInlineField(
  WidgetTester tester,
  String hint,
  String text,
) async {
  final field = tester.widget<InlineTextField>(
    find.byWidgetPredicate((w) => w is InlineTextField && w.hintText == hint),
  );
  field.controller!.text = text;
  field.onChanged?.call(text);
  await tester.pump(const Duration(milliseconds: 200));
}

/// Drags every [ListView] until [finder] is built and visible (lazy lists
/// only build the visible viewport, so the target may not exist yet).
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  final listViews = find.byType(ListView).evaluate().toList();
  for (final element in listViews) {
    for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
      final scrollable = find
          .descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollable, const Offset(0, -160));
      await tester.pump(const Duration(milliseconds: 120));
    }
    if (finder.evaluate().isNotEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 200));
}

/// Sets a plain [TextField] (not an InlineTextField) found by hint text.
Future<void> setPlainField(
  WidgetTester tester,
  String hint,
  String text,
) async {
  final field = tester.widget<TextField>(
    find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    ),
  );
  field.controller!.text = text;
  field.onChanged?.call(text);
  await tester.pump(const Duration(milliseconds: 200));
}

String b64url(String input) =>
    base64Url.encode(utf8.encode(input)).replaceAll('=', '');

void main() {
  group('JWT Debugger', () {
    const tool = 'jwt_debugger';

    String makeJwt(String secret) {
      final head = b64url('{"alg":"HS256","typ":"JWT"}');
      final payload = b64url('{"sub":"1234567890"}');
      final input = '$head.$payload';
      final digest = crypto.Hmac(
        crypto.sha256,
        utf8.encode(secret),
      ).convert(utf8.encode(input)).bytes;
      final sig = base64Url.encode(digest).replaceAll('=', '');
      return '$input.$sig';
    }

    toolTest('decodes header and payload', tool, (h) async {
      await h.enter('Paste JWT here...', text: makeJwt('your-secret'));
      expect(h.text('{ "typ": "JWT", "alg": "HS256" }'), contains('"HS256"'));
      expect(h.text('{ "sub": "1234567890" }'), contains('"1234567890"'));
    }, surface: const Size(1500, 1600));

    toolTest('verifies a valid HS256 signature', tool, (h) async {
      await scrollTo(
        h.tester,
        find.byWidgetPredicate(
          (w) => w is InlineTextField && w.hintText == 'your-secret',
        ),
      );
      await setInlineField(h.tester, 'your-secret', 'your-secret');
      await h.enter('Paste JWT here...', text: makeJwt('your-secret'));
      expect(find.text('Signature Verified'), findsOneWidget);
    }, surface: const Size(1500, 1600));

    toolTest('flags a mismatched signature', tool, (h) async {
      await scrollTo(
        h.tester,
        find.byWidgetPredicate(
          (w) => w is InlineTextField && w.hintText == 'your-secret',
        ),
      );
      await setInlineField(h.tester, 'your-secret', 'wrong-secret');
      await h.enter('Paste JWT here...', text: makeJwt('your-secret'));
      expect(find.text('Signature Mismatch'), findsOneWidget);
    }, surface: const Size(1500, 1600));

    toolTest('malformed token surfaces an error', tool, (h) async {
      await h.enter('Paste JWT here...', text: 'garbage');
      await scrollTo(h.tester, find.textContaining('Invalid JWT format'));
      expect(find.text('Invalid JWT format.'), findsOneWidget);
    }, surface: const Size(1500, 1600));
  });

  group('Auth TOTP', () {
    const tool = 'auth_totp';

    toolTest('adding a token shows two rotating 6-digit codes', tool, (
      h,
    ) async {
      await h.tester.tap(find.byIcon(Icons.add).first);
      await h.settle();
      await setInlineField(h.tester, 'Paste or enter secret', 'JBSWY3DPEHPK3PXP');
      await setInlineField(h.tester, 'Optional label', 'Test');
      await h.tap('Add');
      final codes = h.tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => RegExp(r'^\d{6}$').hasMatch(s))
          .toList();
      expect(codes, hasLength(2));
      expect(codes[0], isNot(codes[1]));
    }, surface: const Size(1500, 1600));

    toolTest('invalid base32 secret shows a placeholder code', tool, (h) async {
      await h.tester.tap(find.byIcon(Icons.add).first);
      await h.settle();
      await setInlineField(h.tester, 'Paste or enter secret', '!!!!1!!!!');
      await h.tap('Add');
      expect(find.text('------'), findsWidgets);
    }, surface: const Size(1500, 1600));
  });

  group('Hash Generator', () {
    const tool = 'hash_generator';

    toolTest('computes standard digests for ASCII input', tool, (h) async {
      await h.enter('Enter text to hash...', text: 'abc');
      expect(
        find.text('900150983CD24FB0D6963F7D28E17F72'),
        findsOneWidget,
      ); // MD5
      expect(
        find.text('A9993E364706816ABA3E25717850C26C9CD0D89D'),
        findsOneWidget,
      ); // SHA-1
      expect(
        find.text(
          'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD',
        ),
        findsOneWidget,
      ); // SHA-256
    });

    toolTest('digests change with input', tool, (h) async {
      await h.enter('Enter text to hash...', text: 'abc');
      await h.enter('Enter text to hash...', text: 'abd');
      expect(find.text('900150983CD24FB0D6963F7D28E17F72'), findsNothing);
    });

    toolTest('empty input clears digests', tool, (h) async {
      await h.enter('Enter text to hash...', text: 'abc');
      await h.enter('Enter text to hash...', text: '');
      expect(find.text('900150983CD24FB0D6963F7D28E17F72'), findsNothing);
    });
  });

  group('Certificate Decoder (X.509)', () {
    const tool = 'certificate_decoder_x509';
    const pem = '''-----BEGIN CERTIFICATE-----
MIIB7DCCAZOgAwIBAgIUXz0eZsNS2P7FbZ0PzYs/goWMXTIwCgYIKoZIzj0EAwIw
ODEWMBQGA1UEAwwNRGV2VXRpbHMgRGVtbzERMA8GA1UECgwIRGV2VXRpbHMxCzAJ
BgNVBAYTAlVTMB4XDTI2MTAwODEwNDUxM1oXDTM2MTAwNTEwNDUxM1owODEWMBQG
A1UEAwwNRGV2VXRpbHMgRGVtbzERMA8GA1UECgwIRGV2VXRpbHMxCzAJBgNVBAYT
AlVTMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEaNiU5wrEOh/LS0sV04TNzKJA
Scar+ts5fPV3XIopvvklHyBbsQrn2g/sYTKdMgYRaG31a67lapoVy+k0dwhd6qN7
MHkwHQYDVR0OBBYEFC2hlqwJzlOPtDqMVQUBvcGhySjgMB8GA1UdIwQYMBaAFC2h
lqwJzlOPtDqMVQUBvcGhySjgMA8GA1UdEwEB/wQFMAMBAf8wJgYDVR0RBB8wHYIO
ZGV2dXRpbHMubG9jYWyCC2V4YW1wbGUuY29tMAoGCCqGSM49BAMCA0cAMEQCIDI+
K06p2IAFqR1XJi2JV8yPBGgKKEG4U2VjHuGL8FlYAiBVYwDaOdrvC8r9EuF0o0m5
OPB4kKiuf2pbeafouebiHg==
-----END CERTIFICATE-----''';

    toolTest('decodes subject, issuer and validity', tool, (h) async {
      await h.enter(
        'Paste a PEM certificate (-----BEGIN CERTIFICATE-----)...',
        text: pem,
      );
      final out = h.text('Decoded certificate details...');
      expect(out, contains('DevUtils Demo'));
      expect(out, contains('DevUtils'));
      expect(out, contains('US'));
    });

    toolTest('non-PEM input surfaces an error', tool, (h) async {
      await h.enter(
        'Paste a PEM certificate (-----BEGIN CERTIFICATE-----)...',
        text: 'hello world',
      );
      expect(
        h.text('Decoded certificate details...'),
        contains(RegExp('Invalid|Unable|not', caseSensitive: false)),
      );
    });
  });

  group('Text Encryption/Decryption', () {
    const tool = 'text_encryption';

    toolTest('encrypt then decrypt roundtrips', tool, (h) async {
      await setPlainField(
        h.tester,
        'Enter password for encryption/decryption...',
        'correct horse',
      );
      await h.enter('Enter text to encrypt...', text: 'top secret payload');
      final cipher = h.text('Encrypted output appears here...');
      expect(cipher, isNotEmpty);
      expect(cipher, isNot(contains('top secret')));

      // Swap & toggle mode moves the cipher into the input.
      await h.tester.tap(find.byTooltip('Swap & toggle mode'));
      await h.settle();
      expect(h.text('Enter ciphertext to decrypt...'), cipher);
      expect(h.text('Decrypted output appears here...'), 'top secret payload');
    }, surface: const Size(1500, 1600));

    toolTest('wrong password fails to decrypt', tool, (h) async {
      await setPlainField(
        h.tester,
        'Enter password for encryption/decryption...',
        'correct horse',
      );
      await h.enter('Enter text to encrypt...', text: 'top secret payload');
      final cipher = h.text('Encrypted output appears here...');
      await h.tester.tap(find.byTooltip('Swap & toggle mode'));
      await h.settle();
      await setPlainField(
        h.tester,
        'Enter password for encryption/decryption...',
        'wrong password',
      );
      await h.enter('Enter ciphertext to decrypt...', text: cipher);
      expect(
        find.textContaining(RegExp('wrong|fail|error', caseSensitive: false)),
        findsWidgets,
      );
    }, surface: const Size(1500, 1600));
  });

  group('User Agent Generator/Validator', () {
    const tool = 'user_agent_tool';

    toolTest('generates a plausible UA string', tool, (h) async {
      await h.tap('Generate');
      final ua = h.text('Paste or generate a user agent...');
      expect(ua, contains('Mozilla/5.0'));
      expect(h.text('Analysis appears here...'), isNotEmpty);
    });

    toolTest('validates a Chrome UA', tool, (h) async {
      await h.enter(
        'Paste or generate a user agent...',
        text:
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      final out = h.text('Analysis appears here...');
      expect(out.toLowerCase(), contains('chrome'));
    });
  });

  group('AntiBot Detection', () {
    const tool = 'antibot_detection';

    toolTest('renders the target field and results pane', tool, (h) async {
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'https://example.com',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Detection results appear here...'),
        findsOneWidget,
      );
    });
  });
}
