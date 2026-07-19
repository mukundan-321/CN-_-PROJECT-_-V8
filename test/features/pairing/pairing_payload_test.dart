import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:two_person_app/features/pairing/data/crypto/pairing_payload.dart';

void main() {
  group('PairingPayload', () {
    late SimpleKeyPair signingKeyPair;

    setUp(() async {
      signingKeyPair = await Ed25519().newKeyPair();
    });

    Future<PairingPayload> makePayload({Map<String, dynamic>? signalingData}) {
      return PairingPayload.createSigned(
        deviceId: 'device-a',
        identityPublicKeyBase64: 'aWRlbnRpdHlrZXk=',
        signingPublicKeyBase64: 'c2lnbmluZ2tleQ==',
        sessionId: 'session-123',
        createdAt: DateTime.utc(2026, 1, 1),
        signingKeyPair: signingKeyPair,
        signalingData: signalingData,
      );
    }

    test('a freshly signed payload verifies', () async {
      final payload = await makePayload();
      expect(await payload.verifySignature(), isTrue);
    });

    test('round-trips through JSON and still verifies', () async {
      final payload = await makePayload(signalingData: {'offer': 'sdp-blob'});
      final json = payload.toJson();
      final parsed = PairingPayload.tryParse(json);

      expect(parsed, isNotNull);
      expect(parsed!.deviceId, payload.deviceId);
      expect(parsed.signalingData, {'offer': 'sdp-blob'});
      expect(await parsed.verifySignature(), isTrue);
    });

    test('tampering with a field breaks verification', () async {
      final payload = await makePayload();
      final tampered = PairingPayload(
        deviceId: 'device-EVIL', // changed after signing
        identityPublicKeyBase64: payload.identityPublicKeyBase64,
        signingPublicKeyBase64: payload.signingPublicKeyBase64,
        sessionId: payload.sessionId,
        createdAt: payload.createdAt,
        signalingData: payload.signalingData,
        signatureBase64: payload.signatureBase64, // stale signature
      );
      expect(await tampered.verifySignature(), isFalse);
    });

    test('tryParse returns null for garbage input', () {
      expect(PairingPayload.tryParse('not json at all'), isNull);
      expect(PairingPayload.tryParse('{"incomplete": true}'), isNull);
    });
  });
}
