import 'dart:math';

/// Encodings the app knows how to read and write.
///
/// [tag] is the single symbol written into the envelope of a packed payload so
/// a value stays self describing and can be decoded without out of band
/// knowledge. None of the alphabets contains a tag symbol or the envelope
/// marker, which keeps the envelope unambiguous.
enum FuzzyEncodingType {
  base16('1', _base16Symbols),
  base32('2', _base32Symbols),
  base36('3', _base36Symbols),
  base58('4', _base58Symbols),
  base62('5', _base62Symbols),
  base64('6', _base64Symbols),
  base91('9', _base91Symbols);

  const FuzzyEncodingType(this.tag, this.symbols);

  final String tag;
  final String symbols;

  /// Symbols produced per byte, useful to compare how compact an encoding is.
  double get symbolsPerByte => 8 / (log(symbols.length) / ln2);

  static FuzzyEncodingType? fromTag(String tag) {
    for (final encoding in values) {
      if (encoding.tag == tag) return encoding;
    }

    return null;
  }
}

const String _base16Symbols = '0123456789ABCDEF';
const String _base32Symbols = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const String _base36Symbols = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const String _base58Symbols =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
const String _base62Symbols =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const String _base64Symbols =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const String _base91Symbols =
    r'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~"';
