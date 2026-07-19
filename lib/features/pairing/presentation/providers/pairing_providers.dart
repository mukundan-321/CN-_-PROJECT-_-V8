import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:two_person_app/core/di/injector.dart';
import 'package:two_person_app/features/pairing/domain/entities/device_identity.dart';
import 'package:two_person_app/features/pairing/domain/repositories/pairing_repository.dart';

final pairingRepositoryProvider = Provider<PairingRepository>(
  (ref) => sl<PairingRepository>(),
);

/// Whether this device has ever completed pairing — persists across
/// restarts (backed by the DB), unlike [connectionStatusProvider]
/// which reflects the current session's live connection only.
final isPairedProvider = FutureProvider<bool>(
  (ref) => ref.watch(pairingRepositoryProvider).isPaired,
);

/// True only while the encrypted WebRTC data channel for *this app
/// session* is actually open. Every app relaunch starts this at
/// false again — there's no server to stay connected through, so
/// being "paired" and being "connected right now" are genuinely
/// different things here.
final connectionStatusProvider = StreamProvider<bool>(
  (ref) => ref.watch(pairingRepositoryProvider).connectionStatus,
);

final peerIdentityProvider = FutureProvider<DeviceIdentity?>(
  (ref) => ref.watch(pairingRepositoryProvider).peerIdentity,
);
