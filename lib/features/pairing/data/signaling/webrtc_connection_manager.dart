import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'ice_config.dart';

/// What goes into [PairingPayload.signalingData] for the offer side.
class SignalingOffer {
  final String sdp;
  final List<Map<String, dynamic>> candidates;

  const SignalingOffer({required this.sdp, required this.candidates});

  Map<String, dynamic> toJson() => {'sdp': sdp, 'candidates': candidates};

  static SignalingOffer fromJson(Map<String, dynamic> json) => SignalingOffer(
        sdp: json['sdp'] as String,
        candidates: (json['candidates'] as List).cast<Map<String, dynamic>>(),
      );
}

class SignalingAnswer {
  final String sdp;
  final List<Map<String, dynamic>> candidates;

  const SignalingAnswer({required this.sdp, required this.candidates});

  Map<String, dynamic> toJson() => {'sdp': sdp, 'candidates': candidates};

  static SignalingAnswer fromJson(Map<String, dynamic> json) => SignalingAnswer(
        sdp: json['sdp'] as String,
        candidates: (json['candidates'] as List).cast<Map<String, dynamic>>(),
      );
}

/// Wraps a single [RTCPeerConnection] and its one data channel — the
/// direct encrypted link chat messages travel over. No media/call
/// handling here; this is scoped to exactly what pairing + chat need.
///
/// Because pairing happens over manual/QR/invite-link transport rather
/// than a live signaling server, this uses non-trickle ICE: candidates
/// are gathered up front (bounded by [_iceGatheringTimeout]) and
/// shipped as a batch inside the same payload as the SDP, instead of
/// trickling in over a channel that doesn't exist yet.
class WebRtcConnectionManager {
  static const _dataChannelLabel = 'app-data';
  static const _iceGatheringTimeout = Duration(seconds: 8);

  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  final List<RTCIceCandidate> _gatheredCandidates = [];

  final _connectionStateController =
      StreamController<RTCPeerConnectionState>.broadcast();
  final _incomingMessagesController = StreamController<Uint8List>.broadcast();

  Stream<RTCPeerConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<Uint8List> get incomingMessages => _incomingMessagesController.stream;

  bool get isDataChannelOpen =>
      _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;

  /// Offer side (pairing initiator). Creates the peer connection, opens
  /// the data channel locally (the answerer receives it via
  /// `onDataChannel`), and waits for ICE gathering to finish so
  /// candidates can be embedded in the invite payload as a single batch.
  Future<SignalingOffer> createOffer({required bool turnEnabled}) async {
    await _resetForNewAttempt();
    final pc = await createPeerConnection(
      IceConfig.configuration(turnEnabled: turnEnabled),
    );
    _pc = pc;
    _bindConnectionState(pc);

    final channel = await pc.createDataChannel(
      _dataChannelLabel,
      RTCDataChannelInit()..ordered = true,
    );
    _bindDataChannel(channel);

    final gatheringDone = _listenForIceCandidates(pc);

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await gatheringDone;

    return SignalingOffer(
      sdp: offer.sdp!,
      candidates: _gatheredCandidates.map(_candidateToJson).toList(),
    );
  }

  /// Answer side (pairing responder). Applies the remote offer +
  /// candidates, generates a local answer, and waits for its own ICE
  /// gathering before returning — same non-trickle rationale as above.
  Future<SignalingAnswer> createAnswerForOffer(
    SignalingOffer remoteOffer, {
    required bool turnEnabled,
  }) async {
    await _resetForNewAttempt();
    final pc = await createPeerConnection(
      IceConfig.configuration(turnEnabled: turnEnabled),
    );
    _pc = pc;
    _bindConnectionState(pc);

    pc.onDataChannel = (channel) => _bindDataChannel(channel);

    await pc.setRemoteDescription(
      RTCSessionDescription(remoteOffer.sdp, 'offer'),
    );
    for (final c in remoteOffer.candidates) {
      await pc.addCandidate(_candidateFromJson(c));
    }

    final gatheringDone = _listenForIceCandidates(pc);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await gatheringDone;

    return SignalingAnswer(
      sdp: answer.sdp!,
      candidates: _gatheredCandidates.map(_candidateToJson).toList(),
    );
  }

  /// Offer side, after receiving the response payload back.
  Future<void> applyAnswer(SignalingAnswer answer) async {
    final pc = _pc;
    if (pc == null) {
      throw StateError('applyAnswer called before createOffer.');
    }
    await pc.setRemoteDescription(RTCSessionDescription(answer.sdp, 'answer'));
    for (final c in answer.candidates) {
      await pc.addCandidate(_candidateFromJson(c));
    }
  }

  Future<void> sendRaw(Uint8List bytes) async {
    final channel = _dataChannel;
    if (channel == null || !isDataChannelOpen) {
      throw StateError('Data channel is not open.');
    }
    await channel.send(RTCDataChannelMessage.fromBinary(bytes));
  }

  Future<void> close() async {
    await _dataChannel?.close();
    await _pc?.close();
    await _connectionStateController.close();
    await _incomingMessagesController.close();
  }

  /// Called at the start of every new offer/answer attempt. Without
  /// this, a retry (e.g. after a failed first pairing attempt) would
  /// append new ICE candidates onto the leftover list from the
  /// previous attempt — shipping stale candidates belonging to an
  /// already-abandoned peer connection — and would leak the old
  /// RTCPeerConnection's native resources instead of releasing them.
  Future<void> _resetForNewAttempt() async {
    _gatheredCandidates.clear();
    await _dataChannel?.close();
    await _pc?.close();
    _dataChannel = null;
    _pc = null;
  }

  void _bindConnectionState(RTCPeerConnection pc) {
    pc.onConnectionState = (state) => _connectionStateController.add(state);
  }

  void _bindDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    channel.onMessage = (message) {
      if (message.isBinary) {
        _incomingMessagesController.add(message.binary);
      }
    };
  }

  /// Resolves once ICE gathering completes, or after the timeout —
  /// whichever comes first. A timeout still yields a usable (if
  /// possibly incomplete) candidate set rather than hanging pairing
  /// indefinitely on a restrictive network.
  Future<void> _listenForIceCandidates(RTCPeerConnection pc) {
    final completer = Completer<void>();
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        _gatheredCandidates.add(candidate);
      }
    };
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };
    Future.delayed(_iceGatheringTimeout, () {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Map<String, dynamic> _candidateToJson(RTCIceCandidate c) => {
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      };

  RTCIceCandidate _candidateFromJson(Map<String, dynamic> json) =>
      RTCIceCandidate(
        json['candidate'] as String?,
        json['sdpMid'] as String?,
        json['sdpMLineIndex'] as int?,
      );
}
