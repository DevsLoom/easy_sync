import 'dart:math';

abstract interface class RetryPolicy {
  Duration? nextDelay({required int attempt, required Object error});
}

class NoRetryPolicy implements RetryPolicy {
  const NoRetryPolicy();

  @override
  Duration? nextDelay({required int attempt, required Object error}) => null;
}

class ExponentialBackoffRetryPolicy implements RetryPolicy {
  const ExponentialBackoffRetryPolicy({
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    int? maxRetries,
    @Deprecated('Use maxRetries instead.') int? maxAttempts,
    this.multiplier = 2,
  }) : maxRetries = maxRetries ?? maxAttempts ?? 5;

  final Duration initialDelay;
  final Duration maxDelay;
  final int maxRetries;
  final int multiplier;

  @Deprecated('Use maxRetries instead.')
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
