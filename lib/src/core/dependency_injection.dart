import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'web_stubs/web_stubs.dart';

class DependencyInjection {
  static Future<void> inject() async {
    log('DI: inject() started');
    late final Directory documentsDirectory;
    late final Directory supportDirectory;

    late final SharedPreferences prefs;

    if (kIsWeb) {
      log('DI: running in web mode');
      try {
        prefs = await SharedPreferences.getInstance();
        log('DI: SharedPreferences initialized');
      } catch (e, stack) {
        log('DI: SharedPreferences FAILED: $e', stackTrace: stack);
        rethrow;
      }
      
      sl.safeRegisterSingleton<PreferencesService>(PreferencesService(prefs));
      log('DI: PreferencesService registered');

      // Web: use stub directories
      final webDocsDir = WebDirectory('/documents');
      final webSupportDir = WebDirectory('/support');

      sl.safeRegisterSingleton<AppDocumentsDirectory>(
        AppDocumentsDirectory(
          directory: Directory(webDocsDir.path),
        ),
      );
      log('DI: AppDocumentsDirectory registered');

      sl.safeRegisterSingleton<AppSupportDirectory>(
        AppSupportDirectory(
          directory: Directory(webSupportDir.path),
        ),
      );
      log('DI: AppSupportDirectory registered');

      // Web: data sources use SharedPreferences internally
      try {
        _registerRepositoriesWeb();
        log('DI: _registerRepositoriesWeb completed');
      } catch (e, stack) {
        log('DI: _registerRepositoriesWeb FAILED: $e', stackTrace: stack);
        rethrow;
      }
      
      try {
        _registerVaultWeb();
        log('DI: _registerVaultWeb completed');
      } catch (e, stack) {
        log('DI: _registerVaultWeb FAILED: $e', stackTrace: stack);
        rethrow;
      }
      
      log('DI: web initialization completed');
      return;
    }

    await Future.wait<void>([
      (() async =>
          documentsDirectory = await getApplicationDocumentsDirectory())(),
      (() async => supportDirectory = await getApplicationSupportDirectory())(),
      (() async => prefs = await SharedPreferences.getInstance())(),
    ]);

    sl.safeRegisterSingleton<PreferencesService>(PreferencesService(prefs));

    sl.safeRegisterSingleton<AppDocumentsDirectory>(
      AppDocumentsDirectory(
        directory: documentsDirectory,
      ),
    );

    sl.safeRegisterSingleton<AppSupportDirectory>(
      AppSupportDirectory(
        directory: supportDirectory,
      ),
    );

    final isar = await Isar.open(
      [
        StoredChatGeneralDataSchema,
        StoredChatPreferencesSchema,
        StoredChatSecurityDataSchema,
        StoredMessageDataSchema,
        StoredUserAuthPreferencesSchema,
        StoredVaultItemSchema,
        StoredVaultGroupSchema,
        StoredVaultMetadataSchema,
      ],
      directory: supportDirectory.path,
    );

    sl.safeRegisterSingleton<Isar>(isar);

    sl.safeRegisterSingleton<FuzzyLinkService>(FuzzyLinkService());

    sl.safeRegisterSingleton<UserAuthPreferencesRepository>(
      UserAuthPreferencesRepository(
          localDataSource: UserAuthPreferencesLocalDataSource(isar: sl.get()),),
    );

    sl.safeRegisterSingleton<ChatAuthRepository>(
      ChatAuthRepository(
        userAuthPreferencesRepository: sl.get<UserAuthPreferencesRepository>(),
      ),
    );

    sl.safeRegisterSingleton<BiometricAuthRepository>(
        BiometricAuthRepository(),);

    sl.safeRegisterSingleton<FuzzyAuthStore>(
      FuzzyAuthStore(
        chatAuthRepository: sl.get<ChatAuthRepository>(),
        biometricAuthRepository: sl.get<BiometricAuthRepository>(),
      ),
    );

    sl.safeRegisterSingleton<KeyStorageRepository>(KeyStorageRepository());
    await sl.get<KeyStorageRepository>().recoverStagedMigration();

    sl.safeRegisterSingleton<ChatGeneralDataListRepository>(
      ChatGeneralDataListRepository(
          localDataSource: ChatGeneralDataLocalDataSource(isar: sl.get()),),
    );

    sl.safeRegisterSingleton<MessageDataRepository>(
      MessageDataRepository(
          localDataSource: MessageDataLocalDataSource(isar: sl.get()),),
    );

    sl.safeRegisterSingleton<FuzzyLinkHandler>(
      FuzzyLinkHandler(
        linkService: sl.get<FuzzyLinkService>(),
        chatRepository: sl.get<ChatGeneralDataListRepository>(),
        authStore: sl.get<FuzzyAuthStore>(),
      ),
    );

    // Vault Dependencies
    sl.safeRegisterSingleton<PasswordStrengthService>(
        PasswordStrengthService(),);

    sl.safeRegisterSingleton<VaultFileDataSource>(
      VaultFileDataSource(
          vaultDirectoryPath: sl.get<AppDocumentsDirectory>().directory.path,),
    );

    await sl.get<VaultFileDataSource>().recoverStagedChangesIfNeeded();

    sl.safeRegisterSingleton<VaultItemLocalDataSource>(
      VaultItemLocalDataSource(isar: sl.get<Isar>()),
    );

    sl.safeRegisterSingleton<VaultGroupLocalDataSource>(
      VaultGroupLocalDataSource(isar: sl.get<Isar>()),
    );

    sl.safeRegisterSingleton<VaultCryptoRepository>(
      VaultCryptoRepository(
        passwordStrengthService: sl.get<PasswordStrengthService>(),
      ),
    );

    sl.safeRegisterSingleton<VaultRepository>(
      VaultRepository(
        itemDataSource: sl.get<VaultItemLocalDataSource>(),
        groupDataSource: sl.get<VaultGroupLocalDataSource>(),
        fileDataSource: sl.get<VaultFileDataSource>(),
        cryptoRepository: sl.get<VaultCryptoRepository>(),
      ),
    );

    sl.safeRegisterSingleton<VaultExportRepository>(
      VaultExportRepository(
        fileDataSource: sl.get<VaultFileDataSource>(),
        itemDataSource: sl.get<VaultItemLocalDataSource>(),
        groupDataSource: sl.get<VaultGroupLocalDataSource>(),
      ),
    );

    // Vault Cubits
    sl.safeRegisterSingleton<VaultAuthCubit>(
      VaultAuthCubit(
        vaultRepository: sl.get<VaultRepository>(),
        cryptoRepository: sl.get<VaultCryptoRepository>(),
        biometricAuthRepository: sl.get<BiometricAuthRepository>(),
      ),
    );

    sl.registerFactory<VaultItemsCubit>(
      () => VaultItemsCubit(
        vaultRepository: sl.get<VaultRepository>(),
      ),
    );

    sl.registerFactory<VaultGroupsCubit>(
      () => VaultGroupsCubit(
        vaultRepository: sl.get<VaultRepository>(),
      ),
    );

    sl.registerFactory<VaultSearchCubit>(
      () => VaultSearchCubit(
        vaultRepository: sl.get<VaultRepository>(),
      ),
    );

    sl.registerFactory<VaultExportCubit>(
      () => VaultExportCubit(
        exportRepository: sl.get<VaultExportRepository>(),
      ),
    );
  }

