import 'dart:math';

import 'package:meta/meta.dart';

@immutable
/// Built-in retry configuration used by [SyncPolicy].
class RetryConfig {
  /// Creates a disabled retry configuration.
  const RetryConfig.disabled()
    : enabled = false,
      maxRetries = 0,
      initialDelay = Duration.zero,
      maxDelay = Duration.zero,
      multiplier = 1;

  /// Creates an exponential backoff retry configuration.
  const RetryConfig.exponential({
    int? maxRetries,
    @Deprecated('Use maxRetries instead.') int? maxAttempts,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.multiplier = 2,
  }) : maxRetries = maxRetries ?? maxAttempts ?? 5,
       enabled = true;

  /// Whether retries are enabled.
  final bool enabled;

  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Initial retry delay.
  final Duration initialDelay;

  /// Maximum allowed retry delay.
  final Duration maxDelay;

  /// Backoff multiplier applied on each retry.
  final int multiplier;

  @Deprecated('Use maxRetries instead.')
  /// Deprecated alias for [maxRetries].
  int get maxAttempts => maxRetries;

  /// Returns the next retry delay for [attempt], or `null` when no retry should occur.
  Duration? nextDelay(int attempt) {
    if (!enabled || attempt > maxRetries || attempt <= 0) {
      return null;
    }

    final factor = pow(multiplier, attempt - 1).toInt();
    final delayMs = initialDelay.inMilliseconds * factor;
    final boundedMs = min(delayMs, maxDelay.inMilliseconds);
    return Duration(milliseconds: boundedMs);
  }
}
