import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fuzzy_chat/src/app/app.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  // QA instrumentation (uncommitted): Marionette must be the ONLY binding, and it
  // must be installed before anything else calls WidgetsFlutterBinding.ensureInitialized()
  // (Initializer.preAppInit does — that call becomes a no-op once a binding exists).
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  bootstrap(App.runner);
}
