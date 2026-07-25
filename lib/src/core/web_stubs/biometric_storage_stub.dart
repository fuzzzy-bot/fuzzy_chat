// Stub for biometric_storage on web
class BiometricStorage {
  factory BiometricStorage() => _instance ??= BiometricStorage._();
  BiometricStorage._();

  static BiometricStorage? _instance;

  Future<CanAuthenticateResponse> canAuthenticate() async => CanAuthenticateResponse.error;

  Future<BiometricStorageFile> getStorage(String name, {dynamic options, dynamic promptInfo}) async {
    throw UnsupportedError('Biometric storage is not supported on web');
  }
}

class BiometricStorageFile {
  Future<String?> read() async => null;
  Future<void> write(String content) async {}
  Future<void> delete() async {}
}

enum CanAuthenticateResponse {
  success,
  error,
}

class StorageFileInitOptions {
  final int authenticationValidityDurationSeconds;
  final bool androidBiometricOnly;
  final bool darwinBiometricOnly;

  StorageFileInitOptions({
    required this.authenticationValidityDurationSeconds,
    required this.androidBiometricOnly,
    required this.darwinBiometricOnly,
  });
}

class PromptInfo {
  final IosPromptInfo? iosPromptInfo;
  final AndroidPromptInfo? androidPromptInfo;

  PromptInfo({this.iosPromptInfo, this.androidPromptInfo});
}

class IosPromptInfo {
  final String? saveTitle;
  final String? accessTitle;

  IosPromptInfo({this.saveTitle, this.accessTitle});
}

class AndroidPromptInfo {
  final String? title;
  final String? subtitle;

  AndroidPromptInfo({this.title, this.subtitle});
}
