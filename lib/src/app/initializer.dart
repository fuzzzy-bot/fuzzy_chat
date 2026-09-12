import 'package:flutter/material.dart';
import 'package:fuzzy_chat/rust_bridge/frb_generated.dart';
import 'package:fuzzy_chat/src/core/dependency_injection.dart';

class Initializer {
  static Future<void> preAppInit() async {
    WidgetsFlutterBinding.ensureInitialized();

    await FuzzyCryptoCoreLib.init();
    await DependencyInjection.inject();
  }
}
