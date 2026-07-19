import 'package:drift/drift.dart';

/// Deliberately does NOT store private key bytes, even though the DB
/// file itself is SQLCipher-encrypted. Private keys live in the
/// platform secure enclave (Keychain / Android Keystore) via the
/// crypto module, never in this database. This table only tracks:
/// - the peer's long-term public identity/signing keys (from pairing)
/// - the verified fingerprint
/// - session key rotation bookkeeping (not the session keys themselves)
class KeyRecords extends Table {
  TextColumn get id => text()();
  TextColumn get keyType =>
      text()(); // 'peer_identity_pub' | 'peer_signing_pub' | 'session_meta'
  TextColumn get publicKeyBase64 => text().nullable()();
  TextColumn get fingerprint => text().nullable()();
  BoolColumn get fingerprintVerifiedByUser =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get rotatedAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()(); // JSON-encoded where needed

  @override
  Set<Column> get primaryKey => {key};
}
