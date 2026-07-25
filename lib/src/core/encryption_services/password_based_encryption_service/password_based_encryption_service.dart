import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../../utils/secure_bytes_generation.dart';

part 'password_based_encryption_service_impl.dart';

class PasswordBasedEncryptionSevice {
  static Future<Uint8List> encrypt(Uint8List bytes, String password) async {
    if (kIsWeb) {
      await Future.delayed(Duration.zero);
      return _PasswordBasedEncryptionServiceImpl.syncEncrypt(bytes, password);
    }
    return Isolate.run(
        () => _PasswordBasedEncryptionServiceImpl.syncEncrypt(bytes, password),);
  }

  static Future<Uint8List> decrypt(
      Uint8List encryptedBytes, String password,) async {
    if (kIsWeb) {
      await Future.delayed(Duration.zero);
      return _PasswordBasedEncryptionServiceImpl.syncDecrypt(
          encryptedBytes, password,);
    }
    return Isolate.run(() => _PasswordBasedEncryptionServiceImpl.syncDecrypt(
        encryptedBytes, password,),);
  }

  static Future<Uint8List> deriveKey(String password, Uint8List salt) async {
    if (kIsWeb) {
      await Future.delayed(Duration.zero);
      return _PasswordBasedEncryptionServiceImpl.deriveKey(password, salt);
    }
    return Isolate.run(
        () => _PasswordBasedEncryptionServiceImpl.deriveKey(password, salt),);
  }
}
