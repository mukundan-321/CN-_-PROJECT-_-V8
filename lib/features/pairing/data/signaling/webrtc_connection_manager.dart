import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'ice_config.dart';

class SignalingOffer {
  final String sdp;
  final List<Map<String, dynamic>> candidates;

  const SignalingOffer({
    required this.sdp,
    required this.candidates,
  });

  Map<String, dynamic> toJson() => {
        'sdp': sdp,
        'candidates': candidates,
      };

  static SignalingOffer fromJson(Map<String, dynamic> json) {
    return SignalingOffer(
      sdp: json['sdp'] as String,
      candidates:
          (json['candidates'] as List).cast<Map<String, dynamic>>(),
    );
  }
}

class SignalingAnswer {
  final String sdp;
  final List<Map<String, dynamic>> candidates;

  const SignalingAnswer({
    required this.sdp,
    required this.candidates,
  });

  Map<String, dynamic> toJson() => {
        'sdp': sdp,
        'candidates': candidates,
      };

  static SignalingAnswer fromJson(Map<String, dynamic> json) {
    return SignalingAnswer(
      sdp: json['sdp'] as String,
      candidates:
          (json['candidates'] as List).cast<Map<String, dynamic>>(),
    );
  }
}

class WebRtcConnectionManager {
  static const _dataChannelLabel = 'app-data';
  static const _iceGatheringTimeout = Duration(seconds: 8);

  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;

  final List<RTCIceCandidate> _gatheredCandidates = [];

  final _connectionStateController =
      StreamController<RTCPeerConnectionState>.broadcast();

  final _incomingMessagesController =
      StreamController<Uint8List>.broadcast();

  Stream<RTCPeerConnectionState> get connectionState =>
      _connectionStateController.stream;

  Stream<Uint8List> get incomingMessages =>
      _incomingMessagesController.stream;

  bool get isDataChannelOpen =>
      _dataChannel?.state ==
      RTCDataChannelState.RTCDataChannelOpen;
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

    // Temporary diagnostic: don't include ICE candidates in the invite.
    return SignalingOffer(
      sdp: offer.sdp!,
      candidates: const [],
    );
  }

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

    // Temporary diagnostic: don't include ICE candidates in the reply.
    return SignalingAnswer(
      sdp: answer.sdp!,
      candidates: const [],
    );
  }

  Future<void> applyAnswer(SignalingAnswer answer) async {
    final pc = _pc;

    if (pc == null) {
      throw StateError('applyAnswer called before createOffer.');
    }

    await pc.setRemoteDescription(
      RTCSessionDescription(answer.sdp, 'answer'),
    );

    for (final c in answer.candidates) {
      await pc.addCandidate(_candidateFromJson(c));
    }
  }
  Future<void> sendRaw(Uint8List bytes) async {
    final channel = _dataChannel;

    if (channel == null || !isDataChannelOpen) {
      throw StateError('Data channel is not open.');
    }

    await channel.send(
      RTCDataChannelMessage.fromBinary(bytes),
    );
  }

  Future<void> close() async {
    await _dataChannel?.close();
    await _pc?.close();

    await _connectionStateController.close();
    await _incomingMessagesController.close();
  }

  Future<void> _resetForNewAttempt() async {
    _gatheredCandidates.clear();

    await _dataChannel?.close();
    await _pc?.close();

    _dataChannel = null;
    _pc = null;
  }

  void _bindConnectionState(RTCPeerConnection pc) {
    pc.onConnectionState = (state) {
      _connectionStateController.add(state);
    };
  }

  void _bindDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    channel.onMessage = (message) {
      if (message.isBinary) {
        _incomingMessagesController.add(message.binary);
      }
    };
  }

  Future<void> _listenForIceCandidates(
    RTCPeerConnection pc,
  ) {
    final completer = Completer<void>();

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null &&
          candidate.candidate!.isNotEmpty) {
        _gatheredCandidates.add(candidate);
      }
    };

    pc.onIceGatheringState = (state) {
      if (state ==
              RTCIceGatheringState
                  .RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };

    Future.delayed(_iceGatheringTimeout, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    return completer.future;
  }

  Map<String, dynamic> _candidateToJson(
    RTCIceCandidate c,
  ) {
    return {
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    };
  }

  RTCIceCandidate _candidateFromJson(
    Map<String, dynamic> json,
  ) {
    return RTCIceCandidate(
      json['candidate'] as String?,
      json['sdpMid'] as String?,
      json['sdpMLineIndex'] as int?,
    );
  }
}