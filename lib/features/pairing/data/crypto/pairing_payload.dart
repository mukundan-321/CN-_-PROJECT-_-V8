import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// What actually gets put in a QR code / invite link / typed pairing
/// code. Signed with the sender's Ed25519 signing key so the payload
/// can't be silently modified in transit (e.g. by whatever app the
/// invite link gets pasted through) — that's a tamper check, not an
/// identity check. Note this signature can't itself prove the payload
/// came from the *right* person; that's what [FingerprintService]'s
/// out-of-band verification step is for. Signed-but-unverified is the
/// TOFU (trust-on-first-use) state pairing starts in.
///
/// [signalingData] is an intentionally opaque JSON blob — the WebRTC
/// offer/answer/ICE-candidate payload — populated by the signaling
/// module. This class only knows it needs to be carried and signed
/// alongside the keys, not what's inside it.
class PairingPayload {
  final String deviceId;
  final String identityPublicKeyBase64; // X25519
  final String signingPublicKeyBase64; // Ed25519
  final String sessionId;
  final DateTime createdAt;
  final Map<String, dynamic>? signalingData;
  final String signatureBase64;

  const PairingPayload({
    required this.deviceId,
    required this.identityPublicKeyBase64,
    required this.signingPublicKeyBase64,
    required this.sessionId,
    required this.createdAt,
    required this.signatureBase64,
    this.signalingData,
  });

  /// Canonical bytes that get signed / verified — deliberately excludes
  /// [signatureBase64] itself, and uses a fixed field order so both
  /// sides always sign/verify the same bytes.
  static List<int> _canonicalBytes({
    required String deviceId,
    required String identityPublicKeyBase64,
    required String signingPublicKeyBase64,
    required String sessionId,
    required DateTime createdAt,
    Map<String, dynamic>? signalingData,
  }) {
    final map = {
      'deviceId': deviceId,
      'identityPublicKey': identityPublicKeyBase64,
      'signingPublicKey': signingPublicKeyBase64,
      'sessionId': sessionId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'signalingData': signalingData,
    };
    return utf8.encode(jsonEncode(map));
  }

  static Future<PairingPayload> createSigned({
    required String deviceId,
    required String identityPublicKeyBase64,
    required String signingPublicKeyBase64,
    required String sessionId,
    required DateTime createdAt,
    required SimpleKeyPair signingKeyPair,
    Map<String, dynamic>? signalingData,
  }) async {
    final bytes = _canonicalBytes(
      deviceId: deviceId,
      identityPublicKeyBase64: identityPublicKeyBase64,
      signingPublicKeyBase64: signingPublicKeyBase64,
      sessionId: sessionId,
      createdAt: createdAt,
      signalingData: signalingData,
    );
    final signature = await Ed25519().sign(bytes, keyPair: signingKeyPair);
    return PairingPayload(
      deviceId: deviceId,
      identityPublicKeyBase64: identityPublicKeyBase64,
      signingPublicKeyBase64: signingPublicKeyBase64,
      sessionId: sessionId,
      createdAt: createdAt,
      signalingData: signalingData,
      signatureBase64: base64Encode(signature.bytes),
    );
  }

  /// Verifies the signature against the *embedded* signing public key.
  /// This only proves internal consistency (the payload wasn't altered
  /// after signing) — it does NOT prove the embedded key belongs to
  /// the person the user thinks they're pairing with. Callers must
  /// still run fingerprint verification before trusting this payload.
  Future<bool> verifySignature() async {
    try {
      final bytes = _canonicalBytes(
        deviceId: deviceId,
        identityPublicKeyBase64: identityPublicKeyBase64,
        signingPublicKeyBase64: signingPublicKeyBase64,
        sessionId: sessionId,
        createdAt: createdAt,
        signalingData: signalingData,
      );
      final publicKey =
          SimplePublicKey(base64Decode(signingPublicKeyBase64), type: KeyPairType.ed25519);
      final signature = Signature(base64Decode(signatureBase64), publicKey: publicKey);
      return Ed25519().verify(bytes, signature: signature);
    } catch (_) {
      return false;
    }
  }

  String toJson() => jsonEncode({
        'deviceId': deviceId,
        'identityPublicKey': identityPublicKeyBase64,
        'signingPublicKey': signingPublicKeyBase64,
        'sessionId': sessionId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'signalingData': signalingData,
        'signature': signatureBase64,
      });

  static PairingPayload? tryParse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PairingPayload(
        deviceId: map['deviceId'] as String,
        identityPublicKeyBase64: map['identityPublicKey'] as String,
        signingPublicKeyBase64: map['signingPublicKey'] as String,
        sessionId: map['sessionId'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        signalingData: map['signalingData'] as Map<String, dynamic>?,
        signatureBase64: map['signature'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
