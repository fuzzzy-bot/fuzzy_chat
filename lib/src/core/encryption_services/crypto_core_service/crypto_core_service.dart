import 'dart:typed_data';
import 'package:fuzzy_chat/lib.dart';
import 'package:fuzzy_chat/rust_bridge/api/core.dart' as rust_core;
import 'package:fuzzy_chat/rust_bridge/api/files.dart' as rust_files;
import 'package:fuzzy_chat/rust_bridge/api/formats.dart' as rust_formats;
import 'package:fuzzy_chat/rust_bridge/api/passwords.dart' as rust_passwords;
import 'package:fuzzy_chat/rust_bridge/api/vault.dart' as rust_vault;
import 'package:fuzzy_chat/rust_bridge/error.dart';
import 'package:path/path.dart' as path;

export 'components/components.dart';

/// The vault master key as Dart ever holds it: an opaque handle whose bytes
/// stay in the core. `close()` zeroises it (later seal/open calls answer
/// `storeLocked`), `dispose()` frees the handle.
typedef VaultKey = rust_vault.VaultKey;

/// The only importer of `package:fuzzy_chat/rust_bridge/...` besides
/// `initializer.dart`. Owns the single `CryptoCore` handle of the process and
/// maps every `CoreError` onto a [CryptoCoreResponse].
class CryptoCoreService {
  CryptoCoreService({
    required String storeDirectoryPath,
  }) : _storeDirectoryPath = storeDirectoryPath;

  /// uuid-v4 shape, as `store::validate_chat_id` demands — a blob's chat id
  /// is a path component on the Rust side and must never be trusted before
  /// this check.
  static final _chatIdShape =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

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

  /// The chat id a pasted invitation or acceptance names — a routing hint
  /// only: nothing is authenticated until [acceptInvitation] /
  /// [completeHandshake] verify the signature against it.
  CryptoCoreResponse<String> peekChatId(String text) {
    final chatIdRes = _guardedSync(() => rust_formats.peekChatId(text: text));
    if (chatIdRes is CryptoCoreSuccess<String> &&
        !_chatIdShape.hasMatch(chatIdRes.data)) {
      return const CryptoCoreFailure(CryptoCoreFailureType.corrupt);
    }
    return chatIdRes;
  }

  /// A (inviter): the chat's Olm account and its signed invitation. A
  /// pending chat regenerates; a connected one is `internal`.
  Future<CryptoCoreResponse<CryptoCoreInvitation>> createInvitation(
    String chatId,
  ) {
    return _withCore((core) async {
      final content = await core.createInvitation(chatId: chatId);
      return CryptoCoreInvitation(chatId: chatId, content: content);
    });
  }

  Future<CryptoCoreResponse<CryptoCoreInvitation>> currentInvitation(
    String chatId,
  ) {
    return _withCore((core) async {
      final content = await core.currentInvitation(chatId: chatId);
      return CryptoCoreInvitation(chatId: chatId, content: content);
    });
  }

  /// B (accepter): verifies [invitation], establishes the session and
  /// returns the signed acceptance. [chatId] must be the id the invitation
  /// names (`wrongChat` otherwise); a chat that already has state is
  /// `internal`.
  Future<CryptoCoreResponse<CryptoCoreAcceptance>> acceptInvitation({
    required String chatId,
    required String invitation,
  }) {
    return _withCore((core) async {
      final content = await core.acceptInvitation(
        chatId: chatId,
        invitation: invitation,
      );
      return CryptoCoreAcceptance(chatId: chatId, content: content);
    });
  }

  Future<CryptoCoreResponse<CryptoCoreAcceptance>> currentAcceptance(
    String chatId,
  ) {
    return _withCore((core) async {
      final content = await core.currentAcceptance(chatId: chatId);
      return CryptoCoreAcceptance(chatId: chatId, content: content);
    });
  }

  /// A (inviter): verifies [acceptance] and completes the handshake. The
  /// one-time key is consumed exactly once, so a second acceptance of the
  /// same invitation is `invitationAlreadyUsed`.
  Future<CryptoCoreResponse<void>> completeHandshake({
    required String chatId,
    required String acceptance,
  }) {
    return _withCore(
      (core) => core.completeHandshake(chatId: chatId, acceptance: acceptance),
    );
  }

