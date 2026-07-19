import 'package:two_person_app/core/utils/result.dart';
import 'package:two_person_app/features/pairing/domain/entities/device_identity.dart';
import 'package:two_person_app/features/pairing/domain/entities/encrypted_channel.dart';

/// Contract for identity, key exchange, and the live connection to the
/// one other person this app talks to. Chat depends only on this
/// interface — never on WebRTC or crypto types directly.
abstract class PairingRepository {
  /// Whether this device already has a paired peer (max: 1, ever).
  Future<bool> get isPaired;

  /// This device's own identity (generated on first launch).
  Future<DeviceIdentity> get localIdentity;

  /// The paired peer's identity, if pairing has completed.
  Future<DeviceIdentity?> get peerIdentity;

  /// Starts a new pairing/session and returns an invite payload
  /// (offer + ICE candidates + public key + session id) to be shared
  /// via QR, deep link, or external transport.
  Future<Result<String>> createInviteLink();

  /// Consumes an invite payload from the other device, generates the
  /// answer, and returns the response payload to send back.
  Future<Result<String>> acceptInvite(String invitePayload);

  /// Finalizes pairing/reconnection once the response payload is applied.
  Future<Result<DeviceIdentity>> completePairing(String responsePayload);

  /// User-facing manual verification of the peer's fingerprint
  /// (read-aloud / compare-side-by-side flow). Only meaningful the
  /// first time two devices pair.
  Future<Result<void>> confirmFingerprintVerified();

  /// True once a live encrypted data channel to the peer is open for
  /// *this session*. Resets to false on every app relaunch — there is
  /// no server to stay connected through between launches.
  Stream<bool> get connectionStatus;

  /// The live encrypted channel, once session keys are established
  /// and the data channel is open. Null before that point.
  EncryptedChannel? get transport;
}
