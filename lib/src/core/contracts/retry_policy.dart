import 'dart:math';

/// Strategy interface for computing retry delays after failures.
abstract interface class RetryPolicy {
  /// Returns the next delay for a failed attempt, or `null` to stop retrying.
  Duration? nextDelay({required int attempt, required Object error});
}

/// A retry policy that never retries.
class NoRetryPolicy implements RetryPolicy {
  /// Creates a no-retry policy.
  const NoRetryPolicy();

  @override
  Duration? nextDelay({required int attempt, required Object error}) => null;
}

/// An exponential backoff retry policy.
class ExponentialBackoffRetryPolicy implements RetryPolicy {
  /// Creates an exponential backoff retry policy.
  const ExponentialBackoffRetryPolicy({
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    int? maxRetries,
    @Deprecated('Use maxRetries instead.') int? maxAttempts,
    this.multiplier = 2,
  }) : maxRetries = maxRetries ?? maxAttempts ?? 5;

  /// Delay used for the first retry attempt.
  final Duration initialDelay;

  /// Maximum retry delay cap.
  final Duration maxDelay;

  /// Maximum number of retry attempts allowed.
  final int maxRetries;

  /// Multiplier applied between retry attempts.
  final int multiplier;

  @Deprecated('Use maxRetries instead.')
  /// Deprecated alias for [maxRetries].
  int get maxAttempts => maxRetries;

  @override
  Duration? nextDelay({required int attempt, required Object error}) {
    if (attempt > maxRetries) {
      return null;
    }

    final factor = pow(multiplier, attempt - 1).toInt();
    final delayMs = initialDelay.inMilliseconds * factor;
    final boundedMs = min(delayMs, maxDelay.inMilliseconds);
    return Duration(milliseconds: boundedMs);
  }
}
