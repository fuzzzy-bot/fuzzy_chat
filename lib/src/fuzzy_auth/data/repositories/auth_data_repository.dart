import '../../storage/local_data_sources/auth_data_local_data_source.dart';
import '../models/auth_data.dart';

class AuthDataRepository {
  final AuthDataLocalDataSource localDataSource;

  AuthDataRepository({required this.localDataSource});

  Future<List<AuthData>> getAllAuthDatas() async {
    final storedItems = await localDataSource.getAll();
    return storedItems.map(AuthData.fromStored).toList();
  }

  Future<AuthData?> getAuthDataByUid(String uid) async {
    final storedItem = await localDataSource.getByUid(uid);
    if (storedItem != null) {
      return AuthData.fromStored(storedItem);
    }
    return null;
  }

  Future<void> addOrUpdateAuthData(AuthData item) async {
    await localDataSource.addOrUpdate(item);
  }

  Future<void> deleteAuthData(String uid) async {
    await localDataSource.delete(uid);
  }
}
