import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fuzzy_chat/lib.dart';

import 'package:fuzzy_chat/src/core/web_stubs/web_stubs.dart';

class ChatAuthRepository {
  ChatAuthRepository({
    required UserAuthPreferencesRepository userAuthPreferencesRepository,
  }) : _userAuthPreferencesRepository = userAuthPreferencesRepository;

  final UserAuthPreferencesRepository _userAuthPreferencesRepository;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final WebSecureStorage _webSecureStorage = WebSecureStorage();

  static const _saltKey = 'chat_auth_salt';
  static const _verificationTokenKey = 'chat_auth_verification_token';

  Future<bool> isChatAuthEnabled() async {
    final prefs = await _userAuthPreferencesRepository.getUserAuthPreferences();
    if (prefs == null || !prefs.isAuthenticationOnceEnabled) return false;

    if (kIsWeb) {
      await _webSecureStorage.init();
      final salt = await _webSecureStorage.read(key: _saltKey);
      final token = await _webSecureStorage.read(key: _verificationTokenKey);
      return salt != null && token != null;
    }

    final salt = await _secureStorage.read(key: _saltKey);
    final token = await _secureStorage.read(key: _verificationTokenKey);
    return salt != null && token != null;
  }

  Future<void> setupPassword(String password) async {
    final salt = generateRandomSecureBytes(24);
    final masterKey =
        await PasswordBasedEncryptionSevice.deriveKey(password, salt);

    final verificationTokenBytes = generateRandomSecureBytes(32);
    final encryptedToken =
        await AESService.encrypt(verificationTokenBytes, masterKey);

    if (kIsWeb) {
      await _webSecureStorage.init();
      await _webSecureStorage.write(key: _saltKey, value: base64Encode(salt));
      await _webSecureStorage.write(
        key: _verificationTokenKey,
        value: base64Encode(encryptedToken),
      );
    } else {
      await _secureStorage.write(key: _saltKey, value: base64Encode(salt));
      await _secureStorage.write(
        key: _verificationTokenKey,
        value: base64Encode(encryptedToken),
      );
    }

    await _userAuthPreferencesRepository.updateUserAuthPreferences(
      UserAuthPreferences(isAuthenticationOnceEnabled: true),
    );
  }

  Future<bool> verifyPassword(String password) async {
    String? saltBase64;
    String? tokenBase64;

    if (kIsWeb) {
      await _webSecureStorage.init();
      saltBase64 = await _webSecureStorage.read(key: _saltKey);
      tokenBase64 = await _webSecureStorage.read(key: _verificationTokenKey);
    } else {
      saltBase64 = await _secureStorage.read(key: _saltKey);
      tokenBase64 = await _secureStorage.read(key: _verificationTokenKey);
    }

    if (saltBase64 == null || tokenBase64 == null) return false;

    final salt = base64Decode(saltBase64);
    final masterKey =
        await PasswordBasedEncryptionSevice.deriveKey(password, salt);
    final encryptedToken = base64Decode(tokenBase64);

    try {
      await AESService.decrypt(encryptedToken, masterKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disableAuth() async {
    if (kIsWeb) {
      await _webSecureStorage.init();
      await _webSecureStorage.delete(key: _saltKey);
      await _webSecureStorage.delete(key: _verificationTokenKey);
    } else {
      await _secureStorage.delete(key: _saltKey);
      await _secureStorage.delete(key: _verificationTokenKey);
    }

    await _userAuthPreferencesRepository.updateUserAuthPreferences(
      UserAuthPreferences(isAuthenticationOnceEnabled: false),
    );
  }

  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
    required List<String> chatIds,
    required KeyStorageRepository keyStorageRepository,
  }) async {
    final isValid = await verifyPassword(oldPassword);
    if (!isValid) return false;

    await keyStorageRepository.reencryptAllKeys(
      chatIds: chatIds,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );

    await setupPassword(newPassword);

    return true;
  }
}
