import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

part 'rsa_service_impl.dart';

class RSAService {
  static Future<AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>>
      generateRSAKeyPair() async {
    if (kIsWeb) {
      await Future.delayed(Duration.zero);
      return _RSAServiceImpl.generateRSAKeyPairSync();
    }
    return Isolate.run(_RSAServiceImpl.generateRSAKeyPairSync);
  }

  static Future<Uint8List> encrypt(Uint8List data, RSAPublicKey publicKey) async {
    if (kIsWeb) {
      await Future.delayed(Duration.zero);
      return _RSAServiceImpl.syncEncrypt(data, publicKey);
    }
    return Isolate.run(() => _RSAServiceImpl.syncEncrypt(data, publicKey));
  }

  static Future<Uint8List> decrypt(Uint8List data, RSAPrivateKey privateKey) async {
    if (kIsWeb) {
      await Future.delayed(Duration.zero);
      return _RSAServiceImpl.syncDecrypt(data, privateKey);
    }
    return Isolate.run(() => _RSAServiceImpl.syncDecrypt(data, privateKey));
  }

  static Future<Uint8List> sign(Uint8List value, RSAPrivateKey privateKey) async {
    if (kIsWeb) {
      await Future.delayed(Duration.zero);
      return _RSAServiceImpl.syncSign(value, privateKey);
    }
    return Isolate.run(() => _RSAServiceImpl.syncSign(value, privateKey));
  }

  static Future<bool> verify(
      Uint8List value, Uint8List signature, RSAPublicKey publicKey,) async {
    if (kIsWeb) {
      await Future.delayed(Duration.zero);
      return _RSAServiceImpl.syncVerify(value, signature, publicKey);
    }
    return Isolate.run(
        () => _RSAServiceImpl.syncVerify(value, signature, publicKey),);
  }

  static Map<String, String> transformRSAPrivateKeyToMap(
      RSAPrivateKey privateKey,) {
    return _RSAServiceImpl.transformRSAPrivateKeyToMap(privateKey);
  }

  static RSAPrivateKey transformMapToRSAPrivateKey(Map<String, String> map) {
    return _RSAServiceImpl.transformMapToRSAPrivateKey(map);
  }

  static Map<String, String> transformRSAPublicKeyToMap(
      RSAPublicKey publicKey,) {
    return _RSAServiceImpl.transformRSAPublicKeyToMap(publicKey);
  }

  static RSAPublicKey transformMapToRSAPublicKey(Map<String, String> map) {
    return _RSAServiceImpl.transformMapToRSAPublicKey(map);
  }
}