  static void _registerRepositoriesWeb() {
    log('DI: _registerRepositoriesWeb started');
    
    // Web: stub services that don't need real implementations
    sl.safeRegisterSingleton<FuzzyLinkService>(FuzzyLinkService());
    log('DI: FuzzyLinkService registered');

    // Web: use real auth repositories with web storage
    sl.safeRegisterSingleton<UserAuthPreferencesRepository>(
      UserAuthPreferencesRepository(
        localDataSource: UserAuthPreferencesLocalDataSource(),
      ),
    );
    log('DI: UserAuthPreferencesRepository registered');

    sl.safeRegisterSingleton<ChatAuthRepository>(
      ChatAuthRepository(
        userAuthPreferencesRepository: sl.get<UserAuthPreferencesRepository>(),
      ),
    );
    log('DI: ChatAuthRepository registered');

    sl.safeRegisterSingleton<BiometricAuthRepository>(
      BiometricAuthRepository(),
    );
    log('DI: BiometricAuthRepository registered');

    sl.safeRegisterSingleton<FuzzyAuthStore>(
      FuzzyAuthStore(
        chatAuthRepository: sl.get<ChatAuthRepository>(),
        biometricAuthRepository: sl.get<BiometricAuthRepository>(),
      ),
    );
    log('DI: FuzzyAuthStore registered');

    sl.safeRegisterSingleton<KeyStorageRepository>(KeyStorageRepository());
    log('DI: KeyStorageRepository registered');

    // Web: use real data sources with SharedPreferences
    sl.safeRegisterSingleton<ChatGeneralDataListRepository>(
      ChatGeneralDataListRepository(
        localDataSource: ChatGeneralDataLocalDataSource(),
      ),
    );
    log('DI: ChatGeneralDataListRepository registered');

    sl.safeRegisterSingleton<MessageDataRepository>(
      MessageDataRepository(
        localDataSource: MessageDataLocalDataSource(),
      ),
    );
    log('DI: MessageDataRepository registered');

    sl.safeRegisterSingleton<FuzzyLinkHandler>(
      FuzzyLinkHandler(
        linkService: sl.get<FuzzyLinkService>(),
        chatRepository: sl.get<ChatGeneralDataListRepository>(),
        authStore: sl.get<FuzzyAuthStore>(),
      ),
    );
    log('DI: FuzzyLinkHandler registered');
    log('DI: _registerRepositoriesWeb completed');
  }

