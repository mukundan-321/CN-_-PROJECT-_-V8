import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:two_person_app/core/database/app_database.dart';
import 'package:two_person_app/features/chat/data/chat_repository_impl.dart';
import 'package:two_person_app/features/pairing/domain/entities/device_identity.dart';
import 'package:two_person_app/features/pairing/domain/entities/encrypted_channel.dart';
import 'package:two_person_app/features/pairing/domain/repositories/pairing_repository.dart';
import 'package:two_person_app/core/utils/result.dart';

/// A fake [EncryptedChannel] that hands bytes directly to a paired
/// counterpart's incoming stream — standing in for the real
/// WebRTC-data-channel-plus-ChaCha20 pipeline so this test can verify
/// the *application* wire protocol (message/edit/delete framing)
/// without spinning up actual peer connections.
class _LinkedFakeChannel implements EncryptedChannel {
  final _incomingController = StreamController<List<int>>.broadcast();
  _LinkedFakeChannel? peer;

  @override
  Stream<List<int>> get decryptedIncoming => _incomingController.stream;

  @override
  Future<void> send(List<int> plaintext) async {
    peer?._incomingController.add(plaintext);
  }

  void dispose() => _incomingController.close();
}

class _ConnectedFakePairingRepository implements PairingRepository {
  @override
  final EncryptedChannel transport;
  _ConnectedFakePairingRepository(this.transport);

  @override
  Future<bool> get isPaired async => true;
  @override
  Future<DeviceIdentity> get localIdentity => throw UnimplementedError();
  @override
  Future<DeviceIdentity?> get peerIdentity async => null;
  @override
  Future<Result<String>> createInviteLink() => throw UnimplementedError();
  @override
  Future<Result<String>> acceptInvite(String invitePayload) => throw UnimplementedError();
  @override
  Future<Result<DeviceIdentity>> completePairing(String responsePayload) =>
      throw UnimplementedError();
  @override
  Future<Result<void>> confirmFingerprintVerified() => throw UnimplementedError();
  @override
  Stream<bool> get connectionStatus => Stream.value(true);
}

void main() {
  late AppDatabase dbA;
  late AppDatabase dbB;
  late ChatRepositoryImpl repoA;
  late ChatRepositoryImpl repoB;

  setUp(() async {
    dbA = AppDatabase.forTesting();
    dbB = AppDatabase.forTesting();

    final channelA = _LinkedFakeChannel();
    final channelB = _LinkedFakeChannel();
    channelA.peer = channelB;
    channelB.peer = channelA;

    repoA = ChatRepositoryImpl(
      db: dbA,
      pairingRepository: _ConnectedFakePairingRepository(channelA),
    );
    repoB = ChatRepositoryImpl(
      db: dbB,
      pairingRepository: _ConnectedFakePairingRepository(channelB),
    );

    // Let the connectionStatus stream's single emission propagate and
    // bind the incoming-frame subscriptions before sending anything.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    repoA.dispose();
    repoB.dispose();
    await dbA.close();
    await dbB.close();
  });

  test('a message sent from A arrives in B\'s message list', () async {
    final sent = await repoA.sendMessage(content: 'hey from A');
    expect(sent.isOk, isTrue);

    // Delivery is async (goes through the fake channel's stream).
    await Future<void>.delayed(Duration.zero);

    final bMessages = await repoB.watchMessages().first;
    expect(bMessages, hasLength(1));
    expect(bMessages.first.content, 'hey from A');
  });

  test('deleteForBoth on A propagates the delete to B', () async {
    final sent = await repoA.sendMessage(content: 'to be deleted');
    final id = sent.when(ok: (m) => m.id, err: (_) => throw StateError('x'));
    await Future<void>.delayed(Duration.zero);

    final result = await repoA.deleteForBoth(id);
    expect(result.isOk, isTrue);
    await Future<void>.delayed(Duration.zero);

    final aMessages = await repoA.watchMessages().first;
    final bMessages = await repoB.watchMessages().first;
    expect(aMessages, isEmpty);
    expect(bMessages, isEmpty); // B's copy was deleted too, not just A's
  });

  test('an edit on A propagates to B\'s copy', () async {
    final sent = await repoA.sendMessage(content: 'original');
    final id = sent.when(ok: (m) => m.id, err: (_) => throw StateError('x'));
    await Future<void>.delayed(Duration.zero);

    await repoA.editMessage(id, 'edited version');
    await Future<void>.delayed(Duration.zero);

    final bMessages = await repoB.watchMessages().first;
    expect(bMessages.first.content, 'edited version');
    expect(bMessages.first.isEdited, isTrue);
  });
}
