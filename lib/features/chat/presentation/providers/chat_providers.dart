import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:two_person_app/core/di/injector.dart';
import 'package:two_person_app/features/chat/domain/entities/message.dart';
import 'package:two_person_app/features/chat/domain/repositories/chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => sl<ChatRepository>(),
);

final messagesProvider = StreamProvider<List<ChatMessage>>(
  (ref) => ref.watch(chatRepositoryProvider).watchMessages(),
);
