import 'package:flutter/foundation.dart';
import 'package:fuzzy_chat/src/app/app.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  if (kDebugMode) MarionetteBinding.ensureInitialized();
  bootstrap(App.runner);
}
