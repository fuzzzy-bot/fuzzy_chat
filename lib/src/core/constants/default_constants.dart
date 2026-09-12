// The analyzer sees no `--flavor`, so it reads the macOS options as defaults.
// ignore_for_file: avoid_redundant_argument_values, use_named_constants

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const fuzzIdentificator = 'Fuzz/';
const fuzzedFileIdentificator = 'fuzz';

/// Development builds are unsigned on macOS, so they use the login keychain
/// instead of the data-protection keychain (DECISIONS 2026-09-12 / D-3);
/// revert to `MacOsOptions.defaultOptions` once an Apple Development cert lands.
const secureStorageMacOsOptions = MacOsOptions(
  useDataProtectionKeyChain: appFlavor != 'development',
);

/// The settings tile that benchmarks the file path exists in the development
/// flavor only; staging and production builds never carry it. Not tied to
/// `kDebugMode` on purpose: a debug build ships the crate's dev profile, so
/// only a `--profile`/`--release` development build measures the real core.
const isFileBenchmarkEnabled = appFlavor == 'development';
