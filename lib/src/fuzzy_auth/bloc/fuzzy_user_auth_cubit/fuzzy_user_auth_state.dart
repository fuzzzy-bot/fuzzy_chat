part of 'fuzzy_user_auth_cubit.dart';

class FuzzyUserAuthState {
  final StateStatus status;
  final List<AuthData> items;
  final DefaultFailure? failure;

  const FuzzyUserAuthState({
    this.status = StateStatus.initial,
    this.items = const [],
    this.failure,
  });

  FuzzyUserAuthState copyWith({
    StateStatus? status,
    List<AuthData>? items,
    DefaultFailure? failure,
  }) {
    return FuzzyUserAuthState(
      status: status ?? this.status,
      items: items ?? this.items,
      failure: failure ?? this.failure,
    );
  }
}
