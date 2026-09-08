import 'dart:typed_data';

import '../components/components.dart';

/// basE91 codec: the densest ASCII encoding that still runs in linear time.
///
/// Bytes are pushed into a bit queue and drained as 13 or 14 bit groups, each
/// written as two symbols. That costs about 1.23 symbols per byte against the
/// 1.33 of base 64, so a payload comes out roughly 8 percent shorter while the
/// work per byte stays a couple of shifts.
class Base91Codec extends BinaryTextCodec {
  Base91Codec(this.alphabet) {
    if (alphabet.radix != _radix) {
      throw ArgumentError.value(
        alphabet,
        'alphabet',
        'Base91Codec needs an alphabet of exactly $_radix symbols',
      );
    }
  }

  @override
  final FuzzyAlphabet alphabet;

  static const int _radix = 91;
  static const int _shortGroupMask = 0x1FFF;
  static const int _longGroupMask = 0x3FFF;
  static const int _shortGroupThreshold = 88;

  @override
  String encode(Uint8List bytes) {
    final buffer = StringBuffer();

    var queue = 0;
    var queuedBits = 0;

    for (final byte in bytes) {
      queue |= byte << queuedBits;
      queuedBits += 8;

      if (queuedBits <= 13) continue;

      var group = queue & _shortGroupMask;

      if (group > _shortGroupThreshold) {
        queue >>= 13;
        queuedBits -= 13;
      } else {
        group = queue & _longGroupMask;
        queue >>= 14;
        queuedBits -= 14;
      }

      buffer.writeCharCode(alphabet.codeUnitFor(group % _radix));
      buffer.writeCharCode(alphabet.codeUnitFor(group ~/ _radix));
    }

    if (queuedBits > 0) {
      buffer.writeCharCode(alphabet.codeUnitFor(queue % _radix));

      if (queuedBits > 7 || queue > _radix - 1) {
        buffer.writeCharCode(alphabet.codeUnitFor(queue ~/ _radix));
      }
    }

    return buffer.toString();
  }

  @override
  Uint8List decode(String encoded) {
    final decoded = <int>[];

    var group = -1;
    var queue = 0;
    var queuedBits = 0;

    for (var index = 0; index < encoded.length; index++) {
      final value = alphabet.valueOfCodeUnit(encoded.codeUnitAt(index));

      if (value < 0) {
        throw FormatException(
          'Symbol does not belong to base $_radix',
          encoded,
          index,
        );
      }

      if (group < 0) {
        group = value;
        continue;
      }

      group += value * _radix;
      queue |= group << queuedBits;
      queuedBits += (group & _shortGroupMask) > _shortGroupThreshold ? 13 : 14;

      do {
        decoded.add(queue & 0xFF);
        queue >>= 8;
        queuedBits -= 8;
      } while (queuedBits > 7);

      group = -1;
    }

    if (group >= 0) {
      decoded.add((queue | (group << queuedBits)) & 0xFF);
    }

    return Uint8List.fromList(decoded);
  }
}
