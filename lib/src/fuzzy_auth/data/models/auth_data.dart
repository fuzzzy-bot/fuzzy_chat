import '../../storage/storage_models/stored_auth_data.dart';

class AuthData {
  final String uid;
  // TODO: Add the properties for your model here.
  // For example:
  // final String name;
  // final bool isEnabled;
  final DateTime lastUpdated;

  AuthData({
    required this.uid,
    // required this.name,
    // required this.isEnabled,
    required this.lastUpdated,
  });

  factory AuthData.fromStored(StoredAuthData stored) {
    return AuthData(
      uid: stored.uid,
      // TODO: Map properties from stored model.
      // name: stored.name,
      // isEnabled: stored.isEnabled,
      lastUpdated: stored.lastUpdated,
    );
  }

  AuthData copyWith({
    String? uid,
    // String? name,
    // bool? isEnabled,
    DateTime? lastUpdated,
  }) {
    return AuthData(
      uid: uid ?? this.uid,
      // name: name ?? this.name,
      // isEnabled: isEnabled ?? this.isEnabled,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
