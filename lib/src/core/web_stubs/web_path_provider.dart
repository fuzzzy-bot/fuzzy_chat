/// Web stub for path_provider - returns web-safe paths
class WebPathProvider {
  static Future<String> getApplicationDocumentsDirectory() async {
    return '/documents';
  }

  static Future<String> getApplicationSupportDirectory() async {
    return '/support';
  }

  static Future<String> getTemporaryDirectory() async {
    return '/tmp';
  }

  static Future<String> getDownloadsDirectory() async {
    return '/downloads';
  }
}