  /// Zeroises and unlinks the chat's state; a chat the store never had is
  /// not an error.
  Future<CryptoCoreResponse<void>> deleteChat(String chatId) {
    return _withCore((core) => core.deleteChat(chatId: chatId));
  }

  /// Fuzzes [text] on the chat's live Olm session; the ratcheted session is
  /// on disk before the `Fuzz/` blob comes back. A chat that is not
  /// connected is `internal`.
  Future<CryptoCoreResponse<String>> encryptText({
    required String chatId,
    required String text,
  }) {
    return _withCore((core) => core.encryptText(chatId: chatId, text: text));
  }

  /// Unfuzzes a pasted `Fuzz/` message [blob] against the chat's session. A
  /// blob decrypts once: a second paste is `replay`, one for another chat
  /// `wrongChat`, one behind the window `tooOld`, garbage `corrupt` /
  /// `unsupportedFormat`. Nothing is persisted on failure.
  Future<CryptoCoreResponse<String>> decryptText({
    required String chatId,
    required String blob,
  }) {
    return _withCore((core) => core.decryptText(chatId: chatId, blob: blob));
  }

  /// Fuzzes the file at [inputPath] for [chatId] into the chat-mode container
  /// at [outputPath]. The file key rides in one Olm message — one ratchet
  /// step, taken under the core lock and persisted before this returns — and
  /// the chunks then stream without the core, so a running (or paused) file
  /// never blocks a text message or a lock. Progress, pause/resume/cancel and
  /// the `.part` rules arrive through the handler; a run failure is the
  /// terminal event's `errorMessage` (a [CryptoCoreFailureType] name) with
  /// `isComplete` set — check `errorMessage` first.
  Future<CryptoCoreResponse<FileProcessingHandler>> encryptFileForChat({
    required String chatId,
    required String inputPath,
    required String outputPath,
  }) {
    return _withCore((core) async {
      final ticket =
          await core.prepareFileSend(chatId: chatId, input: inputPath);
      return _startFileJob(
        (job) =>
            rust_files.runFileJob(ticket: ticket, output: outputPath, job: job),
      );
    });
  }

  /// Unfuzzes the chat-mode container at [inputPath] for [chatId] into
  /// [outputDirectoryPath] under the sender's original file name. The
  /// container's key message is consumed here (a second attempt is `replay`;
  /// `wrongChat`, `tooOld`, and `corrupt` for a truncated or tampered header
  /// leave nothing consumed), so a run failure after a success here is
  /// terminal for that container — the sender has to send it again. Never
  /// call this on a file that is still being written.
  Future<CryptoCoreResponse<CryptoCoreReceivedFile>> decryptFileForChat({
    required String chatId,
    required String inputPath,
    required String outputDirectoryPath,
  }) {
    return _withCore((core) async {
      final ticket =
          await core.prepareFileReceive(chatId: chatId, input: inputPath);
      // Before the run: a running job holds the ticket's write lock.
      final outputPath =
          path.join(outputDirectoryPath, await ticket.originalName());
      final handler = await _startFileJob(
        (job) =>
            rust_files.runFileJob(ticket: ticket, output: outputPath, job: job),
      );
      return CryptoCoreReceivedFile(outputPath: outputPath, handler: handler);
    });
  }

  /// Fuzzes the file at [inputPath] under [password] (Argon2id, fresh salt)
  /// into the password-mode container at [outputPath]; the store is not
  /// involved, so this works with a locked store and never queues a chat call.
  Future<CryptoCoreResponse<FileProcessingHandler>> encryptFileWithPassword({
    required String password,
    required String inputPath,
    required String outputPath,
  }) {
    return _guarded(
      () => _startFileJob(
        (job) => rust_files.encryptFile(
          password: password,
          input: inputPath,
          output: outputPath,
          job: job,
        ),
      ),
    );
  }

