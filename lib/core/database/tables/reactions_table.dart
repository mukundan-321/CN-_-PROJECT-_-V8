import 'package:drift/drift.dart';

/// Reactions on chat messages. [targetType] is kept even though
/// 'message' is the only value used today — reactions are structurally
/// generic (any target id + type), so extending to other content types
/// later doesn't require a schema change.
class Reactions extends Table {
  TextColumn get id => text()();
  TextColumn get targetId => text()();
  TextColumn get targetType => text()(); // 'message' | 'story' | 'feed_post'
  TextColumn get reactorDeviceId => text()();
  TextColumn get emoji => text()();
  DateTimeColumn get reactedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
