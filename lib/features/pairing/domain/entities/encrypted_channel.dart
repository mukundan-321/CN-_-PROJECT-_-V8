/// What chat depends on: plaintext bytes in, plaintext bytes out.
/// Everything about how that's secured (WebRTC data channel,
/// ChaCha20-Poly1305, session key rotation) lives behind this in the
/// data layer — chat never imports `pairing/data/...` directly, only
/// this interface.
abstract class EncryptedChannel {
  Future<void> send(List<int> plaintext);
  Stream<List<int>> get decryptedIncoming;
}
