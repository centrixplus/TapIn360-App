import 'package:device_info_plus/device_info_plus.dart';

import '../storage/key_value_store.dart';

/// The phone's hardware ID for device binding (spec §14). IMEI is not
/// readable by normal apps, so: Android `ANDROID_ID` (read each time, it is
/// stable), iOS `identifierForVendor` cached in secure storage so a transient
/// nil cannot change it. If the platform gives nothing, the app-install ID is
/// used — and cached when caching, so the value never changes afterwards.
class HardwareIdReader {
  HardwareIdReader({
    required this._store,
    required this._readPlatformId,
    required this._cache,
    required this._fallbackId,
  });

  static const _key = 'hardware_id';

  final KeyValueStore _store;
  final Future<String?> Function() _readPlatformId;
  final bool _cache;
  final String _fallbackId;

  Future<String> read() async {
    if (_cache) {
      final cached = await _tryRead();
      if (cached != null && cached.isNotEmpty) return cached;
    }
    String? id;
    try {
      id = await _readPlatformId();
    } catch (_) {
      id = null;
    }
    if (id == null || id.isEmpty) id = _fallbackId;
    if (_cache) {
      try {
        await _store.write(_key, id);
      } catch (_) {
        // Not cached this time; read again on the next start.
      }
    }
    return id;
  }

  Future<String?> _tryRead() async {
    try {
      return await _store.read(_key);
    } catch (_) {
      return null;
    }
  }
}

/// iOS `identifierForVendor` (null until the device is unlocked after a restart).
Future<String?> iosVendorId() async => (await DeviceInfoPlugin().iosInfo).identifierForVendor;
