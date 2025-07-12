import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fuzzy_chat/lib.dart';

import 'widgets/widgets.dart';

class FuzzyUserAuthPage extends StatelessWidget {
  const FuzzyUserAuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FuzzyUserAuthCubit>(
      create: (context) => FuzzyUserAuthCubit(
        // TODO: Ensure repository is available via your service locator (like sl.get())
        authDataRepository: sl.get<AuthDataRepository>(),
      )..getAuthData(),
      child: const _ProvidedFuzzyUserAuthPage(),
    );
  }
}

class _ProvidedFuzzyUserAuthPage extends StatelessWidget {
  const _ProvidedFuzzyUserAuthPage();

  @override
  Widget build(BuildContext context) {
    // TODO: Replace with your actual UI components like FuzzyScaffold
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuzzy User Auth'),
      ),
      body: BlocBuilder<FuzzyUserAuthCubit, FuzzyUserAuthState>(
        builder: (context, state) {
          return StatusBuilder.buildByStatus(
            status: state.status,
            onInitial: DefaultLoadingWidget.new,
            onLoading: DefaultLoadingWidget.new,
            onSuccess: () {
              if (state.items.isEmpty) {
                return const FuzzyUserAuthEmptyContent();
              }
              return FuzzyUserAuthLoadedContent(
                items: state.items,
              );
            },
            onFailure: () => Center(
              child: Text(
                'Error: ${state.failure?.message ?? 'Unknown error'}',
              ),
            ),
          );
        },
      ),
    );
  }
}
