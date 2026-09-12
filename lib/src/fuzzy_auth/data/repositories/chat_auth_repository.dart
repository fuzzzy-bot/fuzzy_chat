import 'package:fuzzy_chat/lib.dart';

class ChatAuthRepository {
  ChatAuthRepository({
    required UserAuthPreferencesRepository userAuthPreferencesRepository,
    required CryptoStoreKeyRepository cryptoStoreKeyRepository,
    required CryptoCoreService cryptoCoreService,
  })  : _userAuthPreferencesRepository = userAuthPreferencesRepository,
        _cryptoStoreKeyRepository = cryptoStoreKeyRepository,
        _cryptoCoreService = cryptoCoreService;

  final UserAuthPreferencesRepository _userAuthPreferencesRepository;
  final CryptoStoreKeyRepository _cryptoStoreKeyRepository;
  final CryptoCoreService _cryptoCoreService;

  Future<bool> isChatAuthEnabled() async {
    final prefs = await _userAuthPreferencesRepository.getUserAuthPreferences();
    if (prefs == null || !prefs.isAuthenticationOnceEnabled) return false;

    final wrapped = await _cryptoStoreKeyRepository.read();
    return wrapped != null;
  }

  /// With the lock disabled the store key is wrapped under `''`; enabling it
  /// re-wraps that same key under [password].
  Future<bool> setupPassword(String password) async {
    final rewrapRes = await _cryptoStoreKeyRepository.rewrap(
      oldPassword: '',
      newPassword: password,
    );
    if (rewrapRes is CryptoCoreFailure) return false;

    await _userAuthPreferencesRepository.updateUserAuthPreferences(
      UserAuthPreferences(isAuthenticationOnceEnabled: true),
    );
    return true;
  }

  /// Opens the store under [password] and leaves it open — the wrapped store
  /// key is the verification token.
  Future<bool> verifyPassword(String password) async {
    final wrapped = await _cryptoStoreKeyRepository.read();
    if (wrapped == null) return false;

    final openRes = await _cryptoCoreService.openStore(
      wrapped: wrapped,
      password: password,
    );
    return openRes is CryptoCoreSuccess;
  }

  Future<bool> disableAuth(String currentPassword) async {
    final rewrapRes = await _cryptoStoreKeyRepository.rewrap(
      oldPassword: currentPassword,
      newPassword: '',
    );
    if (rewrapRes is CryptoCoreFailure) return false;

    await _userAuthPreferencesRepository.updateUserAuthPreferences(
      UserAuthPreferences(isAuthenticationOnceEnabled: false),
    );
    return true;
  }

  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
    required List<String> chatIds,
    required KeyStorageRepository keyStorageRepository,
  }) async {
    final rewrapRes = await _cryptoStoreKeyRepository.rewrap(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    if (rewrapRes is CryptoCoreFailure) return false;

    await keyStorageRepository.reencryptAllKeys(
      chatIds: chatIds,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );

    return true;
  }
}
