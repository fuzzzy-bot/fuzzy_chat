import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/crypto_core_test_init.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUserAuthPreferencesRepository extends Mock
    implements UserAuthPreferencesRepository {}

class MockKeyStorageRepository extends Mock implements KeyStorageRepository {}

Uint8List? _blobOf(CryptoCoreResponse<Uint8List?> readRes) =>
    (readRes as CryptoCoreSuccess<Uint8List?>).data;

void main() {
  setUpAll(initCryptoCoreForTests);

  late Directory storeDir;
  late CryptoCoreService service;
  late CryptoStoreKeyRepository storeKeyRepository;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storeDir = Directory.systemTemp.createTempSync('fuzzy_crypto_core_');
    service = CryptoCoreService(storeDirectoryPath: storeDir.path);
    storeKeyRepository = CryptoStoreKeyRepository(cryptoCoreService: service);
  });

  tearDown(() async {
    await service.close();
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  group('CryptoCoreService + CryptoStoreKeyRepository (real library)', () {
    test(
        'ensureStoreKey → openStore → rewrap → open with new password → '
        'old password rejected → close', () async {
      expect(
        await storeKeyRepository.ensureStoreKey('a'),
        isA<CryptoCoreSuccess<void>>(),
      );
      final wrapped = _blobOf(await storeKeyRepository.read());
      expect(wrapped, isNotNull);
      expect(wrapped!.length, 103, reason: '0x10 blob: 6 + 16 + 9 + 24 + 48');

      // A second call is a no-op: the same blob stays in place.
      expect(
        await storeKeyRepository.ensureStoreKey('other'),
        isA<CryptoCoreSuccess<void>>(),
      );
      expect(_blobOf(await storeKeyRepository.read()), wrapped);

      expect(
        await service.openStore(wrapped: wrapped, password: 'a'),
        isA<CryptoCoreSuccess<void>>(),
      );
      expect(service.isOpen, isTrue);
      expect(
        Directory('${storeDir.path}/fuzzy_crypto_store').existsSync(),
        isTrue,
      );

      expect(
        await storeKeyRepository.rewrap(oldPassword: 'a', newPassword: 'b'),
        isA<CryptoCoreSuccess<void>>(),
      );
      final rewrapped = _blobOf(await storeKeyRepository.read());
      expect(rewrapped, isNot(wrapped));

      expect(
        await service.openStore(wrapped: rewrapped!, password: 'b'),
        isA<CryptoCoreSuccess<void>>(),
      );
      expect(service.isOpen, isTrue);

      final wrongRes =
          await service.openStore(wrapped: rewrapped, password: 'a');
      expect(wrongRes, isA<CryptoCoreFailure<void>>());
      expect(
        (wrongRes as CryptoCoreFailure<void>).type,
        CryptoCoreFailureType.wrongPassword,
      );
      expect(
        service.isOpen,
        isTrue,
        reason: 'a wrong password keeps the store open',
      );

      await service.close();
      expect(service.isOpen, isFalse);
      await service.close();
      expect(service.isOpen, isFalse, reason: 'close is idempotent');
    });

    test('rewrap with the wrong old password changes nothing', () async {
      await storeKeyRepository.ensureStoreKey('a');
      final wrapped = _blobOf(await storeKeyRepository.read());

      final rewrapRes =
          await storeKeyRepository.rewrap(oldPassword: 'x', newPassword: 'b');
      expect(rewrapRes, isA<CryptoCoreFailure<void>>());
      expect(
        (rewrapRes as CryptoCoreFailure<void>).type,
        CryptoCoreFailureType.wrongPassword,
      );
      expect(_blobOf(await storeKeyRepository.read()), wrapped);
    });

    test('rewrap without a store key is internal', () async {
      final rewrapRes =
          await storeKeyRepository.rewrap(oldPassword: '', newPassword: 'b');
      expect(rewrapRes, isA<CryptoCoreFailure<void>>());
      expect(
        (rewrapRes as CryptoCoreFailure<void>).type,
        CryptoCoreFailureType.internal,
      );
    });

    test('concurrent createStoreKey calls queue and all succeed', () async {
      final results = await Future.wait([
        service.createStoreKey('a'),
        service.createStoreKey('b'),
        service.createStoreKey('c'),
      ]);
      expect(results, everyElement(isA<CryptoCoreSuccess<Uint8List>>()));
      final blobs = results
          .map((res) => (res as CryptoCoreSuccess<Uint8List>).data)
          .toList();
      expect(blobs.toSet().length, 3);
    });
  });

  group('ChatAuthRepository change-password round trip (real library)', () {
    late MockUserAuthPreferencesRepository userAuthPreferencesRepository;
    late MockKeyStorageRepository keyStorageRepository;
    late ChatAuthRepository chatAuthRepository;

    setUp(() {
      userAuthPreferencesRepository = MockUserAuthPreferencesRepository();
      keyStorageRepository = MockKeyStorageRepository();
      when(() => userAuthPreferencesRepository.updateUserAuthPreferences(any()))
          .thenAnswer((_) async {});
      when(
        () => keyStorageRepository.reencryptAllKeys(
          chatIds: any(named: 'chatIds'),
          oldPassword: any(named: 'oldPassword'),
          newPassword: any(named: 'newPassword'),
        ),
      ).thenAnswer((_) async {});
      chatAuthRepository = ChatAuthRepository(
        userAuthPreferencesRepository: userAuthPreferencesRepository,
        cryptoStoreKeyRepository: storeKeyRepository,
        cryptoCoreService: service,
      );
    });

    setUpAll(() {
      registerFallbackValue(
        UserAuthPreferences(isAuthenticationOnceEnabled: false),
      );
    });

    test('setup → verify → change → verify new → old rejected → disable',
        () async {
      // Lock disabled: the key is wrapped under '' and the store opens with it.
      await storeKeyRepository.ensureStoreKey('');
      expect(await chatAuthRepository.verifyPassword(''), isTrue);

      expect(await chatAuthRepository.setupPassword('first'), isTrue);
      expect(await chatAuthRepository.verifyPassword('wrong'), isFalse);
      expect(service.isOpen, isTrue);
      expect(await chatAuthRepository.verifyPassword('first'), isTrue);

      expect(
        await chatAuthRepository.changePassword(
          oldPassword: 'wrong',
          newPassword: 'second',
          chatIds: const [],
          keyStorageRepository: keyStorageRepository,
        ),
        isFalse,
      );
      verifyNever(
        () => keyStorageRepository.reencryptAllKeys(
          chatIds: any(named: 'chatIds'),
          oldPassword: any(named: 'oldPassword'),
          newPassword: any(named: 'newPassword'),
        ),
      );

      expect(
        await chatAuthRepository.changePassword(
          oldPassword: 'first',
          newPassword: 'second',
          chatIds: const ['chat-1'],
          keyStorageRepository: keyStorageRepository,
        ),
        isTrue,
      );
      verify(
        () => keyStorageRepository.reencryptAllKeys(
          chatIds: const ['chat-1'],
          oldPassword: 'first',
          newPassword: 'second',
        ),
      ).called(1);

      expect(await chatAuthRepository.verifyPassword('second'), isTrue);
      expect(await chatAuthRepository.verifyPassword('first'), isFalse);

      expect(await chatAuthRepository.disableAuth('second'), isTrue);
      expect(await chatAuthRepository.verifyPassword(''), isTrue);
      expect(await chatAuthRepository.verifyPassword('second'), isFalse);
    });

    test('verifyPassword without a store key is false', () async {
      expect(await chatAuthRepository.verifyPassword('any'), isFalse);
      expect(service.isOpen, isFalse);
    });
  });
}
