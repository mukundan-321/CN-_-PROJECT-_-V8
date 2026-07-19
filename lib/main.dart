import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:two_person_app/core/di/injector.dart';
import 'package:two_person_app/core/theme/app_theme.dart';
import 'package:two_person_app/features/pairing/presentation/screens/pairing_flow_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? startupError;

  try {
    await configureDependencies(
      dbPassphrase: 'REPLACE_WITH_DERIVED_KEY',
    );
  } catch (e) {
    startupError = e.toString();
  }

  runApp(
    ProviderScope(
      child: TwoPersonApp(startupError: startupError),
    ),
  );
}

class TwoPersonApp extends StatelessWidget {
  final String? startupError;

  const TwoPersonApp({
    super.key,
    this.startupError,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Us',
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

  const _StartupErrorScreen({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong starting up.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate({super.key});

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  @override
  Widget build(BuildContext context) {
    return const PairingFlowScreen(
      isReconnect: false,
    );
  }
}