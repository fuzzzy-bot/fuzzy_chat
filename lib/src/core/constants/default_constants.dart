// The analyzer sees no `--flavor`, so it reads the macOS options as defaults.
// ignore_for_file: avoid_redundant_argument_values, use_named_constants

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const fuzzIdentificator = 'Fuzz/';
const fuzzedFileIdentificator = 'fuzz';

final fuzzVersionInfo = Uint8List.fromList(<int>[
  90,
  110,
  86,
  54,
  101,
  108,
  57,
  50,
  77,
  81,
  61,
  61,
]);

/// Development builds are unsigned on macOS, so they use the login keychain
/// instead of the data-protection keychain (DECISIONS 2026-09-12 / D-3);
/// revert to `MacOsOptions.defaultOptions` once an Apple Development cert lands.
const secureStorageMacOsOptions = MacOsOptions(
  useDataProtectionKeyChain: appFlavor != 'development',
);
