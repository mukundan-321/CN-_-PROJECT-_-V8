/// Base type for all recoverable failures in the app.
///
/// These map to failure modes that are the normal state of this app,
/// not edge cases: with no server and no store-and-forward, the peer
/// simply being offline is something every operation has to handle.
sealed class Failure {
  final String message;
  const Failure(this.message);
}

class PeerOfflineFailure extends Failure {
  const PeerOfflineFailure() : super('Your person is not online right now.');
}

class SignalingPayloadInvalidFailure extends Failure {
  const SignalingPayloadInvalidFailure()
      : super('That invite/QR payload could not be read.');
}

class LocalStorageFailure extends Failure {
  const LocalStorageFailure(String reason) : super('Local storage error: $reason');
}

class UnknownFailure extends Failure {
  const UnknownFailure(String reason) : super('Unexpected error: $reason');
}
