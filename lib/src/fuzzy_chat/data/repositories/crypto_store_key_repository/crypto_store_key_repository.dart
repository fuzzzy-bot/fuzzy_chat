import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fuzzy_chat/lib.dart';

/// The wrapped store key (0x10 blob) — the only key material Dart ever holds,
/// and only in its Argon2id-wrapped form.
class CryptoStoreKeyRepository {
  CryptoStoreKeyRepository({
    required CryptoCoreService cryptoCoreService,
  }) : _cryptoCoreService = cryptoCoreService;

  final CryptoCoreService _cryptoCoreService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const _storeKeyKey = 'crypto_store_key_v1';

  Future<Uint8List?> read() async {
    final wrappedBase64 = await _secureStorage.read(key: _storeKeyKey);
    if (wrappedBase64 == null) return null;
    return base64Decode(wrappedBase64);
  }

  Future<void> write(Uint8List wrapped) async {
    await _secureStorage.write(
      key: _storeKeyKey,
      value: base64Encode(wrapped),
    );
  }

  /// Creates the store key wrapped under [password] when none exists yet.
  Future<CryptoCoreResponse<void>> ensureStoreKey(String password) async {
    if (await read() != null) return const CryptoCoreSuccess(null);

    final createRes = await _cryptoCoreService.createStoreKey(password);
    if (createRes is CryptoCoreFailure) {
      return CryptoCoreFailure((createRes as CryptoCoreFailure).type);
    }

    await write((createRes as CryptoCoreSuccess<Uint8List>).data);
    return const CryptoCoreSuccess(null);
  }

  /// Re-wraps the store key from [oldPassword] to [newPassword] — one write.
  Future<CryptoCoreResponse<void>> rewrap({
    required String oldPassword,
    required String newPassword,
  }) async {
    final wrapped = await read();
    // `ensureStoreKey` runs at boot, so a missing blob is a broken invariant.
    if (wrapped == null) {
      return const CryptoCoreFailure(CryptoCoreFailureType.internal);
    }

    final rewrapRes = await _cryptoCoreService.rewrapStoreKey(
      wrapped: wrapped,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    if (rewrapRes is CryptoCoreFailure) {
      return CryptoCoreFailure((rewrapRes as CryptoCoreFailure).type);
    }

    await write((rewrapRes as CryptoCoreSuccess<Uint8List>).data);
    return const CryptoCoreSuccess(null);
  }
}
