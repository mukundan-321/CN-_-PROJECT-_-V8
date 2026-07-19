import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../crypto/session_crypto_service.dart';
import 'webrtc_connection_manager.dart';
import 'package:two_person_app/features/pairing/domain/entities/encrypted_channel.dart';

/// Sits between [WebRtcConnectionManager] (raw bytes over the data
/// channel) and chat. Every byte that leaves the device through this class is ChaCha20-Poly1305
/// sealed first; every byte that arrives is verified and decrypted
/// before anything downstream sees it. Malformed, tampered, or
/// replayed frames are dropped here — they never reach application code.
///
/// Wire framing is JSON+base64 for now (simple, debuggable). Large
/// media chunks should move to a compact binary frame format when the
/// media-transfer module is built — this scaffold optimizes for
/// correctness/readability of the crypto wiring, not throughput.
class EncryptedTransport implements EncryptedChannel {
  final WebRtcConnectionManager connection;
  SessionCipher? _cipher;
  StreamSubscription<Uint8List>? _rawSubscription;
  final _decryptedIncomingController = StreamController<List<int>>.broadcast();

  EncryptedTransport(this.connection);

  Stream<List<int>> get decryptedIncoming => _decryptedIncomingController.stream;

  /// Call once session keys are derived (right after pairing completes
  /// and the data channel opens). Nothing can be sent or received
  /// before this — there is no "send unencrypted, encrypt later" path.
  void attachSessionCipher(SessionCipher cipher) {
    _cipher = cipher;
    _rawSubscription = connection.incomingMessages.listen((raw) async {
      try {
        final envelope = _decodeEnvelope(raw);
        final plaintext = await cipher.decrypt(envelope);
        _decryptedIncomingController.add(plaintext);
      } catch (_) {
        // Tampered MAC, replay, or malformed frame — dropped silently
        // at the transport layer, never surfaced as partial/garbled
        // message content in chat.
      }
    });
  }

  Future<void> send(List<int> plaintext) async {
    final cipher = _cipher;
    if (cipher == null) {
      throw StateError('No session established — call attachSessionCipher first.');
    }
    final envelope = await cipher.encrypt(plaintext);
    await connection.sendRaw(_encodeEnvelope(envelope));
  }

  Future<void> dispose() async {
    await _rawSubscription?.cancel();
    await _decryptedIncomingController.close();
  }

  Uint8List _encodeEnvelope(EncryptedEnvelope e) {
    final json = jsonEncode({
      'c': e.counter,
      'n': base64Encode(e.nonce),
      'ct': base64Encode(e.ciphertext),
      'm': base64Encode(e.mac),
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  EncryptedEnvelope _decodeEnvelope(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return EncryptedEnvelope(
      counter: map['c'] as int,
      nonce: base64Decode(map['n'] as String),
      ciphertext: base64Decode(map['ct'] as String),
      mac: base64Decode(map['m'] as String),
    );
  }
}
