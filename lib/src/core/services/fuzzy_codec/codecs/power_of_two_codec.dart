import 'dart:typed_data';

import '../components/components.dart';

/// Bit packing codec for alphabets whose radix is a power of two.
///
/// Every symbol maps onto a fixed slice of bits, so encoding and decoding stay
/// linear in the payload size. Trailing bits of the last symbol are zero filled
/// and dropped again while decoding, which keeps the output free of padding.
class PowerOfTwoCodec extends BinaryTextCodec {
  PowerOfTwoCodec(this.alphabet) : bitsPerSymbol = alphabet.bitsPerSymbol {
    if (!alphabet.isPowerOfTwoRadix) {
      throw ArgumentError.value(
        alphabet,
        'alphabet',
        'PowerOfTwoCodec needs a radix that is a power of two',
      );
    }
  }

  @override
  final FuzzyAlphabet alphabet;

  final int bitsPerSymbol;

  @override
  String encode(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    final symbolMask = (1 << bitsPerSymbol) - 1;
    final symbols = Uint8List(
      (bytes.length * 8 + bitsPerSymbol - 1) ~/ bitsPerSymbol,
    );

    var symbolCount = 0;
    var queue = 0;
    var queuedBits = 0;

    for (final byte in bytes) {
      queue = (queue << 8) | byte;
      queuedBits += 8;

      while (queuedBits >= bitsPerSymbol) {
        queuedBits -= bitsPerSymbol;
        symbols[symbolCount++] =
            alphabet.codeUnitFor((queue >> queuedBits) & symbolMask);
      }

      queue &= (1 << queuedBits) - 1;
    }

    if (queuedBits > 0) {
      symbols[symbolCount++] = alphabet.codeUnitFor(
        (queue << (bitsPerSymbol - queuedBits)) & symbolMask,
      );
    }

    return String.fromCharCodes(symbols, 0, symbolCount);
  }

  @override
  Uint8List decode(String encoded) {
    if (encoded.isEmpty) return Uint8List(0);

    final decoded = Uint8List(encoded.length * bitsPerSymbol ~/ 8);

    var decodedLength = 0;
    var queue = 0;
    var queuedBits = 0;

    for (var index = 0; index < encoded.length; index++) {
      final value = alphabet.valueOfCodeUnit(encoded.codeUnitAt(index));

      if (value < 0) {
        throw FormatException(
          'Symbol does not belong to base ${alphabet.radix}',
          encoded,
          index,
        );
      }

      queue = (queue << bitsPerSymbol) | value;
      queuedBits += bitsPerSymbol;

      if (queuedBits >= 8) {
        queuedBits -= 8;
        decoded[decodedLength++] = (queue >> queuedBits) & 0xFF;
        queue &= (1 << queuedBits) - 1;
      }
    }

    return decoded;
  }
}
