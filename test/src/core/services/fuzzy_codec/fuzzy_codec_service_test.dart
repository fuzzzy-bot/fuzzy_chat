import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzy_chat/src/core/services/fuzzy_codec/fuzzy_codec.dart';

Uint8List _randomBytes(Random random, int length) {
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

void main() {
  group('FuzzyCodecService round trips', () {
    for (final encoding in FuzzyEncodingType.values) {
      test('${encoding.name} survives a round trip for every payload size',
          () async {
        final random = Random(encoding.index + 1);

        for (var length = 0; length <= 64; length++) {
          final bytes = _randomBytes(random, length);
          final encoded = FuzzyCodecService.encodeBytes(
            bytes,
            encoding: encoding,
          );
          final decoded = FuzzyCodecService.decodeBytes(
            encoded,
            encoding: encoding,
          );

          expect(decoded, equals(bytes), reason: 'length $length');
        }
      });
    }

    test('base 91 handles a payload far longer than a message', () {
      final bytes = _randomBytes(Random(7), 20000);

      final encoded = FuzzyCodecService.encodeBytes(bytes);

      expect(FuzzyCodecService.decodeBytes(encoded), equals(bytes));
    });

    test('leading zero bytes survive a base 58 round trip', () {
      final bytes = Uint8List.fromList([0, 0, 0, 12, 34, 56]);

      final encoded = FuzzyCodecService.encodeBytes(
        bytes,
        encoding: FuzzyEncodingType.base58,
      );

      expect(encoded.startsWith('111'), isTrue);
      expect(
        FuzzyCodecService.decodeBytes(
          encoded,
          encoding: FuzzyEncodingType.base58,
        ),
        equals(bytes),
      );
    });
  });

  group('FuzzyCodecService known vectors', () {
    final foobar = utf8.encode('foobar');

    test('base 16 matches the canonical hex output', () {
      expect(
        FuzzyCodecService.encodeBytes(
          foobar,
          encoding: FuzzyEncodingType.base16,
        ),
        equals('666F6F626172'),
      );
    });

    test('base 32 matches RFC 4648 without padding', () {
      expect(
        FuzzyCodecService.encodeBytes(
          foobar,
          encoding: FuzzyEncodingType.base32,
        ),
        equals('MZXW6YTBOI'),
      );
    });

    test('base 58 matches the reference implementation', () {
      expect(
        FuzzyCodecService.encodeBytes(
          utf8.encode('Hello World!'),
          encoding: FuzzyEncodingType.base58,
        ),
        equals('2NEpo7TZRRrLZSi2U'),
      );
    });

    test('base 64 stays byte for byte compatible with dart:convert', () {
      final random = Random(3);

      for (var length = 0; length <= 32; length++) {
        final bytes = _randomBytes(random, length);

        expect(
          FuzzyCodecService.encodeBytes(
            bytes,
            encoding: FuzzyEncodingType.base64,
          ),
          equals(base64Encode(bytes)),
        );
      }
    });
  });

  group('FuzzyCodecService envelope', () {
    test('packing tags the payload with the encoding it used', () {
      final packed = FuzzyCodecService.packBytes(utf8.encode('fuzzy'));

      expect(packed.startsWith('-${FuzzyEncodingType.base91.tag}'), isTrue);
      expect(
        FuzzyCodecService.readEncoding(packed),
        equals(FuzzyEncodingType.base91),
      );
      expect(FuzzyCodecService.unpackText(packed), equals('fuzzy'));
    });

    test('every encoding can be packed and unpacked', () {
      for (final encoding in FuzzyEncodingType.values) {
        final packed = FuzzyCodecService.packText(
          'counting in base ${encoding.name}',
          encoding: encoding,
        );

        expect(FuzzyCodecService.readEncoding(packed), equals(encoding));
        expect(
          FuzzyCodecService.unpackText(packed),
          equals('counting in base ${encoding.name}'),
        );
      }
    });

    test('a payload without an envelope is read as legacy base 64', () {
      final bytes = _randomBytes(Random(11), 48);
      final legacy = base64Encode(bytes);

      expect(FuzzyCodecService.readEncoding(legacy), isNull);
      expect(FuzzyCodecService.unpackBytes(legacy), equals(bytes));
    });

    test('no alphabet can produce the envelope marker', () {
      for (final encoding in FuzzyEncodingType.values) {
        expect(
          encoding.symbols.contains(FuzzyCodecService.envelopeMarker),
          isFalse,
          reason: encoding.name,
        );
      }
    });
  });

  group('FuzzyCodecService re-encoding', () {
    test('transcode rewrites a base 36 value into base 91', () {
      final bytes = _randomBytes(Random(5), 40);
      final asBase36 = FuzzyCodecService.encodeBytes(
        bytes,
        encoding: FuzzyEncodingType.base36,
      );

      final asBase91 = FuzzyCodecService.transcode(
        asBase36,
        from: FuzzyEncodingType.base36,
        to: FuzzyEncodingType.base91,
      );

      expect(asBase91.length, lessThan(asBase36.length));
      expect(
        FuzzyCodecService.decodeBytes(asBase91),
        equals(bytes),
      );
    });

    test('shrink turns a legacy base 64 payload into a shorter packed one', () {
      final bytes = _randomBytes(Random(13), 120);
      final legacy = base64Encode(bytes);

      final shrunk = FuzzyCodecService.shrink(legacy);

      expect(shrunk.length, lessThan(legacy.length));
      expect(FuzzyCodecService.unpackBytes(shrunk), equals(bytes));
    });

    test('shrink leaves an already shrunk payload untouched', () {
      final packed = FuzzyCodecService.packBytes(_randomBytes(Random(17), 64));

      expect(FuzzyCodecService.shrink(packed), equals(packed));
    });

    test('shrink returns a value it cannot decode untouched', () {
      const filePath = '/Users/someone/Documents/photo.png.fuzz';

      expect(FuzzyCodecService.shrink(filePath), equals(filePath));
      expect(FuzzyCodecService.shrink(''), isEmpty);
    });

    test('base 91 is the shortest encoding on offer', () {
      final bytes = _randomBytes(Random(19), 256);

      final lengths = <FuzzyEncodingType, int>{
        for (final encoding in FuzzyEncodingType.values)
          encoding: FuzzyCodecService.encodeBytes(
            bytes,
            encoding: encoding,
          ).length,
      };

      final shortest = lengths.entries.reduce(
        (best, current) => current.value < best.value ? current : best,
      );

      final base91Length = lengths[FuzzyEncodingType.base91]!;
      final base64Length = lengths[FuzzyEncodingType.base64]!;

      expect(shortest.key, equals(FuzzyEncodingType.base91));
      expect(base91Length, lessThan(base64Length));
    });
  });

  group('FuzzyCodecService validation', () {
    test('decoding rejects a symbol outside the alphabet', () {
      expect(
        () => FuzzyCodecService.decodeBytes(
          '66FG',
          encoding: FuzzyEncodingType.base16,
        ),
        throwsFormatException,
      );
      expect(
        () => FuzzyCodecService.decodeBytes(
          'abc def',
          encoding: FuzzyEncodingType.base36,
        ),
        throwsFormatException,
      );
    });

    test('an alphabet rejects repeated, oversized and non ascii symbols', () {
      expect(() => FuzzyAlphabet('001'), throwsArgumentError);
      expect(() => FuzzyAlphabet('0'), throwsArgumentError);
      expect(() => FuzzyAlphabet('01ə'), throwsArgumentError);
    });

    test('a custom alphabet is served by the fastest matching codec', () {
      expect(
        FuzzyCodecService.codecForAlphabet(FuzzyAlphabet('01')),
        isA<PowerOfTwoCodec>(),
      );
      expect(
        FuzzyCodecService.codecForAlphabet(
          FuzzyAlphabet('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
        ),
        isA<RadixCodec>(),
      );
    });

    test('a custom alphabet round trips through its own symbols', () {
      final alphabet = FuzzyAlphabet('!?');
      final codec = FuzzyCodecService.codecForAlphabet(alphabet);
      final bytes = _randomBytes(Random(23), 32);

      final encoded = codec.encode(bytes);

      expect(RegExp(r'^[!?]+$').hasMatch(encoded), isTrue);
      expect(codec.decode(encoded), equals(bytes));
    });
  });
}
