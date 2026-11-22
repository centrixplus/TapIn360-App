import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/device/hardware_id.dart';
import 'package:nfc_attendance/core/storage/key_value_store.dart';

void main() {
  late MemoryKeyValueStore kv;
  late int reads;

  HardwareIdReader reader({required bool cache, String? platformValue}) {
    reads = 0;
    return HardwareIdReader(
      store: kv,
      readPlatformId: () async {
        reads++;
        return platformValue;
      },
      cache: cache,
      fallbackId: 'install-uuid',
    );
  }

  setUp(() => kv = MemoryKeyValueStore());

  group('Android (ANDROID_ID, not cached)', () {
    test('reads the platform ID every time', () async {
      expect(await reader(cache: false, platformValue: 'a1b2c3d4e5f60718').read(), 'a1b2c3d4e5f60718');
      expect(reads, 1);
      expect(kv.values, isEmpty);
    });

    test('platform ID unavailable → app-install ID', () async {
      expect(await reader(cache: false, platformValue: null).read(), 'install-uuid');
    });
  });

  group('iOS (identifierForVendor, cached)', () {
    test('first read stores the vendor ID; later reads use the cache', () async {
      expect(await reader(cache: true, platformValue: 'IFV-1').read(), 'IFV-1');
      expect(await reader(cache: true, platformValue: 'IFV-2').read(), 'IFV-1');
      expect(reads, 0, reason: 'cached value wins');
    });

    test('a transient nil does not change a cached ID', () async {
      await reader(cache: true, platformValue: 'IFV-1').read();
      expect(await reader(cache: true, platformValue: null).read(), 'IFV-1');
    });

    test('nil with nothing cached → app-install ID, cached so it stays stable', () async {
      expect(await reader(cache: true, platformValue: null).read(), 'install-uuid');
      expect(await reader(cache: true, platformValue: 'IFV-late').read(), 'install-uuid');
    });

    test('a platform error is treated like nil', () async {
      final r = HardwareIdReader(
        store: kv,
        readPlatformId: () async => throw StateError('channel'),
        cache: true,
        fallbackId: 'install-uuid',
      );
      expect(await r.read(), 'install-uuid');
    });
  });
}
