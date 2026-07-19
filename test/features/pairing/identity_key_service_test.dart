import 'package:flutter_test/flutter_test.dart';
import 'package:two_person_app/features/pairing/data/crypto/identity_key_service.dart';
import 'package:two_person_app/features/pairing/data/crypto/secure_key_store.dart';

void main() {
  group('IdentityKeyService', () {
    test('generates an identity on first call', () async {
      final service = IdentityKeyService(InMemorySecureKeyValueStore());
      final identity = await service.getOrCreateIdentity();

      expect(identity.deviceId, isNotEmpty);
      expect(await identity.identityPublicKeyBase64, isNotEmpty);
      expect(await identity.signingPublicKeyBase64, isNotEmpty);
    });

    test('returns the same identity on repeated calls (same store)', () async {
      final store = InMemorySecureKeyValueStore();
      final service = IdentityKeyService(store);

      final first = await service.getOrCreateIdentity();
      final second = await service.getOrCreateIdentity();

      expect(second.deviceId, first.deviceId);
      expect(
        await second.identityPublicKeyBase64,
        await first.identityPublicKeyBase64,
      );
    });

    test('survives "app restart" — new service instance, same store', () async {
      final store = InMemorySecureKeyValueStore();
      final before = await IdentityKeyService(store).getOrCreateIdentity();

      // Simulate relaunch: brand new service wrapping the same
      // underlying secure storage.
      final after = await IdentityKeyService(store).getOrCreateIdentity();

      expect(after.deviceId, before.deviceId);
      expect(
        await after.identityPublicKeyBase64,
        await before.identityPublicKeyBase64,
      );
      expect(
        await after.signingPublicKeyBase64,
        await before.signingPublicKeyBase64,
      );
    });

    test('two different stores produce two different identities', () async {
      final a = await IdentityKeyService(InMemorySecureKeyValueStore())
          .getOrCreateIdentity();
      final b = await IdentityKeyService(InMemorySecureKeyValueStore())
          .getOrCreateIdentity();

      expect(a.deviceId, isNot(b.deviceId));
      expect(
        await a.identityPublicKeyBase64,
        isNot(await b.identityPublicKeyBase64),
      );
    });

    test('destroyIdentity wipes stored keys, next call regenerates', () async {
      final store = InMemorySecureKeyValueStore();
      final service = IdentityKeyService(store);
      final before = await service.getOrCreateIdentity();

      await service.destroyIdentity();
      final after = await service.getOrCreateIdentity();

      expect(after.deviceId, isNot(before.deviceId));
    });

    test('concurrent calls on the same instance return the same identity', () async {
      // Regression test: getOrCreateIdentity() previously had no
      // memoization, so two calls started before either finished
      // would both see no key in storage, both generate *different*
      // keypairs, and race to persist — the loser's in-memory
      // LocalIdentity would silently stop matching what was actually
      // stored. Firing several concurrent calls here and asserting
      // they all agree is exactly the scenario that used to break.
      final service = IdentityKeyService(InMemorySecureKeyValueStore());

      final results = await Future.wait([
        service.getOrCreateIdentity(),
        service.getOrCreateIdentity(),
        service.getOrCreateIdentity(),
      ]);

      final deviceIds = results.map((r) => r.deviceId).toSet();
      expect(deviceIds, hasLength(1));

      final publicKeys = await Future.wait(
        results.map((r) => r.identityPublicKeyBase64),
      );
      expect(publicKeys.toSet(), hasLength(1));
    });
  });
}
