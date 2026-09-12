import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
}
