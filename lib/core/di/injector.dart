import 'package:get_it/get_it.dart';

import 'package:two_person_app/core/database/app_database.dart';

import 'package:two_person_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:two_person_app/features/chat/data/chat_repository_impl.dart';

import 'package:two_person_app/features/pairing/domain/repositories/pairing_repository.dart';
import 'package:two_person_app/features/pairing/data/pairing_repository_impl.dart';
import 'package:two_person_app/features/pairing/data/crypto/secure_key_store.dart';
import 'package:two_person_app/features/pairing/data/crypto/identity_key_service.dart';

final GetIt sl = GetIt.instance;

/// Called once from main() after the device passphrase has been
/// unlocked. Kept as plain manual registration rather than
/// `injectable` codegen: this is a small, fixed set of repositories,
/// and readability here matters more than saving a few lines.
Future<void> configureDependencies({required String dbPassphrase}) async {
  // Core
  sl.registerLazySingleton<AppDatabase>(() => AppDatabase.open(dbPassphrase));

  // Feature: pairing (identity, key exchange, live connection)
  sl.registerLazySingleton<SecureKeyValueStore>(
    () => DeviceSecureKeyValueStore(),
  );
  sl.registerLazySingleton<IdentityKeyService>(
    () => IdentityKeyService(sl()),
  );
  sl.registerLazySingleton<PairingRepository>(
    () => PairingRepositoryImpl(db: sl(), identityKeyService: sl()),
  );

  // Feature: chat — depends on pairing for live message delivery.
  sl.registerLazySingleton<ChatRepository>(
    () => ChatRepositoryImpl(db: sl(), pairingRepository: sl()),
  );
}

/// Call from test setUp() to point the locator at an in-memory DB and
/// fakes instead of real implementations.
Future<void> configureDependenciesForTesting() async {
  sl.reset();
  sl.registerLazySingleton<AppDatabase>(() => AppDatabase.forTesting());
}
