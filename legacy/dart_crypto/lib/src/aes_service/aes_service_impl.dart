part of 'aes_service.dart';

class _AESServiceImpl {
  static const int _nonceByteLength = 12;
  static const int _saltByteLength = 24;
  static const int _keyByteLength = 32;
  static const int _macSize = 128;

  static Uint8List generateKey() {
    return generateRandomSecureBytes(_keyByteLength);
  }

  static Uint8List syncEncrypt(Uint8List bytes, Uint8List key) {
    if (key.length != _keyByteLength) {
      throw Exception('Incorrect key provided');
    }

    final salt = generateRandomSecureBytes(_saltByteLength);
    final nonce = generateRandomSecureBytes(_nonceByteLength);

    final ephemeralKey = _deriveEphemeralKey(mainKey: key, salt: salt);
    final encryptCipher = _initializeCipher(
      isForEncryption: true,
      ephemeralKey: ephemeralKey,
      nonce: nonce,
    );

    final encryptedBytes = encryptCipher.process(bytes);

    return Uint8List.fromList(salt + nonce + encryptedBytes);
  }

  static Uint8List syncDecrypt(Uint8List encryptedBytes, Uint8List key) {
    if (encryptedBytes.length < _saltByteLength + _nonceByteLength) {
      throw ArgumentError('Ciphertext too short, no room for salt and nonce.');
    }

    final salt = encryptedBytes.sublist(0, _saltByteLength);
    final nonce = encryptedBytes.sublist(
      _saltByteLength,
      _saltByteLength + _nonceByteLength,
    );
    final ciphertext =
        encryptedBytes.sublist(_saltByteLength + _nonceByteLength);

    final ephemeralKey = _deriveEphemeralKey(mainKey: key, salt: salt);
    final decryptCipher = _initializeCipher(
      isForEncryption: false,
      ephemeralKey: ephemeralKey,
      nonce: nonce,
    );

    return decryptCipher.process(ciphertext);
  }

  static GCMBlockCipher _initializeCipher({
    required bool isForEncryption,
    required Uint8List ephemeralKey,
    required Uint8List nonce,
  }) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      isForEncryption,
      AEADParameters(
        KeyParameter(ephemeralKey),
        _macSize,
        nonce,
        Uint8List(0),
      ),
    );
    return cipher;
  }

  static Uint8List _deriveEphemeralKey({
    required Uint8List mainKey,
    required Uint8List salt,
  }) {
    final hkdf = HKDFKeyDerivator(SHA256Digest())
      ..init(
        HkdfParameters(
          mainKey,
          _keyByteLength,
          salt,
          fuzzVersionInfo,
        ),
      );

    final derived = Uint8List(_keyByteLength);
    hkdf.deriveKey(null, 0, derived, 0);
    return derived;
  }
}

@visibleForTesting
// ignore: unused_element
class AESServiceDebugExpose {
  static Uint8List deriveEphemeralKey({
    required Uint8List mainKey,
    required Uint8List salt,
  }) =>
      _AESServiceImpl._deriveEphemeralKey(mainKey: mainKey, salt: salt);

  static Uint8List encryptWithFixedSaltNonce({
    required Uint8List plaintext,
    required Uint8List key,
    required Uint8List salt,
    required Uint8List nonce,
  }) {
    final epk = _AESServiceImpl._deriveEphemeralKey(mainKey: key, salt: salt);
    final c = _AESServiceImpl._initializeCipher(
      isForEncryption: true,
      ephemeralKey: epk,
      nonce: nonce,
    ).process(plaintext);
    return Uint8List.fromList(salt + nonce + c);
  }
}
