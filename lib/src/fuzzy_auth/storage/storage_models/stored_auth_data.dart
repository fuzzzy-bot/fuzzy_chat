import 'package:isar/isar.dart';

part 'stored_auth_data.g.dart';

// TODO: Run 'flutter pub run build_runner build' to generate the .g.dart file

@Collection()
class StoredAuthData {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String uid;

  // TODO: Add the properties for your model here.
  // For example:
  // late String name;
  // late bool isEnabled;

  late DateTime lastUpdated;
}
