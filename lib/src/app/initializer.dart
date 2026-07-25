import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:fuzzy_chat/src/core/dependency_injection.dart';

class Initializer {
  static Future<void> preAppInit() async {
    log('Initializer: ensuring WidgetsFlutterBinding...');
    WidgetsFlutterBinding.ensureInitialized();
    log('Initializer: WidgetsFlutterBinding ready');

    try {
      log('Initializer: starting DependencyInjection...');
      await DependencyInjection.inject();
      log('Initializer: DependencyInjection completed successfully');
    } catch (e, stack) {
      log('Initializer: DependencyInjection FAILED: $e', stackTrace: stack);
      rethrow;
    }
  }
}
