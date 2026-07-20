/// Typed failures that cross layer boundaries (data -> repository -> UI)
/// instead of raw exceptions escaping the data layer.
sealed class Failure {
  const Failure(this.message);

  final String message;
}

final class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

/// Result of an operation that can fail with a typed [Failure].
sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T value) ok,
    required R Function(Failure failure) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final failure) => err(failure),
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}
