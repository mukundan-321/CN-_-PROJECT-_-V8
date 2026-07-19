import 'package:flutter_test/flutter_test.dart';
import 'package:two_person_app/features/pairing/data/crypto/fingerprint.dart';

void main() {
  group('FingerprintService', () {
    final keyA = List<int>.generate(32, (i) => i);
    final keyB = List<int>.generate(32, (i) => 255 - i);

    test('is deterministic for the same key pair', () async {
      final f1 = await FingerprintService.compute(
        localIdentityPublicKey: keyA,
        peerIdentityPublicKey: keyB,
      );
      final f2 = await FingerprintService.compute(
        localIdentityPublicKey: keyA,
        peerIdentityPublicKey: keyB,
      );
      expect(f1, f2);
    });

    test('is identical regardless of which side computes it', () async {
      // This is the property that actually matters: both devices must
      // arrive at the same displayed number without coordinating who
      // is "local" and who is "peer".
      final fromA = await FingerprintService.compute(
        localIdentityPublicKey: keyA,
        peerIdentityPublicKey: keyB,
      );
      final fromB = await FingerprintService.compute(
        localIdentityPublicKey: keyB,
        peerIdentityPublicKey: keyA,
      );
      expect(fromA, fromB);
    });

    test('differs for different key pairs', () async {
      final keyC = List<int>.generate(32, (i) => i * 2 % 256);
      final f1 = await FingerprintService.compute(
        localIdentityPublicKey: keyA,
        peerIdentityPublicKey: keyB,
      );
      final f2 = await FingerprintService.compute(
        localIdentityPublicKey: keyA,
        peerIdentityPublicKey: keyC,
      );
      expect(f1, isNot(f2));
    });

    test('formats as space-separated 5-digit groups', () async {
      final f = await FingerprintService.compute(
        localIdentityPublicKey: keyA,
        peerIdentityPublicKey: keyB,
      );
      final groups = f.split(' ');
      expect(groups, hasLength(15));
      for (final g in groups) {
        expect(g.length, 5);
        expect(int.tryParse(g), isNotNull);
      }
    });
  });
}
