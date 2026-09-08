// ignore_for_file: avoid_print
// Throughput benchmark for FuzzyCodecService. Run AOT for release-like numbers:
//   fvm dart compile exe tool/codec_benchmark.dart -o /tmp/codec_benchmark
//   /tmp/codec_benchmark
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fuzzy_chat/src/core/services/fuzzy_codec/fuzzy_codec.dart';

const Duration _budget = Duration(milliseconds: 400);

/// Payload of an encrypted message: 24 B salt + 12 B nonce + text + 16 B tag.
int _payloadFor(int textLength) => 24 + 12 + textLength + 16;

Uint8List _bytes(int length) {
  final random = Random(42);
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

/// Nanoseconds per operation, measured over at least [_budget].
double _measure(void Function() action) {
  for (var index = 0; index < 5; index++) {
    action();
  }

  final watch = Stopwatch()..start();
  var operations = 0;

  while (watch.elapsed < _budget) {
    action();
    operations++;
  }

  watch.stop();

  return watch.elapsedMicroseconds * 1000 / operations;
}

String _perOp(double nanoseconds) {
  if (nanoseconds < 1000) return '${nanoseconds.toStringAsFixed(0)} ns';
  if (nanoseconds < 1000000) {
    return '${(nanoseconds / 1000).toStringAsFixed(1)} us';
  }
  return '${(nanoseconds / 1000000).toStringAsFixed(2)} ms';
}

String _throughput(int byteCount, double nanoseconds) =>
    '${(byteCount / nanoseconds * 1000).toStringAsFixed(0)} MB/s';

void _row(String label, int byteCount, double encodeNs, double decodeNs) {
  print(
    '${label.padRight(22)}'
    '${_perOp(encodeNs).padLeft(9)}'
    '${_throughput(byteCount, encodeNs).padLeft(11)}'
    '${_perOp(decodeNs).padLeft(11)}'
    '${_throughput(byteCount, decodeNs).padLeft(11)}',
  );
}

void _header(String title) {
  print('');
  print(title);
  print('${'codec'.padRight(22)}'
      '${'encode'.padLeft(9)}${''.padLeft(11)}'
      '${'decode'.padLeft(11)}${''.padLeft(11)}');
  print('-' * 62);
}

void _benchmarkSize(int byteCount, List<FuzzyEncodingType> encodings) {
  final bytes = _bytes(byteCount);

  _header('payload $byteCount B');

  for (final encoding in encodings) {
    final encoded = FuzzyCodecService.encodeBytes(bytes, encoding: encoding);

    final encodeNs = _measure(
      () => FuzzyCodecService.encodeBytes(bytes, encoding: encoding),
    );
    final decodeNs = _measure(
      () => FuzzyCodecService.decodeBytes(encoded, encoding: encoding),
    );

    _row(
      '${encoding.name} (${encoded.length} ch)',
      byteCount,
      encodeNs,
      decodeNs,
    );
  }

  final dartEncoded = base64Encode(bytes);
  _row(
    'dart:convert base64',
    byteCount,
    _measure(() => base64Encode(bytes)),
    _measure(() => base64Decode(dartEncoded)),
  );
}

void _benchmarkReEncoding() {
  _header('re-encoding an existing payload (no cipher work)');

  for (final textLength in [100, 1000]) {
    final bytes = _bytes(_payloadFor(textLength));
    final legacy = base64Encode(bytes);

    final shrinkNs = _measure(() => FuzzyCodecService.shrink(legacy));
    final packNs = _measure(() => FuzzyCodecService.packBytes(bytes));

    print(
      'text $textLength chars'.padRight(22) +
          'shrink ${_perOp(shrinkNs)}'.padLeft(20) +
          'pack ${_perOp(packNs)}'.padLeft(20),
    );
  }
}

void main() {
  const linear = [
    FuzzyEncodingType.base16,
    FuzzyEncodingType.base32,
    FuzzyEncodingType.base64,
    FuzzyEncodingType.base91,
  ];
  const all = [
    FuzzyEncodingType.base16,
    FuzzyEncodingType.base32,
    FuzzyEncodingType.base36,
    FuzzyEncodingType.base58,
    FuzzyEncodingType.base62,
    FuzzyEncodingType.base64,
    FuzzyEncodingType.base91,
  ];

  _benchmarkSize(_payloadFor(100), all);
  _benchmarkSize(_payloadFor(1000), all);
  _benchmarkSize(16 * 1024, linear);
  _benchmarkSize(1024 * 1024, linear);

  _benchmarkReEncoding();
}
