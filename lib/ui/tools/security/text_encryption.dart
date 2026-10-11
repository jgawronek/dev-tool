/// Text encryption/decryption tool view.
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/block/modes/cfb.dart';
import 'package:pointycastle/block/modes/ofb.dart';
import 'package:pointycastle/stream/ctr.dart';
import 'package:pointycastle/stream/salsa20.dart';
import 'package:pointycastle/stream/chacha7539.dart';
import 'package:pointycastle/stream/rc4_engine.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/block/rc2_engine.dart';
import 'package:pointycastle/api.dart' as pc;
import '../../../ui/app_colors.dart';
import '../../../ui/widgets.dart';
import '../common/shared.dart';
import '../common/editors.dart';
import '../../tool_sample_action.dart';

class _TextEncryptionView extends StatefulWidget {
  const _TextEncryptionView();

  @override
  State<_TextEncryptionView> createState() => _TextEncryptionViewState();
}

class _TextEncryptionViewState extends State<_TextEncryptionView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  final TextEditingController _key = TextEditingController();

  String _category = 'Modern';
  String _algorithm = 'AES-256-CBC';
  String _mode = 'Encrypt';
  String _outputFormat = 'Base64';
  String? _error;

  static const _categories = [
    'Modern',
    'Legacy',
    'Stream',
    'Lightweight',
    'Classical',
  ];

  static const _algorithmsByCategory = {
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

  List<String> get _algorithms => _algorithmsByCategory[_category] ?? [];

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    _key.dispose();
    super.dispose();
  }

  void _process() {
    final inputText = _input.text;
    final keyText = _key.text;

    if (inputText.isEmpty) {
      setState(() {
        _output.clear();
        _error = null;
      });
      return;
    }

    if (keyText.isEmpty) {
      setState(() {
        _output.clear();
        _error = 'Please enter a password/key';
      });
      return;
    }

    try {
      String result;
      if (_mode == 'Encrypt') {
        result = _encrypt(inputText, keyText);
      } else {
        result = _decrypt(inputText, keyText);
      }
      setState(() {
        _output.text = result;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _output.clear();
        _error = 'Error: ${e.toString()}';
      });
    }
  }

  String _encrypt(String plaintext, String password) {
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));

    // Classical ciphers - text-based, no binary output
    if (_category == 'Classical') {
      return _encryptClassical(plaintext, password);
    }

    Uint8List result;

    if (_algorithm.startsWith('AES')) {
      result = _encryptAES(plaintextBytes, password);
    } else if (_algorithm == 'ChaCha20') {
      result = _encryptChaCha20(plaintextBytes, password);
    } else if (_algorithm == 'Salsa20') {
      result = _encryptSalsa20(plaintextBytes, password);
    } else if (_algorithm.startsWith('3DES')) {
      result = _encrypt3DES(plaintextBytes, password);
    } else if (_algorithm.startsWith('RC2')) {
      result = _encryptRC2(plaintextBytes, password);
    } else if (_algorithm == 'RC4') {
      result = _encryptRC4(plaintextBytes, password);
    } else if (_algorithm == 'TEA') {
      result = _encryptTEA(plaintextBytes, password);
    } else if (_algorithm == 'XTEA') {
      result = _encryptXTEA(plaintextBytes, password);
    } else {
      throw Exception('Unknown algorithm: $_algorithm');
    }

    return _outputFormat == 'Base64'
        ? base64Encode(result)
        : bytesToHex(result);
  }

  String _encryptClassical(String plaintext, String key) {
    switch (_algorithm) {
      case 'XOR':
        final keyBytes = utf8.encode(key);
        final textBytes = utf8.encode(plaintext);
        final result = Uint8List(textBytes.length);
        for (var i = 0; i < textBytes.length; i++) {
          result[i] = textBytes[i] ^ keyBytes[i % keyBytes.length];
        }
        return _outputFormat == 'Base64'
            ? base64Encode(result)
            : bytesToHex(result);
      case 'Vigenere':
        return _vigenereEncrypt(plaintext, key);
      case 'Caesar':
        final shift = int.tryParse(key) ?? 3;
        return _caesarEncrypt(plaintext, shift);
      case 'ROT13':
        return _caesarEncrypt(plaintext, 13);
      case 'Atbash':
        return _atbashCipher(plaintext);
      default:
        throw Exception('Unknown classical cipher');
    }
  }

  Uint8List _encryptAES(Uint8List plaintext, String password) {
    final keySize = _algorithm.contains('128')
        ? 16
        : _algorithm.contains('192')
        ? 24
        : 32;
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, keySize));
    final iv = _generateIV(16);

    final mode = _algorithm.split('-').last;
    Uint8List ciphertext;

    switch (mode) {
      case 'ECB':
        ciphertext = _aesEcbEncrypt(_pkcs7Pad(plaintext, 16), key);
        return ciphertext; // No IV for ECB
      case 'CBC':
        ciphertext = _aesCbcEncrypt(_pkcs7Pad(plaintext, 16), key, iv);
        break;
      case 'CFB':
        ciphertext = _aesCfbEncrypt(plaintext, key, iv);
        break;
      case 'OFB':
        ciphertext = _aesOfbEncrypt(plaintext, key, iv);
        break;
      case 'CTR':
        ciphertext = _aesCtrEncrypt(plaintext, key, iv);
        break;
      default:
        throw Exception('Unknown AES mode: $mode');
    }

    return _combineIvAndCiphertext(iv, ciphertext);
  }

  Uint8List _encryptChaCha20(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = _generateIV(12);

    final cipher = ChaCha7539Engine()
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    final ciphertext = cipher.process(plaintext);

    return _combineIvAndCiphertext(nonce, ciphertext);
  }

  Uint8List _encryptSalsa20(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = _generateIV(8);

    final cipher = Salsa20Engine()
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    final ciphertext = cipher.process(plaintext);

    return _combineIvAndCiphertext(nonce, ciphertext);
  }

  Uint8List _encrypt3DES(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 24));
    final padded = _pkcs7Pad(plaintext, 8);

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(DESedeEngine())
        ..init(true, pc.KeyParameter(key));
      return _processBlocks(cipher, padded, 8);
    } else {
      final iv = _generateIV(8);
      final cipher = CBCBlockCipher(DESedeEngine())
        ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _combineIvAndCiphertext(iv, _processBlocks(cipher, padded, 8));
    }
  }

  Uint8List _encryptRC2(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final padded = _pkcs7Pad(plaintext, 8);

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(RC2Engine())
        ..init(true, pc.KeyParameter(key));
      return _processBlocks(cipher, padded, 8);
    } else {
      final iv = _generateIV(8);
      final cipher = CBCBlockCipher(RC2Engine())
        ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _combineIvAndCiphertext(iv, _processBlocks(cipher, padded, 8));
    }
  }

  Uint8List _encryptRC4(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final cipher = RC4Engine()..init(true, pc.KeyParameter(key));
    return cipher.process(plaintext);
  }

  Uint8List _encryptTEA(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final padded = _pkcs7Pad(plaintext, 8);
    return _teaEncrypt(padded, key);
  }

  Uint8List _encryptXTEA(Uint8List plaintext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final padded = _pkcs7Pad(plaintext, 8);
    return _xteaEncrypt(padded, key);
  }

  String _decrypt(String ciphertextStr, String password) {
    // Classical ciphers
    if (_category == 'Classical') {
      return _decryptClassical(ciphertextStr, password);
    }

    Uint8List combined;
    try {
      combined = _outputFormat == 'Base64'
          ? Uint8List.fromList(base64Decode(ciphertextStr.trim()))
          : _hexToBytes(ciphertextStr.trim());
    } catch (e) {
      throw Exception('Invalid $_outputFormat input');
    }

    Uint8List plaintext;

    if (_algorithm.startsWith('AES')) {
      plaintext = _decryptAES(combined, password);
    } else if (_algorithm == 'ChaCha20') {
      plaintext = _decryptChaCha20(combined, password);
    } else if (_algorithm == 'Salsa20') {
      plaintext = _decryptSalsa20(combined, password);
    } else if (_algorithm.startsWith('3DES')) {
      plaintext = _decrypt3DES(combined, password);
    } else if (_algorithm.startsWith('RC2')) {
      plaintext = _decryptRC2(combined, password);
    } else if (_algorithm == 'RC4') {
      plaintext = _decryptRC4(combined, password);
    } else if (_algorithm == 'TEA') {
      plaintext = _decryptTEA(combined, password);
    } else if (_algorithm == 'XTEA') {
      plaintext = _decryptXTEA(combined, password);
    } else {
      throw Exception('Unknown algorithm: $_algorithm');
    }

    return utf8.decode(plaintext);
  }

  String _decryptClassical(String ciphertext, String key) {
    switch (_algorithm) {
      case 'XOR':
        final keyBytes = utf8.encode(key);
        final ciphertextBytes = _outputFormat == 'Base64'
            ? base64Decode(ciphertext)
            : _hexToBytes(ciphertext);
        final result = Uint8List(ciphertextBytes.length);
        for (var i = 0; i < ciphertextBytes.length; i++) {
          result[i] = ciphertextBytes[i] ^ keyBytes[i % keyBytes.length];
        }
        return utf8.decode(result);
      case 'Vigenere':
        return _vigenereDecrypt(ciphertext, key);
      case 'Caesar':
        final shift = int.tryParse(key) ?? 3;
        return _caesarDecrypt(ciphertext, shift);
      case 'ROT13':
        return _caesarEncrypt(ciphertext, 13); // ROT13 is symmetric
      case 'Atbash':
        return _atbashCipher(ciphertext); // Atbash is symmetric
      default:
        throw Exception('Unknown classical cipher');
    }
  }

  Uint8List _decryptAES(Uint8List combined, String password) {
    final keySize = _algorithm.contains('128')
        ? 16
        : _algorithm.contains('192')
        ? 24
        : 32;
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, keySize));

    final mode = _algorithm.split('-').last;
    Uint8List ciphertext;
    Uint8List iv;

    if (mode == 'ECB') {
      ciphertext = combined;
      return _pkcs7Unpad(_aesEcbDecrypt(ciphertext, key));
    }

    if (combined.length < 17) throw Exception('Ciphertext too short');
    iv = Uint8List.fromList(combined.sublist(0, 16));
    ciphertext = Uint8List.fromList(combined.sublist(16));

    switch (mode) {
      case 'CBC':
        return _pkcs7Unpad(_aesCbcDecrypt(ciphertext, key, iv));
      case 'CFB':
        return _aesCfbDecrypt(ciphertext, key, iv);
      case 'OFB':
        return _aesOfbDecrypt(ciphertext, key, iv);
      case 'CTR':
        return _aesCtrDecrypt(ciphertext, key, iv);
      default:
        throw Exception('Unknown AES mode: $mode');
    }
  }

  Uint8List _decryptChaCha20(Uint8List combined, String password) {
    if (combined.length < 13) throw Exception('Ciphertext too short');
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = Uint8List.fromList(combined.sublist(0, 12));
    final ciphertext = Uint8List.fromList(combined.sublist(12));

    final cipher = ChaCha7539Engine()
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    return cipher.process(ciphertext);
  }

  Uint8List _decryptSalsa20(Uint8List combined, String password) {
    if (combined.length < 9) throw Exception('Ciphertext too short');
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 32));
    final nonce = Uint8List.fromList(combined.sublist(0, 8));
    final ciphertext = Uint8List.fromList(combined.sublist(8));

    final cipher = Salsa20Engine()
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    return cipher.process(ciphertext);
  }

  Uint8List _decrypt3DES(Uint8List combined, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 24));

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(DESedeEngine())
        ..init(false, pc.KeyParameter(key));
      return _pkcs7Unpad(_processBlocks(cipher, combined, 8));
    } else {
      if (combined.length < 9) throw Exception('Ciphertext too short');
      final iv = Uint8List.fromList(combined.sublist(0, 8));
      final ciphertext = Uint8List.fromList(combined.sublist(8));
      final cipher = CBCBlockCipher(DESedeEngine())
        ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _pkcs7Unpad(_processBlocks(cipher, ciphertext, 8));
    }
  }

  Uint8List _decryptRC2(Uint8List combined, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));

    if (_algorithm.contains('ECB')) {
      final cipher = ECBBlockCipher(RC2Engine())
        ..init(false, pc.KeyParameter(key));
      return _pkcs7Unpad(_processBlocks(cipher, combined, 8));
    } else {
      if (combined.length < 9) throw Exception('Ciphertext too short');
      final iv = Uint8List.fromList(combined.sublist(0, 8));
      final ciphertext = Uint8List.fromList(combined.sublist(8));
      final cipher = CBCBlockCipher(RC2Engine())
        ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
      return _pkcs7Unpad(_processBlocks(cipher, ciphertext, 8));
    }
  }

  Uint8List _decryptRC4(Uint8List ciphertext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    final cipher = RC4Engine()..init(false, pc.KeyParameter(key));
    return cipher.process(ciphertext);
  }

  Uint8List _decryptTEA(Uint8List ciphertext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    return _pkcs7Unpad(_teaDecrypt(ciphertext, key));
  }

  Uint8List _decryptXTEA(Uint8List ciphertext, String password) {
    final keyHash = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(password)),
    );
    final key = Uint8List.fromList(keyHash.sublist(0, 16));
    return _pkcs7Unpad(_xteaDecrypt(ciphertext, key));
  }

  // ============ Helper Methods ============

  Uint8List _generateIV(int size) {
    final iv = Uint8List(size);
    final random = Random.secure();
    for (var i = 0; i < size; i++) {
      iv[i] = random.nextInt(256);
    }
    return iv;
  }

  Uint8List _combineIvAndCiphertext(Uint8List iv, Uint8List ciphertext) {
    final combined = Uint8List(iv.length + ciphertext.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, ciphertext);
    return combined;
  }

  Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padLength = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setRange(0, data.length, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLength;
    }
    return padded;
  }

  Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLength = data.last;
    if (padLength > 0 && padLength <= 16 && padLength <= data.length) {
      return Uint8List.fromList(data.sublist(0, data.length - padLength));
    }
    return data;
  }

  Uint8List _processBlocks(dynamic cipher, Uint8List data, int blockSize) {
    final output = Uint8List(data.length);
    for (var offset = 0; offset < data.length; offset += blockSize) {
      cipher.processBlock(data, offset, output, offset);
    }
    return output;
  }

  // ============ AES Modes ============

  Uint8List _aesEcbEncrypt(Uint8List plaintext, Uint8List key) {
    final cipher = ECBBlockCipher(AESEngine())
      ..init(true, pc.KeyParameter(key));
    return _processBlocks(cipher, plaintext, 16);
  }

  Uint8List _aesEcbDecrypt(Uint8List ciphertext, Uint8List key) {
    final cipher = ECBBlockCipher(AESEngine())
      ..init(false, pc.KeyParameter(key));
    return _processBlocks(cipher, ciphertext, 16);
  }

  Uint8List _aesCbcEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processBlocks(cipher, plaintext, 16);
  }

  Uint8List _aesCbcDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processBlocks(cipher, ciphertext, 16);
  }

  Uint8List _processPartialBlock(pc.BlockCipher cipher, Uint8List input) {
    final padded = Uint8List(((input.length + 15) ~/ 16) * 16)
      ..setRange(0, input.length, input);
    return Uint8List.fromList(_processBlocks(cipher, padded, 16).sublist(0, input.length));
  }

  Uint8List _aesCfbEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = CFBBlockCipher(AESEngine(), 16)
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processPartialBlock(cipher, plaintext);
  }

  Uint8List _aesCfbDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CFBBlockCipher(AESEngine(), 16)
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processPartialBlock(cipher, ciphertext);
  }

  Uint8List _aesOfbEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = OFBBlockCipher(AESEngine(), 16)
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processPartialBlock(cipher, plaintext);
  }

  Uint8List _aesOfbDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = OFBBlockCipher(AESEngine(), 16)
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return _processPartialBlock(cipher, ciphertext);
  }

  Uint8List _aesCtrEncrypt(Uint8List plaintext, Uint8List key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(plaintext);
  }

  Uint8List _aesCtrDecrypt(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    return cipher.process(ciphertext);
  }

  // ============ TEA / XTEA ============

  Uint8List _teaEncrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = 0;

      for (var j = 0; j < 32; j++) {
        sum = (sum + delta) & 0xFFFFFFFF;
        v0 =
            (v0 + ((((v1 << 4) + k[0]) ^ (v1 + sum)) ^ ((v1 >> 5) + k[1]))) &
            0xFFFFFFFF;
        v1 =
            (v1 + ((((v0 << 4) + k[2]) ^ (v0 + sum)) ^ ((v0 >> 5) + k[3]))) &
            0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  Uint8List _teaDecrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = (delta * 32) & 0xFFFFFFFF;

      for (var j = 0; j < 32; j++) {
        v1 =
            (v1 - ((((v0 << 4) + k[2]) ^ (v0 + sum)) ^ ((v0 >> 5) + k[3]))) &
            0xFFFFFFFF;
        v0 =
            (v0 - ((((v1 << 4) + k[0]) ^ (v1 + sum)) ^ ((v1 >> 5) + k[1]))) &
            0xFFFFFFFF;
        sum = (sum - delta) & 0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  Uint8List _xteaEncrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = 0;

      for (var j = 0; j < 32; j++) {
        v0 =
            (v0 + ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + k[sum & 3]))) &
            0xFFFFFFFF;
        sum = (sum + delta) & 0xFFFFFFFF;
        v1 =
            (v1 +
                ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + k[(sum >> 11) & 3]))) &
            0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  Uint8List _xteaDecrypt(Uint8List data, Uint8List key) {
    final k = _bytesToUint32List(key);
    final result = <int>[];
    const delta = 0x9E3779B9;

    for (var i = 0; i < data.length; i += 8) {
      var v0 = _bytesToUint32(data, i);
      var v1 = _bytesToUint32(data, i + 4);
      var sum = (delta * 32) & 0xFFFFFFFF;

      for (var j = 0; j < 32; j++) {
        v1 =
            (v1 -
                ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + k[(sum >> 11) & 3]))) &
            0xFFFFFFFF;
        sum = (sum - delta) & 0xFFFFFFFF;
        v0 =
            (v0 - ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + k[sum & 3]))) &
            0xFFFFFFFF;
      }

      result.addAll(_uint32ToBytes(v0));
      result.addAll(_uint32ToBytes(v1));
    }
    return Uint8List.fromList(result);
  }

  int _bytesToUint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  List<int> _bytesToUint32List(Uint8List bytes) {
    final result = <int>[];
    for (var i = 0; i < bytes.length; i += 4) {
      result.add(_bytesToUint32(bytes, i));
    }
    return result;
  }

  List<int> _uint32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  // ============ Classical Ciphers ============

  String _vigenereEncrypt(String plaintext, String key) {
    final keyUpper = key.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (keyUpper.isEmpty) return plaintext;

    final result = StringBuffer();
    var keyIndex = 0;

    for (final char in plaintext.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final charValue = char - base;
        final keyValue = keyUpper.codeUnitAt(keyIndex % keyUpper.length) - 65;
        final encrypted = (charValue + keyValue) % 26;
        result.writeCharCode(base + encrypted);
        keyIndex++;
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  String _vigenereDecrypt(String ciphertext, String key) {
    final keyUpper = key.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (keyUpper.isEmpty) return ciphertext;

    final result = StringBuffer();
    var keyIndex = 0;

    for (final char in ciphertext.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final charValue = char - base;
        final keyValue = keyUpper.codeUnitAt(keyIndex % keyUpper.length) - 65;
        final decrypted = (charValue - keyValue + 26) % 26;
        result.writeCharCode(base + decrypted);
        keyIndex++;
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  String _caesarEncrypt(String text, int shift) {
    final normalizedShift = ((shift % 26) + 26) % 26;
    final result = StringBuffer();

    for (final char in text.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final shifted = (char - base + normalizedShift) % 26;
        result.writeCharCode(base + shifted);
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  String _caesarDecrypt(String text, int shift) {
    return _caesarEncrypt(text, -shift);
  }

  String _atbashCipher(String text) {
    final result = StringBuffer();

    for (final char in text.runes) {
      final c = String.fromCharCode(char);
      if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final isUpper = c == c.toUpperCase();
        final base = isUpper ? 65 : 97;
        final mirrored = 25 - (char - base);
        result.writeCharCode(base + mirrored);
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }

  // ============ Utility ============

  Uint8List _hexToBytes(String hex) {
    hex = hex.replaceAll(' ', '').replaceAll('\n', '');
    if (hex.length % 2 != 0) throw Exception('Invalid hex length');
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  void _swapInputOutput() {
    final temp = _input.text;
    setState(() {
      _input.text = _output.text;
      _output.text = temp;
      _mode = _mode == 'Encrypt' ? 'Decrypt' : 'Encrypt';
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    // Ensure algorithm is valid for current category
    if (!_algorithms.contains(_algorithm)) {
      _algorithm = _algorithms.first;
    }

    return ToolSampleAction(
      onPressed: () {
        setState(() => _input.text = 'Hello, World! This is a secret message.');
        _process();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Controls row 1: Category & Algorithm
          ToolToolbar(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Category:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  SmallDropdown(
                    items: _categories,
                    initialValue: _category,
                    onChanged: (v) {
                      setState(() {
                        _category = v;
                        _algorithm = _algorithmsByCategory[v]!.first;
                      });
                      _process();
                    },
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Algorithm:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  SmallDropdown(
                    items: _algorithms,
                    initialValue: _algorithm,
                    onChanged: (v) {
                      setState(() => _algorithm = v);
                      _process();
                    },
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Mode:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  SegmentedToggle(
                    options: const ['Encrypt', 'Decrypt'],
                    initialIndex: _mode == 'Encrypt' ? 0 : 1,
                    onChanged: (i) {
                      setState(() => _mode = i == 0 ? 'Encrypt' : 'Decrypt');
                      _process();
                    },
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Output:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  SegmentedToggle(
                    options: const ['Base64', 'Hex'],
                    initialIndex: _outputFormat == 'Base64' ? 0 : 1,
                    onChanged: (i) {
                      setState(() => _outputFormat = i == 0 ? 'Base64' : 'Hex');
                      _process();
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Key input row
          Row(
            children: [
              const Text(
                'Password/Key:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: toolSurfaceDecoration(context, radius: 6),
                  child: TextField(
                    controller: _key,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Enter password for encryption/decryption...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintStyle: TextStyle(color: appColors.mutedText),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 12, color: appColors.editorText),
                    onChanged: (_) => _process(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Input/Output editors
          Expanded(
            child: buildAdaptiveSplit(
              first: EditorPane(
                label: _mode == 'Encrypt' ? 'Plaintext' : 'Ciphertext',
                actions: [
                  ToolIconButton(
                    icon: Icons.swap_horiz,
                    tooltip: 'Swap & toggle mode',
                    onPressed: _swapInputOutput,
                  ),
                ],
                controller: _input,
                onChanged: (_) => _process(),
                placeholder: _mode == 'Encrypt'
                    ? 'Enter text to encrypt...'
                    : 'Enter ciphertext to decrypt...',
              ),
              second: EditorPane(
                label: _mode == 'Encrypt' ? 'Ciphertext' : 'Plaintext',
                actions: [
                  ToolButton(
                    label: 'Copy',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: _output.text)),
                  ),
                ],
                controller: _output,
                readOnly: true,
                placeholder: _mode == 'Encrypt'
                    ? 'Encrypted output appears here...'
                    : 'Decrypted output appears here...',
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: errorToolTextStyle(context)),
          ],
        ],
      ),
    );
  }
}

Widget buildTextEncryption() {
  return const _TextEncryptionView();
}
