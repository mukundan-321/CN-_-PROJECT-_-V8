import 'package:flutter_test/flutter_test.dart';
import 'package:two_person_app/features/pairing/data/crypto/session_crypto_service.dart';

void main() {
  group('SessionKeyExchange', () {
    test('both sides derive matching, opposite-direction keys', () async {
      final exchange = SessionKeyExchange();
      final aliceEphemeral = await exchange.generateEphemeral();
      final bobEphemeral = await exchange.generateEphemeral();

      final alicePub = await aliceEphemeral.extractPublicKey();
      final bobPub = await bobEphemeral.extractPublicKey();

      final aliceKeys = await exchange.deriveSessionKeys(
        localEphemeralKeyPair: aliceEphemeral,
        remoteEphemeralPublicKey: bobPub,
        isInitiator: true,
      );
      final bobKeys = await exchange.deriveSessionKeys(
        localEphemeralKeyPair: bobEphemeral,
        remoteEphemeralPublicKey: alicePub,
        isInitiator: false,
      );

      // Alice's send key must equal Bob's receive key, and vice versa.
      final aliceSend = await aliceKeys.sendKey.extractBytes();
      final bobReceive = await bobKeys.receiveKey.extractBytes();
      expect(aliceSend, bobReceive);

      final bobSend = await bobKeys.sendKey.extractBytes();
      final aliceReceive = await aliceKeys.receiveKey.extractBytes();
      expect(bobSend, aliceReceive);

      // And the two directions must not be the same key as each other.
      expect(aliceSend, isNot(bobSend));
    });
  });

  group('SessionCipher', () {
    late SessionCipher aliceCipher;
    late SessionCipher bobCipher;

    setUp(() async {
      final exchange = SessionKeyExchange();
      final aliceEphemeral = await exchange.generateEphemeral();
      final bobEphemeral = await exchange.generateEphemeral();
      final alicePub = await aliceEphemeral.extractPublicKey();
      final bobPub = await bobEphemeral.extractPublicKey();

      final aliceKeys = await exchange.deriveSessionKeys(
        localEphemeralKeyPair: aliceEphemeral,
        remoteEphemeralPublicKey: bobPub,
        isInitiator: true,
      );
      final bobKeys = await exchange.deriveSessionKeys(
        localEphemeralKeyPair: bobEphemeral,
        remoteEphemeralPublicKey: alicePub,
        isInitiator: false,
      );

      aliceCipher = SessionCipher(aliceKeys);
      bobCipher = SessionCipher(bobKeys);
    });

    test('encrypt on one side, decrypt on the other — round trip', () async {
      final envelope = await aliceCipher.encrypt('hello bob'.codeUnits);
      final plaintext = await bobCipher.decrypt(envelope);
      expect(String.fromCharCodes(plaintext), 'hello bob');
    });

    test('multiple messages in sequence decrypt correctly', () async {
      for (final msg in ['one', 'two', 'three']) {
        final envelope = await aliceCipher.encrypt(msg.codeUnits);
        final plaintext = await bobCipher.decrypt(envelope);
        expect(String.fromCharCodes(plaintext), msg);
      }
    });

    test('tampered ciphertext fails to decrypt', () async {
      final envelope = await aliceCipher.encrypt('hello bob'.codeUnits);
      final tampered = EncryptedEnvelope(
        counter: envelope.counter,
        ciphertext: [...envelope.ciphertext]..[0] = envelope.ciphertext[0] ^ 0xFF,
        nonce: envelope.nonce,
        mac: envelope.mac,
      );
      expect(() => bobCipher.decrypt(tampered), throwsException);
    });

    test('replayed envelope is rejected', () async {
      final envelope = await aliceCipher.encrypt('hello bob'.codeUnits);
      await bobCipher.decrypt(envelope); // first delivery: fine

      expect(
        () => bobCipher.decrypt(envelope), // replay
        throwsA(isA<ReplayDetectedException>()),
      );
    });

    test('out-of-order-behind envelope is rejected', () async {
      final e1 = await aliceCipher.encrypt('one'.codeUnits);
      final e2 = await aliceCipher.encrypt('two'.codeUnits);

      await bobCipher.decrypt(e2); // deliver newer first
      expect(
        () => bobCipher.decrypt(e1), // then an older one arrives
        throwsA(isA<ReplayDetectedException>()),
      );
    });
  });
}
