import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:two_person_app/core/database/app_database.dart';
import 'package:two_person_app/core/error/failures.dart';
import 'package:two_person_app/core/utils/result.dart';
import 'package:two_person_app/features/chat/domain/entities/message.dart';
import 'package:two_person_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:two_person_app/features/pairing/domain/repositories/pairing_repository.dart';

const _localDeviceIdPlaceholder = 'local';
const _peerDeviceIdPlaceholder = 'peer';

/// Local-first, as documented on the [ChatRepository] interface:
/// every write lands in the encrypted DB immediately. Delivery over
/// the wire is best-effort layered on top — [sendMessage] never fails
/// just because the peer is offline, but [deleteForBoth] does, since
/// that operation is meaningless without the peer actually receiving it.
class ChatRepositoryImpl implements ChatRepository {
  final AppDatabase db;
  final PairingRepository pairingRepository;
  final _uuid = const Uuid();

  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<List<int>>? _incomingSub;

  ChatRepositoryImpl({required this.db, required this.pairingRepository}) {
    _connectionSub = pairingRepository.connectionStatus.listen((connected) {
      _incomingSub?.cancel();
      final transport = pairingRepository.transport;
      if (connected && transport != null) {
        _incomingSub = transport.decryptedIncoming.listen(_handleIncomingFrame);
      }
    });
  }

  void dispose() {
    _connectionSub?.cancel();
    _incomingSub?.cancel();
  }

