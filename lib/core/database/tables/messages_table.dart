import 'package:drift/drift.dart';

/// Messages are stored already-decrypted at rest, because the whole
/// database file is encrypted (SQLCipher) — there's no benefit to a
/// second layer of per-row encryption, and it would make search/edit
/// features far more painful for no real gain.
@TableIndex(name: 'messages_sent_at_idx', columns: {#sentAt})
class Messages extends Table {
  TextColumn get id => text()(); // UUID, generated on send/receive
  TextColumn get senderDeviceId => text()();
  TextColumn get content => text().nullable()(); // null if media-only
  // Deliberately NOT a SQL foreign key: this is a P2P app with no
  // guaranteed delivery order, so a reply can legitimately arrive
  // before the message it replies to has synced. An FK here would be
  // unenforced today (SQLite foreign key checks are off by default,
  // and this codebase never turns them on) but would silently start
  // rejecting valid out-of-order replies the moment anyone "correctly"
  // enables `PRAGMA foreign_keys = ON` later. Referential integrity
  // for this column is intentionally an application-level concern,
  // not a database-level one.
  TextColumn get replyToMessageId => text().nullable()();
  TextColumn get threadRootId => text().nullable()();
  BoolColumn get isEdited => boolean().withDefault(const Constant(false))();
  DateTimeColumn get editedAt => dateTime().nullable()();
  BoolColumn get isDeletedForMe =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDeletedForBoth =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  TextColumn get forwardedFromMessageId => text().nullable()();
  DateTimeColumn get sentAt => dateTime()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  // Also not a SQL foreign key, for the same out-of-order-delivery
  // reason as replyToMessageId above.
  TextColumn get mediaMetadataId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MediaMetadataRow')
class MediaMetadataTable extends Table {
  TextColumn get id => text()();
  TextColumn get localPath => text()(); // never leaves the device
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get checksumSha256 => text()();
  TextColumn get transferState => text()(); // pending/active/paused/done/failed
  RealColumn get transferProgress => real().withDefault(const Constant(0))();
  BoolColumn get isOriginalQuality =>
      boolean().withDefault(const Constant(true))();
  IntColumn get widthPx => integer().nullable()();
  IntColumn get heightPx => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
