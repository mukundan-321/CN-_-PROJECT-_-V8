import 'package:two_person_app/core/error/failures.dart';

/// Every repository method returns a [Result] instead of throwing.
///
/// This is deliberate for this app: failures here (peer offline, ICE
/// negotiation failed, decryption failed) are expected, routine outcomes
/// — not exceptional ones — and the UI needs to branch on them without
/// try/catch scattered through every screen.
sealed class Result<T> {
  const Result();

  factory Result.ok(T value) = Ok<T>;
  factory Result.err(Failure failure) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  R when<R>({
    required R Function(T value) ok,
    required R Function(Failure failure) err,
  }) {
    final self = this;
    if (self is Ok<T>) return ok(self.value);
    if (self is Err<T>) return err(self.failure);
    throw StateError('Unreachable');
  }
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final Failure failure;
  const Err(this.failure);
}
