import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import 'package:two_person_app/core/database/app_database.dart';
import 'package:two_person_app/core/error/failures.dart';
import 'package:two_person_app/core/utils/result.dart';
import 'package:two_person_app/features/pairing/domain/entities/device_identity.dart';
import 'package:two_person_app/features/pairing/domain/entities/encrypted_channel.dart';
import 'package:two_person_app/features/pairing/domain/repositories/pairing_repository.dart';

import 'crypto/fingerprint.dart';
import 'crypto/identity_key_service.dart';
import 'crypto/pairing_payload.dart';
import 'crypto/session_crypto_service.dart';
import 'signaling/encrypted_transport.dart';
import 'signaling/webrtc_connection_manager.dart';

const _peerIdentityKeyType = 'peer_identity_pub';
const _peerSigningKeyType = 'peer_signing_pub';

/// Real key generation, signed pairing payloads, WebRTC offer/answer
/// exchange, and session-key derivation are all wired up here — this
/// is the module that actually establishes the encrypted channel chat
/// sends messages over.
///
/// TURN is hardcoded off — this app has no settings UI to toggle it.
class PairingRepositoryImpl implements PairingRepository {
  final AppDatabase db;
  final IdentityKeyService identityKeyService;
  final _uuid = const Uuid();
  final _sessionKeyExchange = SessionKeyExchange();

  static const _turnEnabled = false;

  final _connectionManager = WebRtcConnectionManager();
  EncryptedTransport? _transport;

  /// In-memory pairing-in-progress state. Not persisted — if the app
  /// is killed mid-pairing, the user starts a new invite; pairing is a
  /// short-lived flow, not steady-state app behavior.
  String? _pendingOutgoingSessionId;
  SimpleKeyPair? _pendingEphemeralKeyPair;

  PairingRepositoryImpl({required this.db, required this.identityKeyService});

  @override
  Future<bool> get isPaired async {
    final peerKey = await (db.select(db.keyRecords)
          ..where((t) => t.keyType.equals(_peerIdentityKeyType)))
        .getSingleOrNull();
    return peerKey != null;
  }

  @override
  Future<DeviceIdentity> get localIdentity async {
    final identity = await identityKeyService.getOrCreateIdentity();
    // Fingerprint is a property of a *pair* of keys (this device's +
    // the peer's) — meaningless for a standalone local identity before
    // pairing, so left blank here. Read it from [peerIdentity] once paired.
    return DeviceIdentity(
      deviceId: identity.deviceId,
      identityPublicKeyBase64: await identity.identityPublicKeyBase64,
      signingPublicKeyBase64: await identity.signingPublicKeyBase64,
      fingerprint: '',
      fingerprintVerified: false,
      pairedAt: DateTime.now(),
    );
  }

  @override
  Future<DeviceIdentity?> get peerIdentity async {
    final identityRow = await (db.select(db.keyRecords)
          ..where((t) => t.keyType.equals(_peerIdentityKeyType)))
        .getSingleOrNull();
    final signingRow = await (db.select(db.keyRecords)
          ..where((t) => t.keyType.equals(_peerSigningKeyType)))
        .getSingleOrNull();
    if (identityRow == null || signingRow == null) return null;

    return DeviceIdentity(
      // Now the peer's actual transmitted device ID (see
      // _persistPeerKeys) rather than a locally-generated row UUID
      // that happened to have no relationship to the peer at all.
      deviceId: identityRow.id,
      identityPublicKeyBase64: identityRow.publicKeyBase64 ?? '',
      signingPublicKeyBase64: signingRow.publicKeyBase64 ?? '',
      fingerprint: identityRow.fingerprint ?? '',
      fingerprintVerified: identityRow.fingerprintVerifiedByUser,
      pairedAt: identityRow.createdAt,
    );
  }

