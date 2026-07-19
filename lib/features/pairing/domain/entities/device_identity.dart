import 'package:equatable/equatable.dart';

/// Represents either "this device" or "the paired device" — the app
/// only ever has at most these two [DeviceIdentity] instances in memory.
///
/// Note what's absent: no username, no display handle, no avatar URL.
/// Presentation code should let the user set a *local* nickname for
/// their paired person, but that nickname is never transmitted — it's
/// not part of identity, it's a local label.
class DeviceIdentity extends Equatable {
  final String deviceId;
  final String identityPublicKeyBase64; // X25519
  final String signingPublicKeyBase64; // Ed25519
  final String fingerprint; // human-verifiable, derived via SHA-256
  final bool fingerprintVerified;
  final DateTime pairedAt;

  const DeviceIdentity({
    required this.deviceId,
    required this.identityPublicKeyBase64,
    required this.signingPublicKeyBase64,
    required this.fingerprint,
    required this.fingerprintVerified,
    required this.pairedAt,
  });

  @override
  List<Object?> get props => [
        deviceId,
        identityPublicKeyBase64,
        signingPublicKeyBase64,
        fingerprint,
        fingerprintVerified,
        pairedAt,
      ];
}
