/// Web stub for file drop - no-op on web
class WebFileDrop {
  static bool get isSupported => false;
  static Stream<dynamic>? get dropStream => null;
  static Future<void> init() async {}
}
