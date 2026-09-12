import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzy_chat/rust_bridge/api/core.dart';
import 'package:fuzzy_chat/rust_bridge/api/formats.dart';
import 'package:fuzzy_chat/rust_bridge/api/health.dart';
import 'package:fuzzy_chat/rust_bridge/api/pairing.dart';
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

  group('pairing (async, two stores)', () {
    late Directory aDir;
    late Directory bDir;
    late CryptoCore a;
    late CryptoCore b;

    Future<CryptoCore> open(Directory dir) async => openStore(
          storeDir: dir.path,
          wrapped: await createStoreKey(password: ''),
          password: '',
        );

    setUp(() async {
      aDir = Directory.systemTemp.createTempSync('fuzzy_crypto_core_a_');
      bDir = Directory.systemTemp.createTempSync('fuzzy_crypto_core_b_');
      a = await open(aDir);
      b = await open(bDir);
    });

    tearDown(() async {
      await a.close();
      await b.close();
      a.dispose();
      b.dispose();
      for (final dir in [aDir, bDir]) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    test('A invites → B accepts → A completes → both connected', () async {
      final invitation = await a.createInvitation(chatId: _chatId);
      expect(invitation, startsWith('Fuzz/'));
      expect(blobTypeOf(text: invitation), BlobType.invitation);
      expect(peekChatId(text: invitation), _chatId);
      expect(await a.chatStatus(chatId: _chatId), ChatStatus.invited);

      final acceptance = await b.acceptInvitation(
        chatId: _chatId,
        invitation: invitation,
      );
      expect(blobTypeOf(text: acceptance), BlobType.acceptance);
      expect(await b.chatStatus(chatId: _chatId), ChatStatus.connected);

      await a.completeHandshake(chatId: _chatId, acceptance: acceptance);
      expect(await a.chatStatus(chatId: _chatId), ChatStatus.connected);

      expect(await a.currentInvitation(chatId: _chatId), invitation);
      expect(await b.currentAcceptance(chatId: _chatId), acceptance);

      // The one-time key is gone: the same acceptance cannot be completed twice.
      await expectLater(
        a.completeHandshake(chatId: _chatId, acceptance: acceptance),
        throwsA(CoreError.invitationAlreadyUsed),
      );
    });

    test('tampered and foreign blobs are CoreError values, no state written',
        () async {
      final invitation = await a.createInvitation(chatId: _chatId);
      final blob =
          base64Url.decode(base64Url.normalize(invitation.substring(5)));
      final tampered = List<int>.of(blob)..[100] ^= 1;

      await expectLater(
        b.acceptInvitation(chatId: _chatId, invitation: _fuzzText(tampered)),
        throwsA(CoreError.invalidSignature),
      );
      await expectLater(
        b.acceptInvitation(
          chatId: '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
          invitation: invitation,
        ),
        throwsA(CoreError.wrongChat),
      );
      await expectLater(
        b.acceptInvitation(chatId: _chatId, invitation: 'Fuzz/RlVaWgEDAd6tvu8'),
        throwsA(CoreError.unsupportedFormat),
      );
      await expectLater(
        b.chatStatus(chatId: _chatId),
        throwsA(CoreError.unknownChat),
      );
    });

    test('text messages round-trip A→B and B→A; a replay throws', () async {
      final invitation = await a.createInvitation(chatId: _chatId);
      final acceptance = await b.acceptInvitation(
        chatId: _chatId,
        invitation: invitation,
      );
      await a.completeHandshake(chatId: _chatId, acceptance: acceptance);

      // A → B.
      final aBlob = await a.encryptText(chatId: _chatId, text: 'hi from a');
      expect(aBlob, startsWith('Fuzz/'));
      expect(blobTypeOf(text: aBlob), BlobType.message);
      expect(await b.decryptText(chatId: _chatId, blob: aBlob), 'hi from a');

      // B → A.
      final bBlob = await b.encryptText(chatId: _chatId, text: 'hi from b');
      expect(await a.decryptText(chatId: _chatId, blob: bBlob), 'hi from b');

      // Re-pasting a consumed blob throws Replay across the FFI.
      await expectLater(
        b.decryptText(chatId: _chatId, blob: aBlob),
        throwsA(CoreError.replay),
      );
    });

    test('safety number is identical on both sides; markVerified round-trips',
        () async {
      // Nothing to compare before the pairing.
      await expectLater(
        a.safetyNumber(chatId: _chatId),
        throwsA(CoreError.unknownChat),
      );

      final invitation = await a.createInvitation(chatId: _chatId);
      final acceptance = await b.acceptInvitation(
        chatId: _chatId,
        invitation: invitation,
      );
      await a.completeHandshake(chatId: _chatId, acceptance: acceptance);

      final onA = await a.safetyNumber(chatId: _chatId);
      final onB = await b.safetyNumber(chatId: _chatId);
      expect(onA, onB);
      expect(onA, matches(RegExp(r'^\d{5}( \d{5}){11}$')));
      expect(onA.replaceAll(' ', ''), hasLength(60));

      expect(await a.isVerified(chatId: _chatId), isFalse);
      await a.markVerified(chatId: _chatId, verified: true);
      expect(await a.isVerified(chatId: _chatId), isTrue);
      expect(await b.isVerified(chatId: _chatId), isFalse);
      await a.markVerified(chatId: _chatId, verified: false);
      expect(await a.isVerified(chatId: _chatId), isFalse);
    });
  });
}
