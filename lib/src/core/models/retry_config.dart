import 'dart:math';

import 'package:meta/meta.dart';

@immutable
class RetryConfig {
  const RetryConfig.disabled()
      : enabled = false,
        maxRetries = 0,
        initialDelay = Duration.zero,
        maxDelay = Duration.zero,
        multiplier = 1;

  const RetryConfig.exponential({
    int? maxRetries,
    @Deprecated('Use maxRetries instead.') int? maxAttempts,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.multiplier = 2,
  })  : maxRetries = maxRetries ?? maxAttempts ?? 5,
        enabled = true;

  final bool enabled;
  final int maxRetries;
  final Duration initialDelay;
  final Duration maxDelay;
  final int multiplier;

  @Deprecated('Use maxRetries instead.')
  int get maxAttempts => maxRetries;

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