  static void _registerVaultWeb() {
    log('DI: _registerVaultWeb started');
    
    // Web: stub vault dependencies
    sl.safeRegisterSingleton<PasswordStrengthService>(
      PasswordStrengthService(),
    );
    log('DI: PasswordStrengthService registered');

    sl.safeRegisterSingleton<VaultFileDataSource>(
      VaultFileDataSource(
        vaultDirectoryPath: sl.get<AppDocumentsDirectory>().directory.path,
      ),
    );
    log('DI: VaultFileDataSource registered');

    // Web: use real data sources with SharedPreferences
    sl.safeRegisterSingleton<VaultItemLocalDataSource>(
      VaultItemLocalDataSource(),
    );
    log('DI: VaultItemLocalDataSource registered');

    sl.safeRegisterSingleton<VaultGroupLocalDataSource>(
      VaultGroupLocalDataSource(),
    );
    log('DI: VaultGroupLocalDataSource registered');

    sl.safeRegisterSingleton<VaultCryptoRepository>(
      VaultCryptoRepository(
        passwordStrengthService: sl.get<PasswordStrengthService>(),
      ),
    );
    log('DI: VaultCryptoRepository registered');

    sl.safeRegisterSingleton<VaultRepository>(
      VaultRepository(
        itemDataSource: sl.get<VaultItemLocalDataSource>(),
        groupDataSource: sl.get<VaultGroupLocalDataSource>(),
        fileDataSource: sl.get<VaultFileDataSource>(),
        cryptoRepository: sl.get<VaultCryptoRepository>(),
      ),
    );
    log('DI: VaultRepository registered');

    sl.safeRegisterSingleton<VaultExportRepository>(
      VaultExportRepository(
        fileDataSource: sl.get<VaultFileDataSource>(),
        itemDataSource: sl.get<VaultItemLocalDataSource>(),
        groupDataSource: sl.get<VaultGroupLocalDataSource>(),
      ),
    );
    log('DI: VaultExportRepository registered');

    // Vault Cubits
    sl.safeRegisterSingleton<VaultAuthCubit>(
      VaultAuthCubit(
        vaultRepository: sl.get<VaultRepository>(),
        cryptoRepository: sl.get<VaultCryptoRepository>(),
        biometricAuthRepository: sl.get<BiometricAuthRepository>(),
      ),
    );
    log('DI: VaultAuthCubit registered');

    sl.registerFactory<VaultItemsCubit>(
      () => VaultItemsCubit(
        vaultRepository: sl.get<VaultRepository>(),
      ),
    );
    log('DI: VaultItemsCubit factory registered');

    sl.registerFactory<VaultGroupsCubit>(
      () => VaultGroupsCubit(
        vaultRepository: sl.get<VaultRepository>(),
      ),
    );
    log('DI: VaultGroupsCubit factory registered');

    sl.registerFactory<VaultSearchCubit>(
      () => VaultSearchCubit(
        vaultRepository: sl.get<VaultRepository>(),
      ),
    );
    log('DI: VaultSearchCubit factory registered');

    sl.registerFactory<VaultExportCubit>(
      () => VaultExportCubit(
        exportRepository: sl.get<VaultExportRepository>(),
      ),
    );
    log('DI: VaultExportCubit factory registered');
    log('DI: _registerVaultWeb completed');
  }
}