  /// Inverse of [encryptFileWithPassword]. A wrong password (or a corrupt
  /// first chunk) ends the stream with `wrongPassword`, any later damage
  /// with `corrupt`; no output and no `.part` exist after a failure.
  Future<CryptoCoreResponse<FileProcessingHandler>> decryptFileWithPassword({
    required String password,
    required String inputPath,
    required String outputPath,
  }) {
    return _guarded(
      () => _startFileJob(
        (job) => rust_files.decryptFile(
          password: password,
          input: inputPath,
          output: outputPath,
          job: job,
        ),
      ),
    );
  }

  /// Fuzzes [text] under [password] (Argon2id, fresh salt and nonce) as a
  /// paste-able `Fuzz/` 0x05 blob; like the password-mode file calls the
  /// store is not involved, so this works with a locked store.
  Future<CryptoCoreResponse<String>> passwordSealText({
    required String password,
    required String text,
  }) {
    return _guarded(
      () => rust_passwords.passwordSealText(password: password, text: text),
    );
  }

  /// Inverse of [passwordSealText]. A wrong password and a tampered blob are
  /// both `wrongPassword` (the AEAD cannot tell them apart); a pasted string
  /// that is not a 0x05 blob is `unsupportedFormat`, a malformed one
  /// `corrupt`.
  Future<CryptoCoreResponse<String>> passwordOpenText({
    required String password,
    required String blob,
  }) {
    return _guarded(
      () => rust_passwords.passwordOpenText(password: password, blob: blob),
    );
  }

  /// One `FileJob` per file — a cancelled job is spent. Rust events map 1:1
  /// onto [FileProcessingProgress]; the terminal event's error text becomes
  /// the matching [CryptoCoreFailureType] name so no Rust string leaves here.
  Future<FileProcessingHandler> _startFileJob(
    Stream<rust_files.FileProgress> Function(rust_files.FileJob job) start,
  ) async {
    final job = await rust_files.newFileJob();
    return FileProcessingHandler(
      progressStream: start(job).map(
        (event) => FileProcessingProgress(
          progress: event.progress,
          isComplete: event.isComplete,
          isCancelled: event.isCancelled,
          errorMessage: switch (event.errorMessage) {
            null => null,
            final text => _failureTypeOfText(text).name,
          },
        ),
      ),
      pause: job.pause,
      resume: job.resume,
      cancel: job.cancel,
    );
  }

  /// Seals [bytes] under the store-derived local key (0x20 blob) for
  /// at-rest storage on this device only.
  Future<CryptoCoreResponse<Uint8List>> sealLocal(Uint8List bytes) {
    return _withCore((core) => core.sealLocal(bytes: bytes));
  }

  /// Inverse of [sealLocal]; a tampered or foreign blob is `corrupt`.
  Future<CryptoCoreResponse<Uint8List>> openLocal(Uint8List blob) {
    return _withCore((core) => core.openLocal(blob: blob));
  }

  /// The chat's 60-digit safety number (12 groups of 5, space-separated) —
  /// identical on both sides once the peer's key is known; a chat without a
  /// peer yet is `unknownChat`.
  Future<CryptoCoreResponse<String>> safetyNumber(String chatId) {
    return _withCore((core) => core.safetyNumber(chatId: chatId));
  }

  /// Records whether the user compared the safety number with the peer. The
  /// flag lives in the chat's core state, so it resets with the keys on a
  /// re-pair; a chat without a peer is `unknownChat`.
  Future<CryptoCoreResponse<void>> markVerified({
    required String chatId,
    required bool verified,
  }) {
    return _withCore(
      (core) => core.markVerified(chatId: chatId, verified: verified),
    );
  }

  /// The flag [markVerified] set; `false` for a chat that was never marked.
  Future<CryptoCoreResponse<bool>> isVerified(String chatId) {
    return _withCore((core) => core.isVerified(chatId: chatId));
  }

  /// Draws a fresh vault master key and wraps it under [password]: the
  /// unlocked handle for this session plus the 0x10 blob the vault metadata
  /// keeps. Queued with the store-key calls (one Argon2id at a time).
  Future<CryptoCoreResponse<CryptoCoreVaultInit>> vaultInit(String password) {
    return _serialized(() async {
      final created = await rust_vault.vaultInit(password: password);
      return CryptoCoreVaultInit(key: created.key, wrapped: created.wrapped);
    });
  }

