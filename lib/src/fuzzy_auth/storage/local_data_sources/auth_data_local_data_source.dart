import 'package:fuzzy_chat/lib.dart';
import 'package:isar/isar.dart';

class AuthDataLocalDataSource {
  final Isar isar;

  AuthDataLocalDataSource({required this.isar});

  Future<List<StoredAuthData>> getAll() async {
    return await isar.storedAuthDatas.where().findAll();
  }

  Future<StoredAuthData?> getByUid(String uid) async {
    return await isar.storedAuthDatas.filter().uidEqualTo(uid).findFirst();
  }

  Future<void> addOrUpdate(AuthData model) async {
    // TODO: Implement the mapping from your clean model to the stored model.
    final storedModel = StoredAuthData()
      ..uid = model.uid
      ..lastUpdated = DateTime.now();
    // ..name = model.name;

    await isar.writeTxn(() async {
      await isar.storedAuthDatas.put(storedModel);
    });
  }

  Future<void> delete(String uid) async {
    await isar.writeTxn(() async {
      await isar.storedAuthDatas.filter().uidEqualTo(uid).deleteAll();
    });
  }
}
