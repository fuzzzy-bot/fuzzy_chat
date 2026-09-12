import 'dart:typed_data';
import 'package:fuzzy_chat/lib.dart';
import 'package:fuzzy_chat/rust_bridge/api/core.dart' as rust_core;
import 'package:fuzzy_chat/rust_bridge/error.dart';

export 'components/components.dart';

/// The only importer of `package:fuzzy_chat/rust_bridge/...` besides
/// `initializer.dart`. Owns the single `CryptoCore` handle of the process and
/// maps every `CoreError` onto a [CryptoCoreResponse].
class CryptoCoreService {
  CryptoCoreService({
    required String storeDirectoryPath,
  }) : _storeDirectoryPath = storeDirectoryPath;

  final String _storeDirectoryPath;

  rust_core.CryptoCore? _core;

  /// Argon2id needs 64 MiB per run; the store-key calls queue behind each other
  /// so only one derivation is in flight at a time.
  Future<void> _argon2Queue = Future<void>.value();

  bool get isOpen => _core != null;

  Future<CryptoCoreResponse<Uint8List>> createStoreKey(String password) {
    return _serialized(
      () => rust_core.createStoreKey(password: password),
    );
  }

  /// Opens the store under [password]. A handle that is already open stays
  /// in place until the new one exists, then is closed — a wrong password
  /// never closes an open store, and callers only ever see one handle.
  Future<CryptoCoreResponse<void>> openStore({
    required Uint8List wrapped,
    required String password,
  }) {
    return _serialized(() async {
      final core = await rust_core.openStore(
        storeDir: _storeDirectoryPath,
        wrapped: wrapped,
        password: password,
      );
      await _closeNow();
      _core = core;
    });
  }

  Future<CryptoCoreResponse<Uint8List>> rewrapStoreKey({
    required Uint8List wrapped,
    required String oldPassword,
    required String newPassword,
  }) {
    return _serialized(
      () => rust_core.rewrapStoreKey(
        wrapped: wrapped,
        oldPassword: oldPassword,
        newPassword: newPassword,
      ),
    );
  }

  /// Zeroises the store key and every cached state; later calls on the core
  /// fail with [CryptoCoreFailureType.storeLocked]. Queued behind any
  /// in-flight store-key call so a lock never races an open.
  Future<CryptoCoreResponse<void>> close() {
    return _serialized(_closeNow);
  }

  Future<void> _closeNow() async {
    final core = _core;
    if (core == null) return;
    _core = null;
    await core.close();
    core.dispose();
  }

  Future<CryptoCoreResponse<T>> _serialized<T>(Future<T> Function() call) {
    final result = _argon2Queue.then((_) => _guarded(call));
    _argon2Queue = result.then((_) {});
    return result;
  }

  Future<CryptoCoreResponse<T>> _guarded<T>(Future<T> Function() call) async {
    try {
      return CryptoCoreSuccess(await call());
    } on CoreError catch (error) {
      return CryptoCoreFailure(_failureTypeOf(error));
    } catch (ex) {
      logger.e('ERROR: $ex');
      return const CryptoCoreFailure(CryptoCoreFailureType.internal);
    }
  }

  static CryptoCoreFailureType _failureTypeOf(CoreError error) {
    return switch (error) {
      CoreError.unsupportedFormat => CryptoCoreFailureType.unsupportedFormat,
      CoreError.invalidSignature => CryptoCoreFailureType.invalidSignature,
      CoreError.invitationAlreadyUsed =>
        CryptoCoreFailureType.invitationAlreadyUsed,
      CoreError.wrongChat => CryptoCoreFailureType.wrongChat,
      CoreError.replay => CryptoCoreFailureType.replay,
      CoreError.tooOld => CryptoCoreFailureType.tooOld,
      CoreError.corrupt => CryptoCoreFailureType.corrupt,
      CoreError.wrongPassword => CryptoCoreFailureType.wrongPassword,
      CoreError.storeLocked => CryptoCoreFailureType.storeLocked,
      CoreError.unknownChat => CryptoCoreFailureType.unknownChat,
      CoreError.io => CryptoCoreFailureType.io,
      CoreError.cancelled => CryptoCoreFailureType.cancelled,
      CoreError.internal => CryptoCoreFailureType.internal,
    };
  }
}
