import 'package:equatable/equatable.dart';

class ChatMessage extends Equatable {
  final String id;
  final String senderDeviceId;
  final String? content;
  final String? replyToMessageId;
  final String? threadRootId;
  final bool isEdited;
  final bool isPinned;
  final bool isDeletedForMe;
  final bool isDeletedForBoth;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String? mediaMetadataId;

  const ChatMessage({
    required this.id,
    required this.senderDeviceId,
    this.content,
    this.replyToMessageId,
    this.threadRootId,
    this.isEdited = false,
    this.isPinned = false,
    this.isDeletedForMe = false,
    this.isDeletedForBoth = false,
    required this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.mediaMetadataId,
  });

  bool get isMediaOnly => content == null && mediaMetadataId != null;

  @override
  List<Object?> get props => [
        id,
        senderDeviceId,
        content,
        replyToMessageId,
        threadRootId,
        isEdited,
        isPinned,
        isDeletedForMe,
        isDeletedForBoth,
        sentAt,
        deliveredAt,
        readAt,
        mediaMetadataId,
      ];
}
