import 'dart:typed_data';

/// Ordered symbol set that defines a positional numeral system.
///
/// The position of a symbol inside [symbols] is its numeric value, so
/// `FuzzyAlphabet('0123456789ABCDEF')` describes base 16 while
/// `FuzzyAlphabet('01')` describes base 2. Any ASCII symbol set works, which
/// is what lets the codecs count in an arbitrary base.
class FuzzyAlphabet {
  FuzzyAlphabet(this.symbols)
      : _symbolCodeUnits = Uint8List.fromList(symbols.codeUnits),
        _valueByCodeUnit = _buildValueLookup(symbols);

  final String symbols;

  final Uint8List _symbolCodeUnits;
  final Int8List _valueByCodeUnit;

  static const int minRadix = 2;
  static const int maxRadix = 128;
  static const int _lookupSize = 128;

  /// The base this alphabet counts in.
  int get radix => symbols.length;

  /// Whether the radix allows plain bit packing instead of division.
  bool get isPowerOfTwoRadix => radix & (radix - 1) == 0;

  /// Bits carried by a single symbol, only meaningful for power of two radixes.
  int get bitsPerSymbol {
    var bits = 0;
    var remaining = radix;

    while (remaining > 1) {
      remaining >>= 1;
      bits++;
    }

    return bits;
  }

  int codeUnitFor(int value) => _symbolCodeUnits[value];

  /// Numeric value of [codeUnit], or -1 when it is not part of the alphabet.
  int valueOfCodeUnit(int codeUnit) {
    if (codeUnit < 0 || codeUnit >= _lookupSize) return -1;
    return _valueByCodeUnit[codeUnit];
  }

  bool containsCodeUnit(int codeUnit) => valueOfCodeUnit(codeUnit) >= 0;

  static Int8List _buildValueLookup(String symbols) {
    final radix = symbols.length;

    if (radix < minRadix || radix > maxRadix) {
      throw ArgumentError.value(
        symbols,
        'symbols',
        'An alphabet must hold between $minRadix and $maxRadix symbols',
      );
    }

    final lookup = Int8List(_lookupSize)..fillRange(0, _lookupSize, -1);

    for (var value = 0; value < radix; value++) {
      final codeUnit = symbols.codeUnitAt(value);

      if (codeUnit >= _lookupSize) {
        throw ArgumentError.value(
          symbols,
          'symbols',
          'An alphabet accepts ASCII symbols only',
        );
      }

      if (lookup[codeUnit] >= 0) {
        throw ArgumentError.value(
          symbols,
          'symbols',
          'An alphabet must not repeat a symbol',
        );
      }

      lookup[codeUnit] = value;
    }

    return lookup;
  }

  @override
  String toString() => 'FuzzyAlphabet(radix: $radix)';
}
