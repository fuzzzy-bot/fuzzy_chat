import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:fuzzy_chat/src/core/web_stubs/web_stubs.dart';
import 'package:pointycastle/export.dart';

class KeyStorageRepository {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final WebSecureStorage _webSecureStorage = WebSecureStorage();

  Future<String?> _read(String key) async {
    if (kIsWeb) {
      await _webSecureStorage.init();
      return await _webSecureStorage.read(key: key);
    }
    return await _secureStorage.read(key: key);
  }

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      await _webSecureStorage.init();
      await _webSecureStorage.write(key: key, value: value);
      return;
    }
    await _secureStorage.write(key: key, value: value);
  }

  Future<void> _delete(String key) async {
    if (kIsWeb) {
      await _webSecureStorage.init();
      await _webSecureStorage.delete(key: key);
      return;
    }
    await _secureStorage.delete(key: key);
  }

  Future<void> savePrivateKey(String chatId, RSAPrivateKey privateKey) async {
    final password = sl.get<FuzzyAuthStore>().state.authData.password;
    final privateKeyMap = RSAService.transformRSAPrivateKeyToMap(privateKey);
    final privateKeyJson = jsonEncode(privateKeyMap);
    final privateKeyBytes = Uint8List.fromList(utf8.encode(privateKeyJson));

    final encryptedPrivateKey =
        await PasswordBasedEncryptionSevice.encrypt(privateKeyBytes, password);
    final encryptedPrivateKeyBase64 = base64Encode(encryptedPrivateKey);

    await _write('privateKey_$chatId', encryptedPrivateKeyBase64);
  }

  Future<void> savePublicKey(String chatId, RSAPublicKey publicKey) async {
    final publicKeyMap = RSAService.transformRSAPublicKeyToMap(publicKey);
    await _write('publicKey_$chatId', jsonEncode(publicKeyMap));
  }

  Future<RSAPrivateKey?> getPrivateKey(String chatId) async {
    final password = sl.get<FuzzyAuthStore>().state.authData.password;
    final privateKeyData = await _read('privateKey_$chatId');

    if (privateKeyData != null) {
      if (privateKeyData.startsWith('{')) {
        return RSAService.transformMapToRSAPrivateKey(
          (jsonDecode(privateKeyData) as Map<String, dynamic>).cast(),
        );
      } else {
        final encryptedPrivateKey = base64Decode(privateKeyData);
        final decryptedBytes = await PasswordBasedEncryptionSevice.decrypt(
          encryptedPrivateKey,
          password,
        );
        final privateKeyJson = utf8.decode(decryptedBytes);

        return RSAService.transformMapToRSAPrivateKey(
          (jsonDecode(privateKeyJson) as Map<String, dynamic>).cast(),
        );
      }
    }
    return null;
  }

  Future<RSAPublicKey?> getPublicKey(String chatId) async {
    final publicKeyJson = await _read('publicKey_$chatId');

    if (publicKeyJson != null) {
      return RSAService.transformMapToRSAPublicKey(
        (jsonDecode(publicKeyJson) as Map<String, dynamic>).cast(),
      );
    }
    return null;
  }

  Future<void> saveSymmetricKey(String chatId, Uint8List symmetricKey) async {
    final password = sl.get<FuzzyAuthStore>().state.authData.password;

    final encryptedSymmetricKey =
        await PasswordBasedEncryptionSevice.encrypt(symmetricKey, password);
    final encryptedSymmetricKeyBase64 = base64Encode(encryptedSymmetricKey);

    await _write('symmetricKey_$chatId', encryptedSymmetricKeyBase64);
  }

  Future<Uint8List?> getSymmetricKey(String chatId) async {
    final password = sl.get<FuzzyAuthStore>().state.authData.password;

    final encryptedSymmetricKeyBase64 =
        await _read('symmetricKey_$chatId');
    if (encryptedSymmetricKeyBase64 != null) {
      final encryptedSymmetricKey = base64Decode(encryptedSymmetricKeyBase64);
      final symmetricKey = await PasswordBasedEncryptionSevice.decrypt(
        encryptedSymmetricKey,
        password,
      );

      return symmetricKey;
    }

    return null;
  }

  Future<void> saveOtherPartyPublicKey(
    String chatId,
    RSAPublicKey publicKey,
  ) async {
    final publicKeyMap = RSAService.transformRSAPublicKeyToMap(publicKey);
    await _write('otherPartyPublicKey_$chatId', jsonEncode(publicKeyMap));
  }

  Future<RSAPublicKey?> getOtherPartyPublicKey(String chatId) async {
    final publicKeyJson =
        await _read('otherPartyPublicKey_$chatId');
    if (publicKeyJson != null) {
      return RSAService.transformMapToRSAPublicKey(
        (jsonDecode(publicKeyJson) as Map<String, dynamic>).cast(),
      );
    }
    return null;
  }

  static const _migrationStatusKey = 'key_migration_status';
  static const _migrationChatIdsKey = 'key_migration_chat_ids';
  static const _staged = 'staged';
  static const _committed = 'committed';

  Future<void> reencryptAllKeys({
    required List<String> chatIds,
    required String oldPassword,
    required String newPassword,
  }) async {
    await _write(_migrationChatIdsKey, chatIds.join(','));

    for (final chatId in chatIds) {
      await _stageReencryptedKey(
        storageKeyPrefix: 'privateKey',
        chatId: chatId,
        oldPassword: oldPassword,
        newPassword: newPassword,
        allowLegacyPlainJson: true,
      );
      await _stageReencryptedKey(
        storageKeyPrefix: 'symmetricKey',
        chatId: chatId,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
    }

    await _write(_migrationStatusKey, _staged);
    await _commitStagedKeys(chatIds);
    await _cleanupStagedKeys(chatIds);
  }

  Future<void> _stageReencryptedKey({
    required String storageKeyPrefix,
    required String chatId,
    required String oldPassword,
    required String newPassword,
    bool allowLegacyPlainJson = false,
  }) async {
    final raw = await _read('${storageKeyPrefix}_$chatId');
    if (raw == null) return;

    final Uint8List plaintext;
    if (allowLegacyPlainJson && raw.startsWith('{')) {
      plaintext = Uint8List.fromList(utf8.encode(raw));
    } else {
      plaintext = await PasswordBasedEncryptionSevice.decrypt(
        base64Decode(raw),
        oldPassword,
      );
    }

    final reencrypted =
        await PasswordBasedEncryptionSevice.encrypt(plaintext, newPassword);
    await _write(
      'staged_${storageKeyPrefix}_$chatId',
      base64Encode(reencrypted),
    );
  }

  Future<void> recoverStagedMigration() async {
    final status = await _read(_migrationStatusKey);
    if (status == null) return;

    final chatIdsRaw = await _read(_migrationChatIdsKey);
    if (chatIdsRaw == null || chatIdsRaw.isEmpty) {
      await _delete(_migrationStatusKey);
      return;
    }
    final chatIds = chatIdsRaw.split(',');

    if (status == _staged) {
      await _commitStagedKeys(chatIds);
      await _cleanupStagedKeys(chatIds);
    } else if (status == _committed) {
      await _cleanupStagedKeys(chatIds);
    }
  }

  Future<void> _commitStagedKeys(List<String> chatIds) async {
    for (final chatId in chatIds) {
      final stagedPrivate =
          await _read('staged_privateKey_$chatId');
      if (stagedPrivate != null) {
        await _write('privateKey_$chatId', stagedPrivate);
      }

      final stagedSymmetric =
          await _read('staged_symmetricKey_$chatId');
      if (stagedSymmetric != null) {
        await _write('symmetricKey_$chatId', stagedSymmetric);
      }
    }

    await _write(_migrationStatusKey, _committed);
  }

  Future<void> _cleanupStagedKeys(List<String> chatIds) async {
    for (final chatId in chatIds) {
      await _delete('staged_privateKey_$chatId');
      await _delete('staged_symmetricKey_$chatId');
    }
    await _delete(_migrationStatusKey);
    await _delete(_migrationChatIdsKey);
  }

  Future<void> clearAllKeysForChat(String chatId) async {
    await _delete('privateKey_$chatId');
    await _delete('publicKey_$chatId');
    await _delete('symmetricKey_$chatId');
    await _delete('otherPartyPublicKey_$chatId');
  }
}
