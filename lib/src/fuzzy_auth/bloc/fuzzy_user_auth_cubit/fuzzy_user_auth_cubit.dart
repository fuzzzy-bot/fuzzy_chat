import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fuzzy_chat/lib.dart';

part 'fuzzy_user_auth_state.dart';

class FuzzyUserAuthCubit extends Cubit<FuzzyUserAuthState> {
  final AuthDataRepository _authDataRepository;

  FuzzyUserAuthCubit({
    required AuthDataRepository authDataRepository,
  })  : _authDataRepository = authDataRepository,
        super(const FuzzyUserAuthState());

  Future<void> getAuthData() async {
    emit(state.copyWith(status: StateStatus.loading));
    try {
      // TODO: Implement the logic to fetch data using the repository
      final items = await _authDataRepository.getAllAuthDatas();
      emit(
        state.copyWith(
          status: StateStatus.success,
          items: items,
        ),
      );
    } catch (e) {
      // TODO: Implement proper failure handling
      emit(
        state.copyWith(
          status: StateStatus.failed,
          failure: DefaultFailure(message: e.toString()),
        ),
      );
    }
  }
}
