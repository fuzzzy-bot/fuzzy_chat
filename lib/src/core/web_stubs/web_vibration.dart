/// Web stub for vibration - no-op on web
class WebVibration {
  static Future<bool> hasVibrator() async => false;
  static Future<void> vibrate({int duration = 500, int? amplitude}) async {}
  static Future<void> vibrateWithPattern(List<int> pattern, {List<int>? intensities, int repeat = -1}) async {}
  static Future<void> cancel() async {}
}
