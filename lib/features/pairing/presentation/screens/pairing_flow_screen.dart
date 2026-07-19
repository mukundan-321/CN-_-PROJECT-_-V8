import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:two_person_app/core/utils/result.dart';
import 'package:two_person_app/features/chat/presentation/screens/chat_screen.dart';
import 'package:two_person_app/features/pairing/domain/entities/device_identity.dart';
import 'package:two_person_app/features/pairing/presentation/providers/pairing_providers.dart';
import 'package:two_person_app/features/pairing/presentation/widgets/qr_scanner_screen.dart';

enum _Stage { choosing, createdInvite, joiningInput, postExchange, verifyFingerprint }

/// [isReconnect] distinguishes two real, different flows:
/// - First-time pairing: full flow, ending in mandatory fingerprint
///   verification — this is the actual security boundary.
/// - Reconnect: the two devices already trust each other's long-term
///   keys from a previous pairing; this just re-establishes *this
///   session's* WebRTC connection (unavoidable — there's no server to
///   stay connected through between app launches) and skips
///   re-verifying a fingerprint that hasn't changed.
class PairingFlowScreen extends ConsumerStatefulWidget {
  final bool isReconnect;
  const PairingFlowScreen({super.key, required this.isReconnect});

  @override
  ConsumerState<PairingFlowScreen> createState() => _PairingFlowScreenState();
}

class _PairingFlowScreenState extends ConsumerState<PairingFlowScreen> {
  _Stage _stage = _Stage.choosing;
  String? _outgoingPayload; // invite (as initiator) or response (as responder)
  String? _errorMessage;
  bool _busy = false;
  DeviceIdentity? _peerIdentity;
  StreamSubscription<bool>? _connectionSub;
  final _pasteController = TextEditingController();
  // Two independent paths can decide it's time to enter chat (the
  // live connectionStatus listener, and the direct check right after
  // fingerprint confirmation) — this guards against both firing close
  // together and calling pushReplacement twice before the first
  // navigation's disposal takes effect.
  bool _hasNavigatedToChat = false;

  @override
  void dispose() {
    _connectionSub?.cancel();
    _pasteController.dispose();
    super.dispose();
  }

  void _listenForLiveConnection() {
    _connectionSub?.cancel();
    _connectionSub = ref.read(pairingRepositoryProvider).connectionStatus.listen((connected) {
      if (!connected || !mounted) return;
      if (widget.isReconnect) {
        _goToChat();
      } else if (_peerIdentity != null && _peerIdentity!.fingerprintVerified) {
        _goToChat();
      }
      // Otherwise: connected but not yet fingerprint-verified — wait
      // for the user to confirm on the verify screen before entering chat.
    });
  }

  void _goToChat() {
    if (!mounted || _hasNavigatedToChat) return;
    _hasNavigatedToChat = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  Future<void> _startCreateFlow() async {
    setState(() { _busy = true; _errorMessage = null; });
    final result = await ref.read(pairingRepositoryProvider).createInviteLink();
    if (!mounted) return;
    setState(() {
      _busy = false;
      result.when(
        ok: (payload) {
          _outgoingPayload = payload;
          _stage = _Stage.createdInvite;
        },
        err: (f) => _errorMessage = f.message,
      );
    });
  }

  Future<void> _submitResponsePayload(String responsePayload) async {
    setState(() { _busy = true; _errorMessage = null; });
    final result = await ref.read(pairingRepositoryProvider).completePairing(responsePayload);
    if (!mounted) return;
    result.when(
      ok: (identity) {
        setState(() {
          _busy = false;
          _peerIdentity = identity;
          _outgoingPayload = null;
        });
        _listenForLiveConnection();
        if (widget.isReconnect) {
          // Connection status listener above will navigate once live.
          setState(() => _stage = _Stage.postExchange);
        } else {
          setState(() => _stage = _Stage.verifyFingerprint);
        }
      },
      err: (f) => setState(() { _busy = false; _errorMessage = f.message; }),
    );
  }

  Future<void> _submitInvitePayload(String invitePayload) async {
    setState(() { _busy = true; _errorMessage = null; });
    final result = await ref.read(pairingRepositoryProvider).acceptInvite(invitePayload);
    if (!mounted) return;

    // Deliberately not doing the async peerIdentity lookup inside
    // result.when()'s `ok` callback: mixing an async callback there
    // with the synchronous `err` callback means the two branches
    // return different types (Future<void> vs void) to the same
    // generic when<R>() call, which is fragile at best and a type
    // inference error at worst. Extract synchronously, then branch.
    final responsePayload = result.when(ok: (p) => p, err: (_) => null);
    if (responsePayload == null) {
      final failureMessage = result.when(ok: (_) => '', err: (f) => f.message);
      setState(() { _busy = false; _errorMessage = failureMessage; });
      return;
    }

    final peer = await ref.read(pairingRepositoryProvider).peerIdentity;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outgoingPayload = responsePayload;
      _peerIdentity = peer;
      _stage = widget.isReconnect ? _Stage.postExchange : _Stage.verifyFingerprint;
    });
    _listenForLiveConnection();
  }

  Future<void> _scanAndSubmit({required bool asResponse}) async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (scanned == null) return;
    if (asResponse) {
      await _submitResponsePayload(scanned);
    } else {
      await _submitInvitePayload(scanned);
    }
  }

  Future<void> _confirmFingerprint() async {
    setState(() => _busy = true);
    await ref.read(pairingRepositoryProvider).confirmFingerprintVerified();
    final peer = await ref.read(pairingRepositoryProvider).peerIdentity;
    if (!mounted) return;
    setState(() { _busy = false; _peerIdentity = peer; });
    if (peer?.fingerprintVerified == true) {
      // If the data channel already connected while the user was
      // reading the fingerprint, go straight in; otherwise the
      // connection listener will take over once it does.
      final connected = await ref.read(connectionStatusProvider.future);
      if (connected) _goToChat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isReconnect ? 'Reconnect' : 'Pairing'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildStageContent(),
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case _Stage.choosing:
        return _ChoosingView(
          isReconnect: widget.isReconnect,
          busy: _busy,
          error: _errorMessage,
          onCreate: _startCreateFlow,
          onJoin: () => setState(() => _stage = _Stage.joiningInput),
        );
      case _Stage.joiningInput:
        return _PasteOrScanView(
          title: widget.isReconnect ? 'Paste or scan their session code' : 'Paste or scan the invite',
          controller: _pasteController,
          busy: _busy,
          error: _errorMessage,
          onScan: () => _scanAndSubmit(asResponse: false),
          onSubmitPasted: () => _submitInvitePayload(_pasteController.text.trim()),
        );
      case _Stage.createdInvite:
        return _ShareAndAwaitView(
          instructions: 'Send this to your person. Once they respond, paste or scan their reply below.',
          payload: _outgoingPayload!,
          controller: _pasteController,
          busy: _busy,
          error: _errorMessage,
          onScanReply: () => _scanAndSubmit(asResponse: true),
          onSubmitReply: () => _submitResponsePayload(_pasteController.text.trim()),
        );
      case _Stage.postExchange:
        return const _WaitingToConnectView();
      case _Stage.verifyFingerprint:
        return _FingerprintVerifyView(
          fingerprint: _peerIdentity?.fingerprint ?? '',
          alreadyVerified: _peerIdentity?.fingerprintVerified ?? false,
          busy: _busy,
          onConfirm: _confirmFingerprint,
        );
    }
  }
}