  Future<void> _handleIncomingFrame(List<int> bytes) async {
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      switch (map['type'] as String?) {
        case 'message':
          await db.into(db.messages).insert(
                MessagesCompanion.insert(
                  id: map['id'] as String,
                  senderDeviceId: _peerDeviceIdPlaceholder,
                  content: Value(map['content'] as String?),
                  replyToMessageId: Value(map['replyToMessageId'] as String?),
                  sentAt: DateTime.parse(map['sentAt'] as String),
                ),
                mode: InsertMode.insertOrIgnore,
              );
          break;
        case 'edit':
          // Only the message's original sender may edit it — without
          // this check, the peer could send an 'edit' frame for a
          // message ID the *local* user wrote, and this would have
          // silently rewritten it.
          await (db.update(db.messages)
                ..where((t) =>
                    t.id.equals(map['id'] as String) &
                    t.senderDeviceId.equals(_peerDeviceIdPlaceholder)))
              .write(MessagesCompanion(
            content: Value(map['content'] as String),
            isEdited: const Value(true),
            editedAt: Value(DateTime.now()),
          ));
          break;
        case 'delete_for_both':
          // Same authorization check as 'edit' above — the peer can
          // only delete-for-both messages they themselves sent.
          await (db.update(db.messages)
                ..where((t) =>
                    t.id.equals(map['id'] as String) &
                    t.senderDeviceId.equals(_peerDeviceIdPlaceholder)))
              .write(const MessagesCompanion(
            isDeletedForBoth: Value(true),
            isDeletedForMe: Value(true),
          ));
          break;
        case 'reaction':
          await db.into(db.reactions).insert(ReactionsCompanion.insert(
                id: _uuid.v4(),
                targetId: map['targetId'] as String,
                targetType: 'message',
                reactorDeviceId: _peerDeviceIdPlaceholder,
                emoji: map['emoji'] as String,
                reactedAt: DateTime.now(),
              ));
          break;
      }
    } catch (_) {
      // Malformed frame from the peer — drop it. The AEAD layer below
      // this already guarantees authenticity; this only guards against
      // an authenticated-but-unparseable application-level message.
    }
  }

  Future<bool> _tryPushOverWire(Map<String, dynamic> frame) async {
    final transport = pairingRepository.transport;
    if (transport == null) return false;
    try {
      await transport.send(utf8.encode(jsonEncode(frame)));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Result<ChatMessage>> sendMessage({
    required String content,
    String? replyToMessageId,
  }) async {
    try {
      final id = _uuid.v4();
      final now = DateTime.now();
      await db.into(db.messages).insert(MessagesCompanion.insert(
            id: id,
            senderDeviceId: _localDeviceIdPlaceholder,
            content: Value(content),
            replyToMessageId: Value(replyToMessageId),
            sentAt: now,
          ));

      final delivered = await _tryPushOverWire({
        'type': 'message',
        'id': id,
        'content': content,
        'replyToMessageId': replyToMessageId,
        'sentAt': now.toIso8601String(),
      });
      if (delivered) {
        await (db.update(db.messages)..where((t) => t.id.equals(id)))
            .write(MessagesCompanion(deliveredAt: Value(DateTime.now())));
      }

      return Ok(ChatMessage(
        id: id,
        senderDeviceId: _localDeviceIdPlaceholder,
        content: content,
        replyToMessageId: replyToMessageId,
        sentAt: now,
        deliveredAt: delivered ? DateTime.now() : null,
      ));
    } catch (e) {
      return Err(LocalStorageFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> editMessage(String messageId, String newContent) async {
    final rows = await (db.update(db.messages)
          ..where((t) => t.id.equals(messageId)))
        .write(MessagesCompanion(
      content: Value(newContent),
      isEdited: const Value(true),
      editedAt: Value(DateTime.now()),
    ));
    if (rows == 0) return const Err(UnknownFailure('Message not found.'));
    await _tryPushOverWire({'type': 'edit', 'id': messageId, 'content': newContent});
    return const Ok(null);
  }

  @override
  Future<Result<void>> deleteForMe(String messageId) async {
    final rows = await (db.update(db.messages)
          ..where((t) => t.id.equals(messageId)))
        .write(const MessagesCompanion(isDeletedForMe: Value(true)));
    if (rows == 0) return const Err(UnknownFailure('Message not found.'));
    return const Ok(null);
  }

  @override
  Future<Result<void>> deleteForBoth(String messageId) async {
    // Unlike sendMessage, this genuinely requires the peer to be
    // online — there is no queued "delete for both" once they've gone
    // offline and possibly already read it. That's the deliberate
    // consequence of no store-and-forward.
    final delivered = await _tryPushOverWire({'type': 'delete_for_both', 'id': messageId});
    if (!delivered) return const Err(PeerOfflineFailure());

    await (db.update(db.messages)..where((t) => t.id.equals(messageId)))
        .write(const MessagesCompanion(isDeletedForBoth: Value(true), isDeletedForMe: Value(true)));
    return const Ok(null);
  }

  @override
  Future<Result<void>> pinMessage(String messageId, bool pinned) async {
    final rows = await (db.update(db.messages)
          ..where((t) => t.id.equals(messageId)))
        .write(MessagesCompanion(isPinned: Value(pinned)));
    if (rows == 0) return const Err(UnknownFailure('Message not found.'));
    return const Ok(null);
  }

  @override
  Future<Result<void>> addReaction(String messageId, String emoji) async {
    await db.into(db.reactions).insert(ReactionsCompanion.insert(
          id: _uuid.v4(),
          targetId: messageId,
          targetType: 'message',
          reactorDeviceId: _localDeviceIdPlaceholder,
          emoji: emoji,
          reactedAt: DateTime.now(),
        ));
    await _tryPushOverWire({'type': 'reaction', 'targetId': messageId, 'emoji': emoji});
    return const Ok(null);
  }

  @override
  Stream<List<ChatMessage>> watchMessages({String? threadRootId}) {
    final query = db.select(db.messages)
      ..where((t) => t.isDeletedForMe.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.sentAt)]);
    if (threadRootId != null) {
      query.where((t) => t.threadRootId.equals(threadRootId));
    }
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<List<ChatMessage>> searchMessages(String query) async {
    // Filtered in Dart rather than via SQL LIKE: a raw `LIKE '%$query%'`
    // treats literal `%`/`_` characters in the user's search text as
    // SQL wildcards, silently producing wrong results (e.g. searching
    // "50% off" would match unrelated text). Message volume for a
    // two-person chat is small enough that this doesn't need a SQL-side
    // index-backed search.
    final q = db.select(db.messages)
      ..where((t) => t.isDeletedForMe.equals(false));
    final rows = await q.get();
    final needle = query.toLowerCase();
    return rows
        .where((row) => (row.content ?? '').toLowerCase().contains(needle))
        .map(_toEntity)
        .toList();
  }

  ChatMessage _toEntity(Message row) => ChatMessage(
        id: row.id,
        senderDeviceId: row.senderDeviceId,
        content: row.content,
        replyToMessageId: row.replyToMessageId,
        threadRootId: row.threadRootId,
        isEdited: row.isEdited,
        isPinned: row.isPinned,
        isDeletedForMe: row.isDeletedForMe,
        isDeletedForBoth: row.isDeletedForBoth,
        sentAt: row.sentAt,
        deliveredAt: row.deliveredAt,
        readAt: row.readAt,
        mediaMetadataId: row.mediaMetadataId,
      );
}
