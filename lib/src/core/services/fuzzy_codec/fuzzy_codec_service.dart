import 'dart:convert';
import 'dart:typed_data';

import 'codecs/codecs.dart';
import 'components/components.dart';

/// One entry point for turning bytes into text in any supported base.
///
/// Two levels of API live here:
///
/// * [encodeBytes] and [decodeBytes] are the raw conversions, the caller knows
///   which base is in play.
/// * [packBytes] and [unpackBytes] wrap the same conversion in a two symbol
///   envelope, `-` followed by [FuzzyEncodingType.tag], so a stored or shared
///   value says which base it is written in. Anything without that envelope is
///   read as [legacyEncoding], which is how payloads written before this
///   service still decode.
///
/// Re-encoding is pure symbol shuffling and never touches the cipher, so
/// [shrink] and [transcode] make an existing payload shorter without paying for
/// encryption again.
class FuzzyCodecService {
  const FuzzyCodecService._();

  /// Densest encoding that still runs in linear time, see [Base91Codec].
  static const FuzzyEncodingType defaultEncoding = FuzzyEncodingType.base91;

  /// How an envelope-less payload is read, matching what the app wrote before.
  static const FuzzyEncodingType legacyEncoding = FuzzyEncodingType.base64;

  static const String envelopeMarker = '-';
  static const int envelopeLength = 2;

  static final Map<FuzzyEncodingType, BinaryTextCodec> _codecs = {};

  static BinaryTextCodec codecOf(FuzzyEncodingType encoding) =>
      _codecs.putIfAbsent(encoding, () => _buildCodec(encoding));

  /// Fastest codec able to serve a custom [alphabet].
  static BinaryTextCodec codecForAlphabet(FuzzyAlphabet alphabet) {
    if (alphabet.radix == 91) return Base91Codec(alphabet);
    if (alphabet.isPowerOfTwoRadix) return PowerOfTwoCodec(alphabet);
    return RadixCodec(alphabet);
  }

  static String encodeBytes(
    Uint8List bytes, {
    FuzzyEncodingType encoding = defaultEncoding,
  }) =>
      codecOf(encoding).encode(bytes);

  static Uint8List decodeBytes(
    String encoded, {
    FuzzyEncodingType encoding = defaultEncoding,
  }) =>
      codecOf(encoding).decode(encoded);

  /// Encodes [bytes] and prefixes the envelope that names the encoding.
  static String packBytes(
    Uint8List bytes, {
    FuzzyEncodingType encoding = defaultEncoding,
  }) =>
      '$envelopeMarker${encoding.tag}${encodeBytes(bytes, encoding: encoding)}';

  /// Reverses [packBytes], falling back to [legacyEncoding] without envelope.
  static Uint8List unpackBytes(String packed) {
    final encoding = readEncoding(packed);

    if (encoding == null) {
      return decodeBytes(packed, encoding: legacyEncoding);
    }

    return decodeBytes(packed.substring(envelopeLength), encoding: encoding);
  }

  static String packText(
    String text, {
    FuzzyEncodingType encoding = defaultEncoding,
  }) =>
      packBytes(utf8.encode(text), encoding: encoding);

  static String unpackText(String packed) => utf8.decode(unpackBytes(packed));

  /// Encoding named by the envelope of [packed], or null when it carries none.
  static FuzzyEncodingType? readEncoding(String packed) {
    if (packed.length < envelopeLength) return null;
    if (!packed.startsWith(envelopeMarker)) return null;

    return FuzzyEncodingType.fromTag(packed[1]);
  }

  /// Rewrites an already encoded value from one base into another.
  static String transcode(
    String encoded, {
    required FuzzyEncodingType from,
    required FuzzyEncodingType to,
  }) =>
      encodeBytes(decodeBytes(encoded, encoding: from), encoding: to);

  /// Rewrites a packed value into [encoding], keeping the envelope in place.
  static String repack(
    String packed, {
    FuzzyEncodingType encoding = defaultEncoding,
  }) =>
      packBytes(unpackBytes(packed), encoding: encoding);

  /// Best effort [repack] for values that may not be an encoded payload.
  ///
  /// Returns [packed] untouched when it already uses [encoding] or when it
  /// cannot be decoded at all, which keeps call sites that hand over arbitrary
  /// strings, such as a file path, safe.
  static String shrink(
    String packed, {
    FuzzyEncodingType encoding = defaultEncoding,
  }) {
    if (packed.isEmpty) return packed;
    if (readEncoding(packed) == encoding) return packed;

    try {
      return repack(packed, encoding: encoding);
    } catch (_) {
      return packed;
    }
  }

  static BinaryTextCodec _buildCodec(FuzzyEncodingType encoding) {
    final alphabet = FuzzyAlphabet(encoding.symbols);

    if (encoding == FuzzyEncodingType.base64) {
      return StandardBase64Codec(alphabet);
    }

    return codecForAlphabet(alphabet);
  }
}
