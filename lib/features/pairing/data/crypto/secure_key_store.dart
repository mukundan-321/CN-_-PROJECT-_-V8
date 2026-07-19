import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin interface over secure, platform-native key/value storage.
///
/// Private key material is the one thing in this app that must never
/// end up in the SQLCipher database, log output, or a backup — it goes
/// through this interface and nowhere else. Abstracted so tests don't
/// need a real Keychain/Keystore (which isn't available under plain
/// `flutter_test`, only on-device / integration tests).
abstract class SecureKeyValueStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

class DeviceSecureKeyValueStore implements SecureKeyValueStore {
  final FlutterSecureStorage _storage;

  DeviceSecureKeyValueStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// In-memory fake for unit tests. Never used outside `test/`.
class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> deleteAll() async => _data.clear();
}
