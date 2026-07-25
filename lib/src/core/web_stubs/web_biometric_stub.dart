/// Web stub for biometric authentication - always returns false
class WebBiometricStub {
  Future<bool> get canAuthenticate async => false;

  Future<bool> authenticate({
    required String localizedReason,
    bool useErrorDialogs = true,
    bool stickyAuth = false,
    bool sensitiveTransaction = true,
  }) async {
    return false;
  }

  Future<bool> store({
    required String key,
    required String value,
    bool useErrorDialogs = true,
    bool stickyAuth = false,
    bool sensitiveTransaction = true,
  }) async {
    return false;
  }

  Future<String?> read({
    required String key,
    bool useErrorDialogs = true,
    bool stickyAuth = false,
    bool sensitiveTransaction = true,
  }) async {
    return null;
  }

  Future<bool> delete({
    required String key,
    bool useErrorDialogs = true,
    bool stickyAuth = false,
    bool sensitiveTransaction = true,
  }) async {
    return false;
  }
}
