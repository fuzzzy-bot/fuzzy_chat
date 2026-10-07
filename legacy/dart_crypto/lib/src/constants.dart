import 'dart:typed_data';

/// The HKDF `info` bytes every per-message sub-key was derived under.
///
/// Restored verbatim from `lib/src/core/constants/default_constants.dart` as it
/// stood at `d4f7ce4^`; the rest of that file is still in the app and is not
/// cryptographic.
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
