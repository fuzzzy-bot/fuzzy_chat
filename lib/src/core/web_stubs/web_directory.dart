/// Web stub for Directory - provides web-safe paths
class WebDirectory {
  final String path;
  WebDirectory(this.path);

  Future<bool> exists() async => true;
  Future<WebDirectory> create({bool recursive = false}) async => this;
}

/// Web stub for File
class WebFile {
  final String path;
  WebFile(this.path);

  Future<bool> exists() async => false;
  Future<String> readAsString() async => '';
  Future<List<int>> readAsBytes() async => [];
  Future<WebFile> writeAsString(String contents) async => this;
  Future<WebFile> writeAsBytes(List<int> bytes) async => this;
}

/// Web-safe path operations
class WebPath {
  static String join(String part1, String part2, [String? part3]) {
    if (part3 != null) return '$part1/$part2/$part3';
    return '$part1/$part2';
  }

  static String basename(String path) {
    final parts = path.split('/');
    return parts.last;
  }

  static String dirname(String path) {
    final parts = path.split('/');
    if (parts.length <= 1) return '.';
    return parts.sublist(0, parts.length - 1).join('/');
  }
}
