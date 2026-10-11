import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dev_tool/ui/widgets.dart';

import 'functionality_audit_test.dart' as audit;
import 'generation_regression_audit_test.dart' as harness;
import 'output_contract_audit_test.dart' as contract;

const algorithms = {
  'Modern': [
    'AES-128-ECB',
    'AES-128-CBC',
    'AES-128-CFB',
    'AES-128-OFB',
    'AES-128-CTR',
    'AES-192-ECB',
    'AES-192-CBC',
    'AES-192-CFB',
    'AES-192-OFB',
    'AES-192-CTR',
    'AES-256-ECB',
    'AES-256-CBC',
    'AES-256-CFB',
    'AES-256-OFB',
    'AES-256-CTR',
    'ChaCha20',
    'Salsa20',
  ],
  'Legacy': ['3DES-CBC', '3DES-ECB', 'RC2-CBC', 'RC2-ECB'],
  'Stream': ['RC4'],
  'Lightweight': ['TEA', 'XTEA'],
  'Classical': ['XOR', 'Vigenere', 'Caesar', 'ROT13', 'Atbash'],
};

void main() {
  for (final category in algorithms.entries) {
    for (final algorithm in category.value) {
      for (final format in ['Base64', 'Hex']) {
        testWidgets('encryption roundtrip: $algorithm $format', (tester) async {
          await harness.open(tester, 'text_encryption');
          tester
              .widgetList<SmallDropdown>(find.byType(SmallDropdown))
              .first
              .onChanged!(category.key);
          await audit.settle(tester);
          tester
              .widgetList<SmallDropdown>(find.byType(SmallDropdown))
              .elementAt(1)
              .onChanged!(algorithm);
          await audit.settle(tester);
          final key = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText ==
                    'Enter password for encryption/decryption...',
          );
          await tester.enterText(key, algorithm == 'Caesar' ? '7' : 'KEY');
          await contract.segment(tester, format);
          await contract.segment(tester, 'Encrypt');
          final original = category.key == 'Classical'
              ? 'HELLO WORLD THIS MESSAGE CROSSES MULTIPLE BLOCK BOUNDARIES'
              : '  é漢字🙂 This message crosses several block boundaries.\nWhitespace stays.  ';
          await contract.enter(tester, original);
          final encrypted = contract.output(tester);
          // ignore: avoid_print
          print(
            'ENCRYPTION_AUDIT ${jsonEncode({'algorithm': algorithm, 'format': format, 'input': original, 'outputLength': encrypted.length, 'messages': tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').where((s) => s.startsWith('Error:')).toList()})}',
          );
          expect(encrypted, isNotEmpty, reason: '$algorithm encryption');
          expect(encrypted, isNot(original));
          if (algorithm.startsWith('AES') || algorithm == 'ChaCha20') {
            final reference = await tester.runAsync(() => Process.run('node', [
              '-e',
              r'''const crypto=require('node:crypto');
const [algorithm,format,payload,password]=process.argv.slice(1);
const data=Buffer.from(payload,format==='Hex'?'hex':'base64');
const keyHash=crypto.createHash('sha256').update(password).digest();
let name,key,iv,body;
if(algorithm==='ChaCha20') {
  name='chacha20'; key=keyHash;
  iv=Buffer.concat([Buffer.alloc(4),data.subarray(0,12)]); body=data.subarray(12);
} else {
  name=algorithm.toLowerCase(); key=keyHash.subarray(0,Number(algorithm.split('-')[1])/8);
  const ecb=algorithm.endsWith('ECB'); iv=ecb?null:data.subarray(0,16); body=ecb?data:data.subarray(16);
}
const cipher=crypto.createDecipheriv(name,key,iv);
process.stdout.write(Buffer.concat([cipher.update(body),cipher.final()]).toString('utf8'));''',
              algorithm, format, encrypted, 'KEY',
            ]));
            expect(reference!.exitCode, 0, reason: reference.stderr.toString());
            expect(reference.stdout, original, reason: '$algorithm independent Node/OpenSSL decryption');
          }

          await contract.segment(tester, 'Decrypt');
          await contract.enter(tester, encrypted);
          expect(
            contract.output(tester),
            original,
            reason: '$algorithm $format decrypt',
          );
          await contract.enter(tester, '');
          expect(contract.output(tester), isEmpty);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
