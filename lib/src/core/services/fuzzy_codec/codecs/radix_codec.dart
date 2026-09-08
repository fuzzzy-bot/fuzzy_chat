import 'dart:math';
import 'dart:typed_data';

import '../components/components.dart';

/// Counts the payload as one big number and rewrites it in another base.
///
/// This is the general answer for alphabets whose radix is not a power of two,
/// such as base 36 or base 58. Leading zero bytes carry no weight in a number,
/// so they are preserved separately as leading zero symbols.
///
/// The conversion divides the whole payload once per symbol, so cost grows with
/// the square of the payload size. Reach for it on short values such as ids and
/// keys, and prefer `PowerOfTwoCodec` or `Base91Codec` for message sized data.
class RadixCodec extends BinaryTextCodec {
  RadixCodec(this.alphabet);

  @override
  final FuzzyAlphabet alphabet;

  @override
  String encode(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    final radix = alphabet.radix;
    final zeroCodeUnit = alphabet.codeUnitFor(0);
    final leadingZeros = _countLeadingZeroBytes(bytes);

    final capacity = _capacityFor(
      sourceLength: bytes.length - leadingZeros,
      unitsPerSource: 8 / (log(radix) / ln2),
    );

    final digits = Uint8List(capacity);
    var digitCount = 0;

    for (var index = leadingZeros; index < bytes.length; index++) {
      var carry = bytes[index];
      var written = 0;

      for (var position = capacity - 1;
          position >= 0 && (carry != 0 || written < digitCount);
          position--) {
        carry += 256 * digits[position];
        digits[position] = carry % radix;
        carry ~/= radix;
        written++;
      }

      digitCount = written;
    }

    final buffer = StringBuffer();

    for (var index = 0; index < leadingZeros; index++) {
      buffer.writeCharCode(zeroCodeUnit);
    }

    for (var index = capacity - digitCount; index < capacity; index++) {
      buffer.writeCharCode(alphabet.codeUnitFor(digits[index]));
    }

    return buffer.toString();
  }

  @override
  Uint8List decode(String encoded) {
    if (encoded.isEmpty) return Uint8List(0);

    final radix = alphabet.radix;
    final zeroCodeUnit = alphabet.codeUnitFor(0);
    final leadingZeros = _countLeadingZeroSymbols(encoded, zeroCodeUnit);

    final capacity = _capacityFor(
      sourceLength: encoded.length - leadingZeros,
      unitsPerSource: (log(radix) / ln2) / 8,
    );

    final bytes = Uint8List(capacity);
    var byteCount = 0;

    for (var index = leadingZeros; index < encoded.length; index++) {
      var carry = alphabet.valueOfCodeUnit(encoded.codeUnitAt(index));

      if (carry < 0) {
        throw FormatException(
          'Symbol does not belong to base $radix',
          encoded,
          index,
        );
      }

      var written = 0;

      for (var position = capacity - 1;
          position >= 0 && (carry != 0 || written < byteCount);
          position--) {
        carry += radix * bytes[position];
        bytes[position] = carry & 0xFF;
        carry >>= 8;
        written++;
      }

      byteCount = written;
    }

    final decoded = Uint8List(leadingZeros + byteCount);
    decoded.setRange(leadingZeros, decoded.length, bytes, capacity - byteCount);

    return decoded;
  }

  static int _countLeadingZeroBytes(Uint8List bytes) {
    var count = 0;

    while (count < bytes.length && bytes[count] == 0) {
      count++;
    }

    return count;
  }

  static int _countLeadingZeroSymbols(String encoded, int zeroCodeUnit) {
    var count = 0;

    while (count < encoded.length && encoded.codeUnitAt(count) == zeroCodeUnit) {
      count++;
    }

    return count;
  }

  static int _capacityFor({
    required int sourceLength,
    required double unitsPerSource,
  }) =>
      (sourceLength * unitsPerSource).ceil() + 1;
}
