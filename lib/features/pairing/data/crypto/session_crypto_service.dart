import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown when a decrypt call receives a nonce/counter at or below one
/// already seen for that direction — i.e. someone replayed a captured
/// ciphertext. The caller should treat this the same as a failed MAC:
/// drop the message, do not surface any partial content.
class ReplayDetectedException implements Exception {
  final String message;
  ReplayDetectedException(this.message);
  @override
  String toString() => 'ReplayDetectedException: $message';
}

/// Two independent symmetric keys, one per direction, derived from a
/// single ephemeral ECDH exchange. Separate keys per direction avoid
/// nonce-reuse hazards that come from both peers encrypting with the
/// same key — each side only ever encrypts with its own send key.
class SessionKeys {
  final SecretKey sendKey;
  final SecretKey receiveKey;
  const SessionKeys({required this.sendKey, required this.receiveKey});
}

/// Establishes forward-secret session keys for one connection.
///
/// Forward secrecy here comes from two things working together: (1)
/// the ephemeral X25519 keypair is generated fresh for this session
/// and discarded — never persisted — once the session ends, and (2)
/// callers are expected to call [SessionKeyExchange.generateEphemeral]
/// again for every new session establishment (including reconnects
/// after a network change), per the spec's "session key rotation:
/// every session establishment."
class SessionKeyExchange {
  static const _initiatorToResponderInfo = 'two-person-app/i2r/v1';
  static const _responderToInitiatorInfo = 'two-person-app/r2i/v1';

  final _x25519 = X25519();

  Future<SimpleKeyPair> generateEphemeral() => _x25519.newKeyPair();

  /// [isInitiator] must be consistent with who sent the offer during
  /// signaling — both sides need to agree on which direction is
  /// "initiator -> responder" for the derived keys to match.
  Future<SessionKeys> deriveSessionKeys({
    required SimpleKeyPair localEphemeralKeyPair,
    required SimplePublicKey remoteEphemeralPublicKey,
    required bool isInitiator,
  }) async {
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: localEphemeralKeyPair,
      remotePublicKey: remoteEphemeralPublicKey,
    );

    final i2r = await _hkdfDerive(sharedSecret, _initiatorToResponderInfo);
    final r2i = await _hkdfDerive(sharedSecret, _responderToInitiatorInfo);

    return SessionKeys(
      sendKey: isInitiator ? i2r : r2i,
      receiveKey: isInitiator ? r2i : i2r,
    );
  }

  Future<SecretKey> _hkdfDerive(SecretKey sharedSecret, String info) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: sharedSecret,
      info: info.codeUnits,
      nonce: const <int>[], // salt intentionally empty: the shared
      // secret is already unique per session (fresh ephemeral keys),
      // so no additional salt is needed to avoid key reuse.
    );
  }
}

/// Encrypts/decrypts application payloads (messages, media chunks,
/// signaling follow-ups) for one open session, tracking nonces to
/// detect replay in either direction.
class SessionCipher {
  final SessionKeys keys;
  final _aead = Chacha20.poly1305Aead();

  int _sendCounter = 0;
  int _highestSeenReceiveCounter = -1;

  SessionCipher(this.keys);

  Future<EncryptedEnvelope> encrypt(List<int> plaintext) async {
    final counter = _sendCounter++;
    final nonce = _nonceFromCounter(counter);
    final box = await _aead.encrypt(plaintext, secretKey: keys.sendKey, nonce: nonce);
    return EncryptedEnvelope(
      counter: counter,
      ciphertext: box.cipherText,
      nonce: box.nonce,
      mac: box.mac.bytes,
    );
  }

  /// Throws [ReplayDetectedException] for a reused/out-of-order-behind
  /// counter, or [SecretBoxAuthenticationError] (from `cryptography`)
  /// if the MAC doesn't verify — i.e. tampered or corrupted data.
  Future<List<int>> decrypt(EncryptedEnvelope envelope) async {
    if (envelope.counter <= _highestSeenReceiveCounter) {
      throw ReplayDetectedException(
          'counter ${envelope.counter} <= highest seen $_highestSeenReceiveCounter');
    }
    final box = SecretBox(envelope.ciphertext, nonce: envelope.nonce, mac: Mac(envelope.mac));
    final plaintext = await _aead.decrypt(box, secretKey: keys.receiveKey);
    _highestSeenReceiveCounter = envelope.counter;
    return plaintext;
  }

  Uint8List _nonceFromCounter(int counter) {
    // 12-byte ChaCha20-Poly1305 nonce: 4 zero bytes + 8-byte big-endian
    // counter. Safe from reuse because (a) the key is unique per
    // session per direction, and (b) the counter is strictly
    // monotonic and never persisted/replayed across sessions — a new
    // session means a new ephemeral key, which resets the counter
    // against a completely different key.
    final nonce = Uint8List(12);
    final counterBytes = ByteData(8)..setUint64(0, counter, Endian.big);
    nonce.setRange(4, 12, counterBytes.buffer.asUint8List());
    return nonce;
  }
}

class EncryptedEnvelope {
  final int counter;
  final List<int> ciphertext;
  final List<int> nonce;
  final List<int> mac;

  const EncryptedEnvelope({
    required this.counter,
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });
}
