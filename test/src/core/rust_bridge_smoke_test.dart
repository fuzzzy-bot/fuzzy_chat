import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzy_chat/rust_bridge/api/core.dart';
import 'package:fuzzy_chat/rust_bridge/api/formats.dart';
import 'package:fuzzy_chat/rust_bridge/api/health.dart';
import 'package:fuzzy_chat/rust_bridge/error.dart';

import '../../helpers/crypto_core_test_init.dart';

const _chatId = '6f1e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2d';

/// `Fuzz/` + base64url without padding — the text envelope of plan §B.4.
String _fuzzText(List<int> blob) =>
    'Fuzz/${base64Url.encode(blob).replaceAll('=', '')}';

/// `FUZZ · 0x01 · type` followed by [payload].
List<int> _blob(int type, List<int> payload) =>
    [0x46, 0x55, 0x5A, 0x5A, 0x01, type, ...payload];

/// Invitation payload: `chat_id_len · chat_id · curve 32 · ed 32 · otk 32 · sig 64`.
List<int> _invitationBlob() => _blob(0x01, [
      _chatId.length,
      ...utf8.encode(_chatId),
      ...List.filled(32, 0x11),
      ...List.filled(32, 0x22),
      ...List.filled(32, 0x33),
      ...List.filled(64, 0x44),
    ]);

void main() {
  setUpAll(initCryptoCoreForTests);

  group('rust bridge smoke', () {
    test('coreVersion crosses the FFI', () async {
      final version = await coreVersion();

      expect(version, isNotEmpty);
    });

    test('roundTrip reverses bytes across the FFI', () async {
      final result = await roundTrip(bytes: [1, 2, 3]);

      expect(result, [3, 2, 1]);
    });
  });

  group('formats (sync)', () {
    test('blobTypeOf classifies a hand-built Fuzz/ string', () {
      expect(
        blobTypeOf(text: _fuzzText(_invitationBlob())),
        BlobType.invitation,
      );
      expect(blobTypeOf(text: 'Fuzz/RlVaWgEDAd6tvu8'), BlobType.message);
      expect(
        blobTypeOf(text: 'Fuzz/RlVa\r\n WgEDAd6tvu8'),
        BlobType.message,
        reason: 'ASCII whitespace from wrapping is ignored',
      );
    });

    test('blobTypeOf is unknown for storage-only kinds and garbage', () {
      expect(blobTypeOf(text: _fuzzText(_blob(0x10, [0]))), BlobType.unknown);
      expect(blobTypeOf(text: _fuzzText(_blob(0x20, [0]))), BlobType.unknown);
      expect(blobTypeOf(text: 'Fuzz/RlVaWgEDAA=='), BlobType.unknown);
      expect(blobTypeOf(text: 'not a blob'), BlobType.unknown);
    });

    test('peekChatId reads the clear chat id of an invitation', () {
      expect(peekChatId(text: _fuzzText(_invitationBlob())), _chatId);
    });

    test('peekChatId throws CoreError for other kinds and broken payloads', () {
      expect(
        () => peekChatId(text: 'Fuzz/RlVaWgEDAd6tvu8'),
        throwsA(CoreError.unsupportedFormat),
      );
      final truncated = _invitationBlob().sublist(0, 100);
      expect(
        () => peekChatId(text: _fuzzText(truncated)),
        throwsA(CoreError.corrupt),
      );
    });
  });

  group('store (async, opaque handle)', () {
    late Directory storeDir;

    setUp(() {
      storeDir = Directory.systemTemp.createTempSync('fuzzy_crypto_core_');
    });

    tearDown(() {
      if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
    });

    test('createStoreKey → openStore → sealLocal/openLocal → close', () async {
      final wrapped = await createStoreKey(password: 'pw');
      expect(wrapped.length, 103, reason: '0x10 blob: 6 + 16 + 9 + 24 + 48');
      expect(wrapped.sublist(0, 6), [0x46, 0x55, 0x5A, 0x5A, 0x01, 0x10]);

      final core = await openStore(
        storeDir: storeDir.path,
        wrapped: wrapped,
        password: 'pw',
      );
      expect(await core.storeDir(), storeDir.path);
      expect(
        Directory('${storeDir.path}/fuzzy_crypto_store').existsSync(),
        isTrue,
      );

      final sealed = await core.sealLocal(bytes: utf8.encode('history'));
      expect(sealed.sublist(0, 6), [0x46, 0x55, 0x5A, 0x5A, 0x01, 0x20]);
      expect(utf8.decode(await core.openLocal(blob: sealed)), 'history');

      final tampered = List<int>.of(sealed)..[40] ^= 1;
      await expectLater(
        core.openLocal(blob: tampered),
        throwsA(CoreError.corrupt),
      );

      await core.close();
      await expectLater(
        core.sealLocal(bytes: [1]),
        throwsA(CoreError.storeLocked),
      );
      await expectLater(
        core.deleteChat(chatId: _chatId),
        throwsA(CoreError.storeLocked),
      );
      core.dispose();
    });

    test('wrong password and rewrap', () async {
      final wrapped = await createStoreKey(password: 'pw');

      await expectLater(
        openStore(storeDir: storeDir.path, wrapped: wrapped, password: 'px'),
        throwsA(CoreError.wrongPassword),
      );

      final rewrapped = await rewrapStoreKey(
        wrapped: wrapped,
        oldPassword: 'pw',
        newPassword: '',
      );
      expect(rewrapped, isNot(wrapped));
      await expectLater(
        rewrapStoreKey(wrapped: wrapped, oldPassword: 'nope', newPassword: 'x'),
        throwsA(CoreError.wrongPassword),
      );

      final core = await openStore(
        storeDir: storeDir.path,
        wrapped: rewrapped,
        password: '',
      );
      await core.close();
      core.dispose();
    });
  });
}
