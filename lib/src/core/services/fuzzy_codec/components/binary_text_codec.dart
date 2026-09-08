import 'dart:typed_data';

import 'fuzzy_alphabet.dart';

/// Converts bytes into text written in [alphabet] and back.
abstract class BinaryTextCodec {
  const BinaryTextCodec();

  FuzzyAlphabet get alphabet;

  String encode(Uint8List bytes);

  /// Throws a [FormatException] when [encoded] holds a foreign symbol.
  Uint8List decode(String encoded);
}
