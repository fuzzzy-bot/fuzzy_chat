import 'dart:convert';
import 'dart:typed_data';

import '../components/components.dart';

/// Base 64 backed by `dart:convert`.
///
/// Kept apart from `PowerOfTwoCodec` so the output stays byte for byte
/// identical to what the app wrote before this service existed, padding
/// included, which is what makes already stored payloads readable.
class StandardBase64Codec extends BinaryTextCodec {
  StandardBase64Codec(this.alphabet);

  @override
  final FuzzyAlphabet alphabet;

  @override
  String encode(Uint8List bytes) => base64Encode(bytes);

  @override
  Uint8List decode(String encoded) {
    try {
      return base64Decode(encoded);
    } on FormatException {
      // Normalizing costs a second pass, so it is kept for the rare payload
      // that arrives unpadded or in the url flavoured alphabet.
      return base64Decode(base64.normalize(encoded));
    }
  }
}
