/// The pure-Dart encryption stack Fuzzy Chat shipped before the Rust core.
///
/// Archived, not wired in: nothing in the app depends on this package, and the
/// two stacks cannot read each other's blobs. See `README.md` before using any
/// of it for anything.
library fuzzy_dart_crypto_legacy;

export 'src/aes_service/aes_service.dart';
export 'src/constants.dart';
export 'src/handshake_service/handshake_service.dart';
export 'src/password_based_encryption_service/password_based_encryption_service.dart';
export 'src/rsa_service/rsa_service.dart';
export 'src/utils/secure_bytes_generation.dart';
