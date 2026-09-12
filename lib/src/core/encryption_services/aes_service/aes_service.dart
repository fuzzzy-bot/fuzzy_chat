import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:pointycastle/export.dart';

part 'aes_service_impl.dart';

class AESService {
  static Future<Uint8List> encrypt(Uint8List bytes, Uint8List key) async =>
      Isolate.run(() => _AESServiceImpl.syncEncrypt(bytes, key));

  static Future<Uint8List> decrypt(
    Uint8List encryptedBytes,
    Uint8List key,
  ) async =>
      Isolate.run(() => _AESServiceImpl.syncDecrypt(encryptedBytes, key));

  static Future<String> encryptText(String text, Uint8List key) async {
    final decryptedTextBytes = utf8.encode(text);
    final encryptedTextBytes = await encrypt(decryptedTextBytes, key);
    return base64Encode(encryptedTextBytes);
  }

  static Future<String> decryptText(
    String base64EncryptedText,
    Uint8List key,
  ) async {
    final encryptedTextBytes = base64Decode(base64EncryptedText);
    final decryptedTextBytes = await decrypt(encryptedTextBytes, key);
    return utf8.decode(decryptedTextBytes);
  }

  static Future<Uint8List> generateKey() async =>
      Isolate.run(_AESServiceImpl.generateKey);
}
