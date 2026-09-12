import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzy_chat/rust_bridge/api/health.dart';

import '../../helpers/crypto_core_test_init.dart';

void main() {
  setUpAll(initCryptoCoreForTests);

  group('rust bridge smoke', () {
    test('coreVersion crosses the FFI', () async {
      final version = await coreVersion();

      expect(version, isNotEmpty);
    });

    test('roundTrip reverses bytes across the FFI', () async {
      final result = await roundTrip(bytes: [1, 2, 3]);

      expect(result, [3, 2, 1]);
    });
  });
}
