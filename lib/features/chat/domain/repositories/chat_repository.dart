import 'package:two_person_app/core/utils/result.dart';
import 'package:two_person_app/features/chat/domain/entities/message.dart';

abstract class ChatRepository {
  /// Local-first: writes to the encrypted DB immediately, independent
  /// of whether the peer is currently reachable. Actual delivery over
  /// the data channel is handled by the signaling module and updates
  /// [deliveredAt]/[readAt] asynchronously via [watchMessages].
  Future<Result<ChatMessage>> sendMessage({
    required String content,
    String? replyToMessageId,
  });

  Future<Result<void>> editMessage(String messageId, String newContent);

  Future<Result<void>> deleteForMe(String messageId);

  /// Only possible while the peer is online — there is no queued
  /// "delete for both" once they've gone offline and come back with
  /// the message already read; that's a deliberate consequence of the
  /// no-store-and-forward design.
  Future<Result<void>> deleteForBoth(String messageId);

  Future<Result<void>> pinMessage(String messageId, bool pinned);

  Future<Result<void>> addReaction(String messageId, String emoji);

  Stream<List<ChatMessage>> watchMessages({String? threadRootId});

  Future<List<ChatMessage>> searchMessages(String query);
}
