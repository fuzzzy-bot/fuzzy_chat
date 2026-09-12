import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUserAuthPreferencesRepository extends Mock
    implements UserAuthPreferencesRepository {}

class MockCryptoStoreKeyRepository extends Mock
    implements CryptoStoreKeyRepository {}

class MockCryptoCoreService extends Mock implements CryptoCoreService {}

class MockBiometricAuthRepository extends Mock
    implements BiometricAuthRepository {}

void main() {
  late MockUserAuthPreferencesRepository mockPrefsRepo;
  late MockCryptoStoreKeyRepository mockStoreKeyRepo;
  late MockCryptoCoreService mockService;
  late MockBiometricAuthRepository mockBiometricRepo;
  late ChatAuthRepository chatAuthRepository;

  final wrapped = Uint8List.fromList(List.filled(103, 0x10));

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockPrefsRepo = MockUserAuthPreferencesRepository();
    mockStoreKeyRepo = MockCryptoStoreKeyRepository();
    mockService = MockCryptoCoreService();
    mockBiometricRepo = MockBiometricAuthRepository();

    when(() => mockStoreKeyRepo.read()).thenAnswer((_) async => wrapped);
    when(() => mockService.close()).thenAnswer((_) async {});

    chatAuthRepository = ChatAuthRepository(
      userAuthPreferencesRepository: mockPrefsRepo,
      cryptoStoreKeyRepository: mockStoreKeyRepo,
      cryptoCoreService: mockService,
    );
  });

  FuzzyAuthStore buildStore() => FuzzyAuthStore(
        chatAuthRepository: chatAuthRepository,
        biometricAuthRepository: mockBiometricRepo,
        cryptoStoreKeyRepository: mockStoreKeyRepo,
        cryptoCoreService: mockService,
      );

  // -----------------------------------------------------------------------
  // unlock
  // -----------------------------------------------------------------------
  group('unlock', () {
    blocTest<FuzzyAuthStore, FuzzyAuthState>(
      'emits [unlocking, authenticated] when the service opens the store',
      setUp: () {
        when(() => mockService.openStore(wrapped: wrapped, password: 'pw'))
            .thenAnswer((_) async => const CryptoCoreSuccess(null));
      },
      build: buildStore,
      act: (store) => store.unlock('pw'),
      expect: () => [
        isA<FuzzyAuthState>()
            .having((s) => s.status, 'status', AuthStateStatus.unlocking),
        isA<FuzzyAuthState>()
            .having((s) => s.status, 'status', AuthStateStatus.authenticated)
            .having((s) => s.authData.password, 'password', 'pw')
            .having((s) => s.verificationFailed, 'verificationFailed', false),
      ],
      verify: (_) {
        verify(() => mockService.openStore(wrapped: wrapped, password: 'pw'))
            .called(1);
      },
    );

    blocTest<FuzzyAuthStore, FuzzyAuthState>(
      'emits [unlocking, locked + verificationFailed] on wrongPassword',
      setUp: () {
        when(() => mockService.openStore(wrapped: wrapped, password: 'bad'))
            .thenAnswer(
          (_) async =>
              const CryptoCoreFailure(CryptoCoreFailureType.wrongPassword),
        );
      },
      build: buildStore,
      act: (store) => store.unlock('bad'),
      expect: () => [
        isA<FuzzyAuthState>()
            .having((s) => s.status, 'status', AuthStateStatus.unlocking),
        isA<FuzzyAuthState>()
            .having((s) => s.status, 'status', AuthStateStatus.locked)
            .having((s) => s.verificationFailed, 'verificationFailed', true)
            .having((s) => s.authData.password, 'password', ''),
      ],
    );

    blocTest<FuzzyAuthStore, FuzzyAuthState>(
      'never calls the service when no store key exists',
      setUp: () {
        when(() => mockStoreKeyRepo.read()).thenAnswer((_) async => null);
      },
      build: buildStore,
      act: (store) => store.unlock('pw'),
      expect: () => [
        isA<FuzzyAuthState>()
            .having((s) => s.status, 'status', AuthStateStatus.unlocking),
        isA<FuzzyAuthState>()
            .having((s) => s.status, 'status', AuthStateStatus.locked)
            .having((s) => s.verificationFailed, 'verificationFailed', true),
      ],
      verify: (_) {
        verifyNever(
          () => mockService.openStore(
            wrapped: any(named: 'wrapped'),
            password: any(named: 'password'),
          ),
        );
      },
    );
  });

  // -----------------------------------------------------------------------
  // checkAuthStatus
  // -----------------------------------------------------------------------
  group('checkAuthStatus', () {
    blocTest<FuzzyAuthStore, FuzzyAuthState>(
      'with the lock disabled ensures the store key and opens the store '
      'under the empty password',
      setUp: () {
        when(() => mockPrefsRepo.getUserAuthPreferences())
            .thenAnswer((_) async => null);
        when(() => mockStoreKeyRepo.ensureStoreKey(''))
            .thenAnswer((_) async => const CryptoCoreSuccess(null));
        when(() => mockService.openStore(wrapped: wrapped, password: ''))
            .thenAnswer((_) async => const CryptoCoreSuccess(null));
      },
      build: buildStore,
      act: (store) => store.checkAuthStatus(),
      expect: () => [
        isA<FuzzyAuthState>()
            .having((s) => s.status, 'status', AuthStateStatus.noAuthRequired)
            .having((s) => s.biometricEnabled, 'biometricEnabled', false),
      ],
      verify: (_) {
        verifyInOrder([
          () => mockStoreKeyRepo.ensureStoreKey(''),
          () => mockService.openStore(wrapped: wrapped, password: ''),
        ]);
      },
    );

    blocTest<FuzzyAuthStore, FuzzyAuthState>(
      'with the lock enabled emits locked and leaves the store closed',
      setUp: () {
        when(() => mockPrefsRepo.getUserAuthPreferences()).thenAnswer(
          (_) async => UserAuthPreferences(isAuthenticationOnceEnabled: true),
        );
        when(() => mockBiometricRepo.isEnabled(BiometricScope.chat))
            .thenAnswer((_) async => true);
      },
      build: buildStore,
      act: (store) => store.checkAuthStatus(),
      expect: () => [
        isA<FuzzyAuthState>()
            .having((s) => s.status, 'status', AuthStateStatus.locked)
            .having((s) => s.biometricEnabled, 'biometricEnabled', true),
      ],
      verify: (_) {
        verifyNever(() => mockStoreKeyRepo.ensureStoreKey(any()));
        verifyNever(
          () => mockService.openStore(
            wrapped: any(named: 'wrapped'),
            password: any(named: 'password'),
          ),
        );
      },
    );
  });

  // -----------------------------------------------------------------------
  // lock
  // -----------------------------------------------------------------------
  group('lock', () {
    blocTest<FuzzyAuthStore, FuzzyAuthState>(
      'closes the store and emits locked with an empty password',
      setUp: () {
        when(() => mockService.openStore(wrapped: wrapped, password: 'pw'))
            .thenAnswer((_) async => const CryptoCoreSuccess(null));
      },
      build: buildStore,
      act: (store) async {
        await store.unlock('pw');
        await store.lock();
      },
      skip: 2,
      expect: () => [
        isA<FuzzyAuthState>()
            .having((s) => s.status, 'status', AuthStateStatus.locked)
            .having((s) => s.authData.password, 'password', ''),
      ],
      verify: (_) {
        verify(() => mockService.close()).called(1);
      },
    );
  });
}
