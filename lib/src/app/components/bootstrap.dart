import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';

class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    super.onError(bloc, error, stackTrace);
  }
}

Future<void> bootstrap(FutureOr<Widget> Function() builder) async {
  FlutterError.onError = (details) {
    log('FlutterError: ${details.exceptionAsString()}', stackTrace: details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  try {
    log('bootstrap: calling builder...');
    final widget = await builder();
    log('bootstrap: builder completed, calling runApp...');
    runApp(widget);
    log('bootstrap: runApp called successfully');
  } catch (e, stack) {
    log('bootstrap: CRITICAL ERROR: $e', stackTrace: stack);
    // Show error widget instead of crashing
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Initialization Error',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    stack.toString(),
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                    maxLines: 20,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
