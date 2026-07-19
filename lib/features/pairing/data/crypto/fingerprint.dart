import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Computes a human-verifiable fingerprint ("safety number") from both
/// devices' long-term X25519 identity public keys.
///
/// This is the actual trust anchor for pairing. Everything else in the
/// pairing flow — QR codes, invite links, pairing codes — gets a
/// device onto a shared transport and exchanges keys, but none of it
/// is authenticated against anything the user can independently
/// verify. Reading this fingerprint aloud (or comparing it side by
/// side) over a channel the attacker doesn't control — in person, a
/// phone call where you recognize the voice — is what actually rules
/// out a machine-in-the-middle during pairing.
class FingerprintService {
  static const _digitGroups = 15; // Signal-style: N groups of 5 digits

  /// Deterministic regardless of which device calls it: keys are
  /// sorted before hashing, so both sides compute the identical string.
  static Future<String> compute({
    required List<int> localIdentityPublicKey,
    required List<int> peerIdentityPublicKey,
  }) async {
    final ordered = _sortTwo(localIdentityPublicKey, peerIdentityPublicKey);
    final combined = [...ordered.$1, ...ordered.$2];
    final digest = await Sha256().hash(combined);
    return _formatAsDigitGroups(Uint8List.fromList(digest.bytes));
  }

  static (List<int>, List<int>) _sortTwo(List<int> a, List<int> b) {
    final aB64 = base64Encode(a);
    final bB64 = base64Encode(b);
    return aB64.compareTo(bB64) <= 0 ? (a, b) : (b, a);
  }

  /// Signal's approach: derive a run of digits from the hash and chunk
  /// it into groups of 5 for easy reading/comparison. Simplified here
  /// (single SHA-256 pass instead of an iterated hash) — sufficient
  /// for this app's threat model of "did pairing succeed against the
  /// device I meant, not some other one," not intended as a drop-in
  /// replacement for Signal's own protocol.
  static String _formatAsDigitGroups(Uint8List hash) {
    final buffer = StringBuffer();
    var acc = BigInt.zero;
    for (final byte in hash) {
      acc = (acc << 8) | BigInt.from(byte);
    }
    final totalDigits = _digitGroups * 5;
    var digits = acc.toString();
    if (digits.length < totalDigits) {
      digits = digits.padLeft(totalDigits, '0');
    } else {
      digits = digits.substring(0, totalDigits);
    }
    for (var i = 0; i < totalDigits; i += 5) {
      if (i > 0) buffer.write(' ');
      buffer.write(digits.substring(i, i + 5));
    }
    return buffer.toString();
  }
}