  /// Unwraps the vault master key from [wrapped]; a wrong password (or a
  /// tampered blob) is `wrongPassword`.
  Future<CryptoCoreResponse<VaultKey>> vaultUnlock({
    required Uint8List wrapped,
    required String password,
  }) {
    return _serialized(
      () => rust_vault.vaultUnlock(password: password, wrapped: wrapped),
    );
  }

  /// Re-wraps the same master key under [newPassword] (fresh salt and
  /// nonce). The key does not change, so no vault item is re-encrypted; the
  /// caller stores the returned blob in place of [wrapped].
  Future<CryptoCoreResponse<Uint8List>> vaultRewrap({
    required Uint8List wrapped,
    required String oldPassword,
    required String newPassword,
  }) {
    return _serialized(
      () => rust_vault.vaultRewrap(
        oldPassword: oldPassword,
        newPassword: newPassword,
        wrapped: wrapped,
      ),
    );
  }

  /// Seals one vault item under [key] (0x20 blob, AAD `vault-item`); a
  /// closed handle answers `storeLocked`.
  Future<CryptoCoreResponse<Uint8List>> vaultSeal({
    required VaultKey key,
    required Uint8List bytes,
  }) {
    return _guarded(() => rust_vault.vaultSeal(key: key, bytes: bytes));
  }

  /// Inverse of [vaultSeal]; a tampered or foreign blob is `corrupt`.
  Future<CryptoCoreResponse<Uint8List>> vaultOpen({
    required VaultKey key,
    required Uint8List blob,
  }) {
    return _guarded(() => rust_vault.vaultOpen(key: key, blob: blob));
  }

  /// [passwordSealText] for arbitrary bytes, as the binary 0x05 blob — the
  /// vault's optional custom-password layer over a sealed item.
  Future<CryptoCoreResponse<Uint8List>> passwordSealBytes({
    required String password,
    required Uint8List bytes,
  }) {
    return _guarded(
      () => rust_passwords.passwordSealBytes(password: password, bytes: bytes),
    );
  }

  /// Inverse of [passwordSealBytes]; the same error rules as
  /// [passwordOpenText].
  Future<CryptoCoreResponse<Uint8List>> passwordOpenBytes({
    required String password,
    required Uint8List blob,
  }) {
    return _guarded(
      () => rust_passwords.passwordOpenBytes(password: password, blob: blob),
    );
  }

  /// Every chat call: no Argon2, so nothing to queue; a closed store answers
  /// `storeLocked` instead of reaching a null handle.
  Future<CryptoCoreResponse<T>> _withCore<T>(
    Future<T> Function(rust_core.CryptoCore core) call,
  ) {
    final core = _core;
    if (core == null) {
      return Future.value(
        const CryptoCoreFailure(CryptoCoreFailureType.storeLocked),
      );
    }
    return _guarded(() => call(core));
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

  CryptoCoreResponse<T> _guardedSync<T>(T Function() call) {
    try {
      return CryptoCoreSuccess(call());
    } on CoreError catch (error) {
      return CryptoCoreFailure(_failureTypeOf(error));
    } catch (ex) {
      logger.e('ERROR: $ex');
      return const CryptoCoreFailure(CryptoCoreFailureType.internal);
    }
  }

  /// The `CoreError` display text a file job's terminal event carries (frb
  /// runs stream functions unawaited, so an error cannot be thrown to Dart).
  static CryptoCoreFailureType _failureTypeOfText(String text) {
    return switch (text) {
      'wrong password' => CryptoCoreFailureType.wrongPassword,
      'corrupt' => CryptoCoreFailureType.corrupt,
      'unsupported format' => CryptoCoreFailureType.unsupportedFormat,
      'io' => CryptoCoreFailureType.io,
      'store locked' => CryptoCoreFailureType.storeLocked,
      _ => CryptoCoreFailureType.internal,
    };
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
