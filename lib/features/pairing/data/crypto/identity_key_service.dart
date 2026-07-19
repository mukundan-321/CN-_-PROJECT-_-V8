import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'secure_key_store.dart';

const _kIdentityPrivateKey = 'identity_x25519_private_seed';
const _kSigningPrivateKey = 'signing_ed25519_private_seed';
const _kDeviceId = 'device_id';

/// This device's own long-term key material — generated once, on first
/// launch, and never regenerated or exported. The private keys never
/// leave [SecureKeyValueStore] (Keychain/Keystore); only the public
/// keys are ever put into a pairing payload or the database.
class LocalIdentity {
  final String deviceId;
  final SimpleKeyPair identityKeyPair; // X25519 — used for ECDH
  final SimpleKeyPair signingKeyPair; // Ed25519 — used to authenticate messages

  const LocalIdentity({
    required this.deviceId,
    required this.identityKeyPair,
    required this.signingKeyPair,
  });

  Future<Base64String> get identityPublicKeyBase64 async {
    final pub = await identityKeyPair.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  Future<String> get signingPublicKeyBase64 async {
    final pub = await signingKeyPair.extractPublicKey();
    return base64Encode(pub.bytes);
  }
}

typedef Base64String = String;

class IdentityKeyService {
  final SecureKeyValueStore _store;
  final _x25519 = X25519();
  final _ed25519 = Ed25519();

  // Memoizes the in-flight (or completed) identity load/generation.
  // Without this, two concurrent callers of getOrCreateIdentity() —
  // which genuinely happens, since PairingRepositoryImpl calls it
  // independently from several methods with no caching of its own —
  // would both see no key in storage yet, both generate *different*
  // keypairs, and race to persist: whichever write lands last wins in
  // storage, while the other caller keeps using an in-memory
  // LocalIdentity that no longer matches what's actually persisted.
  Future<LocalIdentity>? _identityFuture;

  IdentityKeyService(this._store);

  /// Loads the existing identity, or generates and persists a new one
  /// if this is the first launch. Idempotent and safe to call
  /// concurrently or repeatedly — pairing state lives separately (in
  /// the peer's public keys being present or not), not in whether
  /// this identity exists.
  Future<LocalIdentity> getOrCreateIdentity() {
    return _identityFuture ??= _loadOrCreateIdentity();
  }

  Future<LocalIdentity> _loadOrCreateIdentity() async {
    final existingIdentitySeed = await _store.read(_kIdentityPrivateKey);
    final existingSigningSeed = await _store.read(_kSigningPrivateKey);
    final existingDeviceId = await _store.read(_kDeviceId);

    if (existingIdentitySeed != null &&
        existingSigningSeed != null &&
        existingDeviceId != null) {
      final identityKeyPair = await _x25519
          .newKeyPairFromSeed(base64Decode(existingIdentitySeed));
      final signingKeyPair = await _ed25519
          .newKeyPairFromSeed(base64Decode(existingSigningSeed));
      return LocalIdentity(
        deviceId: existingDeviceId,
        identityKeyPair: identityKeyPair,
        signingKeyPair: signingKeyPair,
      );
    }

    final identityKeyPair = await _x25519.newKeyPair();
    final signingKeyPair = await _ed25519.newKeyPair();
    final deviceId = _generateDeviceId();

    final identitySeed = await identityKeyPair.extractPrivateKeyBytes();
    final signingSeed = await signingKeyPair.extractPrivateKeyBytes();

    await _store.write(_kIdentityPrivateKey, base64Encode(identitySeed));
    await _store.write(_kSigningPrivateKey, base64Encode(signingSeed));
    await _store.write(_kDeviceId, deviceId);

    return LocalIdentity(
      deviceId: deviceId,
      identityKeyPair: identityKeyPair,
      signingKeyPair: signingKeyPair,
    );
  }

  /// Irreversible — wipes this device's identity so a fresh one is
  /// generated on next use. Not currently wired to any UI action in
  /// this build; exists for completeness and is covered by tests.
  Future<void> destroyIdentity() async {
    await _store.deleteAll();
    _identityFuture = null;
  }

  String _generateDeviceId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
