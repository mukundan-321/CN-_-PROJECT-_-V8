import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:two_person_app/core/utils/result.dart';
import 'package:two_person_app/features/chat/domain/entities/message.dart';
import 'package:two_person_app/features/chat/presentation/providers/chat_providers.dart';
import 'package:two_person_app/features/pairing/presentation/providers/pairing_providers.dart';

const _localSenderId = 'local';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  ChatMessage? _replyingTo;
  int _lastKnownMessageCount = 0;

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;
    _composerController.clear();
    final replyId = _replyingTo?.id;
    setState(() => _replyingTo = null);
    await ref.read(chatRepositoryProvider).sendMessage(
          content: text,
          replyToMessageId: replyId,
        );
    if (!mounted) return;
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMessageActions(ChatMessage message) {
    final isMine = message.senderDeviceId == _localSenderId;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyingTo = message);
              },
            ),
            ListTile(
              leading: Icon(message.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(message.isPinned ? 'Unpin' : 'Pin'),
              onTap: () async {
                Navigator.pop(context);
                final result = await ref
                    .read(chatRepositoryProvider)
                    .pinMessage(message.id, !message.isPinned);
                _showErrorIfFailed(result);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: const Text('React ❤️'),
              onTap: () async {
                Navigator.pop(context);
                final result = await ref
                    .read(chatRepositoryProvider)
                    .addReaction(message.id, '❤️');
                _showErrorIfFailed(result);
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete for me'),
              onTap: () async {
                Navigator.pop(context);
                final result =
                    await ref.read(chatRepositoryProvider).deleteForMe(message.id);
                _showErrorIfFailed(result);
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Delete for both'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await ref.read(chatRepositoryProvider).deleteForBoth(message.id);
                  if (result.isErr && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not delete for both — your person is offline.')),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showErrorIfFailed(Result<void> result) {
    if (result.isErr && mounted) {
      final message = result.when(ok: (_) => '', err: (f) => f.message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showEditDialog(ChatMessage message) {
    final controller = TextEditingController(text: message.content ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: controller, maxLines: 4, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final newContent = controller.text.trim();
              Navigator.pop(context);
              // Dialog closes immediately (no reason to block the UI on
              // this), but the Future is still awaited and its result
              // checked — not fired-and-forgotten — so a failure still
              // reaches the user via a snackbar instead of silently
              // vanishing.
              ref.read(chatRepositoryProvider).editMessage(message.id, newContent).then(
                    _showErrorIfFailed,
                  );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider);
    final connected = ref.watch(connectionStatusProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Us'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    connected ? Icons.circle : Icons.circle_outlined,
                    size: 10,
                    color: connected ? Colors.greenAccent : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(connected ? 'Connected' : 'Offline', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text('Say something.'));
                }
                // Only jump to bottom when a message was actually
                // added — not on every rebuild this builder runs for
                // (e.g. the connection-status indicator changing),
                // which previously yanked the scroll position back
                // down even if the user had scrolled up to read
                // earlier messages.
                if (messages.length > _lastKnownMessageCount) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                }
                _lastKnownMessageCount = messages.length;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _MessageBubble(
                      message: message,
                      isMine: message.senderDeviceId == _localSenderId,
                      onLongPress: () => _showMessageActions(message),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Something went wrong: $e')),
            ),
          ),
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying to: ${_replyingTo!.content ?? '[media]'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composerController,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMine
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.isPinned)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.push_pin, size: 12, color: textColor.withOpacity(0.7)),
                ),
              Text(
                message.isDeletedForMe ? '[deleted]' : (message.content ?? '[media]'),
                style: TextStyle(
                  color: textColor,
                  fontStyle: message.isDeletedForMe ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              if (message.isEdited)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('edited', style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.6))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
