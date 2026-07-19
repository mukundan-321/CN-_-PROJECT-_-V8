import 'package:flutter_test/flutter_test.dart';
import 'package:two_person_app/core/database/app_database.dart';
import 'package:two_person_app/features/chat/data/chat_repository_impl.dart';
import 'package:two_person_app/features/pairing/domain/entities/device_identity.dart';
import 'package:two_person_app/features/pairing/domain/entities/encrypted_channel.dart';
import 'package:two_person_app/features/pairing/domain/repositories/pairing_repository.dart';
import 'package:two_person_app/core/utils/result.dart';

/// Never-paired fake — exercises the same "no live transport" path a
/// real unpaired or offline device would hit. sendMessage should still
/// succeed locally; deleteForBoth should fail, since that genuinely
/// requires the peer to be reachable.
class _UnpairedFakePairingRepository implements PairingRepository {
  @override
  Future<bool> get isPaired async => false;
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
  Stream<bool> get connectionStatus => const Stream.empty();
  @override
  EncryptedChannel? get transport => null;
}

void main() {
  late AppDatabase db;
  late ChatRepositoryImpl repo;

  setUp(() {
    db = AppDatabase.forTesting();
    repo = ChatRepositoryImpl(db: db, pairingRepository: _UnpairedFakePairingRepository());
  });

  tearDown(() async => db.close());

  test('sendMessage persists and watchMessages emits it', () async {
    final result = await repo.sendMessage(content: 'hey');
    expect(result.isOk, isTrue);

    final messages = await repo.watchMessages().first;
    expect(messages, hasLength(1));
    expect(messages.first.content, 'hey');
  });

  test('editMessage updates content and sets isEdited', () async {
    final sent = await repo.sendMessage(content: 'original');
    final id = sent.when(ok: (m) => m.id, err: (_) => throw StateError('x'));

    await repo.editMessage(id, 'edited');
    final messages = await repo.watchMessages().first;
    expect(messages.first.content, 'edited');
    expect(messages.first.isEdited, isTrue);
  });

  test('deleteForMe excludes message from watchMessages', () async {
    final sent = await repo.sendMessage(content: 'to delete');
    final id = sent.when(ok: (m) => m.id, err: (_) => throw StateError('x'));

    await repo.deleteForMe(id);
    final messages = await repo.watchMessages().first;
    expect(messages, isEmpty);
  });

  test('deleteForBoth fails without a live peer connection', () async {
    final sent = await repo.sendMessage(content: 'x');
    final id = sent.when(ok: (m) => m.id, err: (_) => throw StateError('x'));

    final result = await repo.deleteForBoth(id);
    expect(result.isErr, isTrue);
  });
}