  @override
  Future<Result<String>> createInviteLink() async {
    try {
      final identity = await identityKeyService.getOrCreateIdentity();
      final sessionId = _uuid.v4();

      final offer = await _connectionManager.createOffer(turnEnabled: _turnEnabled);
      final ephemeralKeyPair = await _sessionKeyExchange.generateEphemeral();
      final ephemeralPub = await ephemeralKeyPair.extractPublicKey();

      final payload = await PairingPayload.createSigned(
        deviceId: identity.deviceId,
        identityPublicKeyBase64: await identity.identityPublicKeyBase64,
        signingPublicKeyBase64: await identity.signingPublicKeyBase64,
        sessionId: sessionId,
        createdAt: DateTime.now(),
        signingKeyPair: identity.signingKeyPair,
        signalingData: {
          'offer': offer.toJson(),
          'ephemeralPublicKey': base64Encode(ephemeralPub.bytes),
        },
      );

      _pendingOutgoingSessionId = sessionId;
      _pendingEphemeralKeyPair = ephemeralKeyPair;
      return Ok(payload.toJson());
    } catch (e) {
      return Err(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Result<String>> acceptInvite(String invitePayload) async {
    final payload = PairingPayload.tryParse(invitePayload);
    if (payload == null) return const Err(SignalingPayloadInvalidFailure());

    final signatureValid = await payload.verifySignature();
    if (!signatureValid) return const Err(SignalingPayloadInvalidFailure());

    final signalingData = payload.signalingData;
    if (signalingData == null ||
        signalingData['offer'] == null ||
        signalingData['ephemeralPublicKey'] == null) {
      return const Err(SignalingPayloadInvalidFailure());
    }

    // Bound the replay window: an old invite that was intercepted (or
    // simply never redeemed) shouldn't be usable indefinitely. This
    // doesn't protect any cryptographic material — ephemeral session
    // keys are freshly generated on every createOffer/createAnswer
    // call regardless — it just closes off pointless replay attempts.
    if (DateTime.now().toUtc().difference(payload.createdAt.toUtc()).abs() >
        const Duration(minutes: 10)) {
      return const Err(SignalingPayloadInvalidFailure());
    }

    try {
      final identity = await identityKeyService.getOrCreateIdentity();
      final fingerprint = await FingerprintService.compute(
        localIdentityPublicKey:
            base64Decode(await identity.identityPublicKeyBase64),
        peerIdentityPublicKey: base64Decode(payload.identityPublicKeyBase64),
      );

      await _persistPeerKeys(
        peerDeviceId: payload.deviceId,
        identityPublicKeyBase64: payload.identityPublicKeyBase64,
        signingPublicKeyBase64: payload.signingPublicKeyBase64,
        fingerprint: fingerprint,
      );

      // WebRTC: answer the offer.
      final remoteOffer = SignalingOffer.fromJson(
        signalingData['offer'] as Map<String, dynamic>,
      );
      final answer = await _connectionManager.createAnswerForOffer(
        remoteOffer,
        turnEnabled: _turnEnabled,
      );

      // Session keys: responder side.
      final localEphemeral = await _sessionKeyExchange.generateEphemeral();
      final localEphemeralPub = await localEphemeral.extractPublicKey();
      final peerEphemeralPub = SimplePublicKey(
        base64Decode(signalingData['ephemeralPublicKey'] as String),
        type: KeyPairType.x25519,
      );
      final sessionKeys = await _sessionKeyExchange.deriveSessionKeys(
        localEphemeralKeyPair: localEphemeral,
        remoteEphemeralPublicKey: peerEphemeralPub,
        isInitiator: false,
      );
      // Dispose any previous transport before replacing it — without
      // this, retrying pairing (e.g. after a failed first attempt)
      // would leak the old transport's stream subscription and
      // session cipher every time.
      await _transport?.dispose();
      _transport = EncryptedTransport(_connectionManager)
        ..attachSessionCipher(SessionCipher(sessionKeys));

      final response = await PairingPayload.createSigned(
        deviceId: identity.deviceId,
        identityPublicKeyBase64: await identity.identityPublicKeyBase64,
        signingPublicKeyBase64: await identity.signingPublicKeyBase64,
        sessionId: payload.sessionId,
        createdAt: DateTime.now(),
        signingKeyPair: identity.signingKeyPair,
        signalingData: {
          'answer': answer.toJson(),
          'ephemeralPublicKey': base64Encode(localEphemeralPub.bytes),
        },
      );

      return Ok(response.toJson());
    } catch (e) {
      return Err(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Result<DeviceIdentity>> completePairing(String responsePayload) async {
    final payload = PairingPayload.tryParse(responsePayload);
    if (payload == null) return const Err(SignalingPayloadInvalidFailure());
    if (payload.sessionId != _pendingOutgoingSessionId) {
      return const Err(SignalingPayloadInvalidFailure());
    }

    final signatureValid = await payload.verifySignature();
    if (!signatureValid) return const Err(SignalingPayloadInvalidFailure());

    final signalingData = payload.signalingData;
    final pendingEphemeral = _pendingEphemeralKeyPair;
    if (signalingData == null ||
        signalingData['answer'] == null ||
        signalingData['ephemeralPublicKey'] == null ||
        pendingEphemeral == null) {
      return const Err(SignalingPayloadInvalidFailure());
    }

    try {
      final identity = await identityKeyService.getOrCreateIdentity();
      final fingerprint = await FingerprintService.compute(
        localIdentityPublicKey:
            base64Decode(await identity.identityPublicKeyBase64),
        peerIdentityPublicKey: base64Decode(payload.identityPublicKeyBase64),
      );

      await _persistPeerKeys(
        peerDeviceId: payload.deviceId,
        identityPublicKeyBase64: payload.identityPublicKeyBase64,
        signingPublicKeyBase64: payload.signingPublicKeyBase64,
        fingerprint: fingerprint,
      );

      // WebRTC: apply the answer.
      final answer = SignalingAnswer.fromJson(
        signalingData['answer'] as Map<String, dynamic>,
      );
      await _connectionManager.applyAnswer(answer);

      // Session keys: initiator side.
      final peerEphemeralPub = SimplePublicKey(
        base64Decode(signalingData['ephemeralPublicKey'] as String),
        type: KeyPairType.x25519,
      );
      final sessionKeys = await _sessionKeyExchange.deriveSessionKeys(
        localEphemeralKeyPair: pendingEphemeral,
        remoteEphemeralPublicKey: peerEphemeralPub,
        isInitiator: true,
      );
      // Dispose any previous transport before replacing it — without
      // this, retrying pairing (e.g. after a failed first attempt)
      // would leak the old transport's stream subscription and
      // session cipher every time.
      await _transport?.dispose();
      _transport = EncryptedTransport(_connectionManager)
        ..attachSessionCipher(SessionCipher(sessionKeys));

      _pendingOutgoingSessionId = null;
      _pendingEphemeralKeyPair = null;

      return Ok(DeviceIdentity(
        deviceId: payload.deviceId,
        identityPublicKeyBase64: payload.identityPublicKeyBase64,
        signingPublicKeyBase64: payload.signingPublicKeyBase64,
        fingerprint: fingerprint,
        fingerprintVerified: false,
        pairedAt: DateTime.now(),
      ));
    } catch (e) {
      return Err(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> confirmFingerprintVerified() async {
    final rows = await (db.update(db.keyRecords)
          ..where((t) => t.keyType.equals(_peerIdentityKeyType)))
        .write(const KeyRecordsCompanion(
      fingerprintVerifiedByUser: Value(true),
    ));
    if (rows == 0) return const Err(UnknownFailure('No peer key on record.'));
    return const Ok(null);
  }

  @override
  Stream<bool> get connectionStatus => _connectionManager.connectionState
      .map((s) => s == RTCPeerConnectionState.RTCPeerConnectionStateConnected);

  @override
  EncryptedChannel? get transport => _transport;

  /// Called on every session establishment — not just first pairing.
  /// With no server, reconnecting after the app is closed and reopened
  /// means a brand new WebRTC handshake, which runs this same code
  /// path. Wiping and recreating the peer's key rows every time would
  /// silently reset [fingerprintVerifiedByUser] to false on every
  /// reconnect, forcing the user to re-verify a safety number that
  /// hasn't actually changed. So: same peer key as last time -> leave
  /// the existing row (and its verified flag) alone. Different key ->
  /// genuinely a new/changed peer, which does need fresh verification.
  Future<void> _persistPeerKeys({
    required String peerDeviceId,
    required String identityPublicKeyBase64,
    required String signingPublicKeyBase64,
    required String fingerprint,
  }) async {
    final existing = await (db.select(db.keyRecords)
          ..where((t) => t.keyType.equals(_peerIdentityKeyType)))
        .getSingleOrNull();

    if (existing != null && existing.publicKeyBase64 == identityPublicKeyBase64) {
      return; // same peer as before — nothing to update, verified flag stays.
    }

    await (db.delete(db.keyRecords)
          ..where((t) =>
              t.keyType.equals(_peerIdentityKeyType) |
              t.keyType.equals(_peerSigningKeyType)))
        .go();

    final now = DateTime.now();
    // The identity row's id IS the peer's real device id (not a
    // random UUID) — this was previously a bug: a random id was
    // generated here, the peer's actual transmitted deviceId was
    // computed and then silently discarded, and peerIdentity.deviceId
    // returned a value with no relationship to the real peer at all.
    await db.into(db.keyRecords).insert(KeyRecordsCompanion.insert(
          id: peerDeviceId,
          keyType: _peerIdentityKeyType,
          publicKeyBase64: Value(identityPublicKeyBase64),
          fingerprint: Value(fingerprint),
          createdAt: now,
        ));
    await db.into(db.keyRecords).insert(KeyRecordsCompanion.insert(
          id: _uuid.v4(),
          keyType: _peerSigningKeyType,
          publicKeyBase64: Value(signingPublicKeyBase64),
          fingerprint: Value(fingerprint),
          createdAt: now,
        ));
  }
}
