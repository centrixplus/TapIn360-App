import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal string store; the app uses the secure one, tests the memory one.
abstract interface class KeyValueStore {
  Future<String?> read(String key);

  /// Writing null deletes the key.
  Future<void> write(String key, String? value);
  Future<void> clear();
}

/// Android EncryptedSharedPreferences / iOS Keychain (this device only).
class SecureKeyValueStore implements KeyValueStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) {
    return value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}

class MemoryKeyValueStore implements KeyValueStore {
  final values = <String, String>{};

  /// Simulates an unreadable store until [clear] is called.
  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('unreadable');
    return values[key];
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> clear() async {
    values.clear();
    failReads = false;
  }
}
