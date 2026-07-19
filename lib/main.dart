import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:two_person_app/core/di/injector.dart';
import 'package:two_person_app/core/theme/app_theme.dart';
import 'package:two_person_app/features/pairing/domain/repositories/pairing_repository.dart';
import 'package:two_person_app/features/pairing/presentation/screens/pairing_flow_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO(crypto-module-v2): replace with a passphrase derived from a
  // biometric/PIN-gated secure-enclave master key. Using a fixed
  // placeholder here so the rest of the app is runnable in isolation —
  // this must not ship as-is, since it means the DB encryption key is
  // effectively public.
  String? startupError;
  try {
    await configureDependencies(dbPassphrase: 'REPLACE_WITH_DERIVED_KEY');
  } catch (e) {
    // Without this, a DI/secure-storage/database init failure at
    // startup would surface as an unhandled framework error (a red
    // screen in debug, a silent crash in release) instead of
    // something the person could at least see a message for.
    startupError = e.toString();
  }

  runApp(ProviderScope(child: TwoPersonApp(startupError: startupError)));
}

class TwoPersonApp extends StatelessWidget {
  final String? startupError;
  const TwoPersonApp({super.key, this.startupError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Us', // deliberately no product-y branding — this is a
      // private space for two people, not a product with a marketing name.
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: startupError != null
          ? _StartupErrorScreen(message: startupError!)
          : const _RootGate(),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final String message;
  const _StartupErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text('Something went wrong starting up.', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every app launch starts here — including on a device that's
/// already paired, because there's no server keeping a connection
/// alive between launches. "Already paired" (long-term trust) and
/// "connected right now" (this session's live WebRTC link) are
/// different things; [PairingFlowScreen] handles both, just with a
/// lighter-weight path when [isPaired] is already true.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  // Cached rather than called directly inside build(): a FutureBuilder
  // whose `future:` is created fresh on every build re-triggers the
  // loading state (and re-queries the database) on any unrelated
  // rebuild of this widget — hot reload, a theme change, anything
  // above it in the tree rebuilding.
  late final Future<bool> _isPairedFuture = sl<PairingRepository>().isPaired;

  @override
Widget build(BuildContext context) {
  return const PairingFlowScreen(isReconnect: false);
}
