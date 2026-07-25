/// Web stub for permission_handler - always returns granted
class WebPermissionHandler {
  static Future<PermissionStatus> request(Permission permission) async {
    return PermissionStatus.granted;
  }

  static Future<PermissionStatus> status(Permission permission) async {
    return PermissionStatus.granted;
  }

  static Future<bool> openAppSettings() async => false;
}

enum Permission {
  storage,
  photos,
  camera,
  microphone,
  location,
  notification,
  contacts,
  calendar,
  sms,
  phone,
  mediaLibrary,
  sensors,
  unknown,
}

enum PermissionStatus {
  granted,
  denied,
  restricted,
  limited,
  permanentlyDenied,
}