class _ChoosingView extends StatelessWidget {
  final bool isReconnect;
  final bool busy;
  final String? error;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  const _ChoosingView({
    required this.isReconnect,
    required this.busy,
    required this.error,
    required this.onCreate,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isReconnect
              ? 'You\'re already paired. Reconnect to start this session.'
              : 'This app connects exactly two people, directly — no accounts, no servers.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 32),
        if (error != null) ...[
          Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: busy ? null : onCreate,
          child: Text(isReconnect ? 'Start session' : 'Start pairing'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy ? null : onJoin,
          child: Text(isReconnect ? 'Join their session' : 'Join with an invite'),
        ),
        if (busy) const Padding(
          padding: EdgeInsets.only(top: 24),
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }
}

class _PasteOrScanView extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final bool busy;
  final String? error;
  final VoidCallback onScan;
  final VoidCallback onSubmitPasted;

  const _PasteOrScanView({
    required this.title,
    required this.controller,
    required this.busy,
    required this.error,
    required this.onScan,
    required this.onSubmitPasted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : onScan,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan QR code'),
        ),
        const SizedBox(height: 16),
        const Text('— or paste the text —'),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy ? null : onSubmitPasted,
          child: const Text('Submit'),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
                  if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaitingToConnectView extends StatelessWidget {
  final String instructions;
  final String payload;
  final TextEditingController controller;
  final bool busy;
  final String? error;
  final VoidCallback onScanReply;
  final VoidCallback onSubmitReply;

  const _ShareAndAwaitView({
    required this.instructions,
    required this.payload,
    required this.controller,
    required this.busy,
    required this.error,
    required this.onScanReply,
    required this.onSubmitReply,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'DEBUG PAYLOAD',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    payload,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  QrImageView(
                    data: payload,
                    size: 220,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: payload));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Copied — share it via any app you like.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy invite text'),
          ),
          const SizedBox(height: 24),
          Text(
            instructions,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : onScanReply,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan their reply'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Or paste their reply text here',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : onSubmitReply,
            child: const Text('Submit reply'),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
          
  class _WaitingToConnectView extends StatelessWidget {
  const _WaitingToConnectView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Connecting…'),
        ],
      ),
    );
  }
}
    

class _FingerprintVerifyView extends StatelessWidget {
  final String fingerprint;
  final bool alreadyVerified;
  final bool busy;
  final VoidCallback onConfirm;

  const _FingerprintVerifyView({
    required this.fingerprint,
    required this.alreadyVerified,
    required this.busy,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Read this number out loud together, or compare it side by side. '
          'This is what actually confirms you\'re connected to the right person '
          'and not someone in between.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            fingerprint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 16, letterSpacing: 1.2),
          ),
        ),
        const SizedBox(height: 24),
        if (alreadyVerified)
          const Text('Verified ✓', textAlign: TextAlign.center)
        else
          FilledButton(
            onPressed: busy ? null : onConfirm,
            child: const Text('It matches — confirm'),
          ),
        if (busy) const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
