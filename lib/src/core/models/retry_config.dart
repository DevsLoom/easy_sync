import 'dart:math';

import 'package:meta/meta.dart';

@immutable
class RetryConfig {
  const RetryConfig.disabled()
      : enabled = false,
        maxAttempts = 0,
        initialDelay = Duration.zero,
        maxDelay = Duration.zero,
        multiplier = 1;

  const RetryConfig.exponential({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.multiplier = 2,
  }) : enabled = true;

  final bool enabled;
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final int multiplier;

  Duration? nextDelay(int attempt) {
    if (!enabled || attempt > maxAttempts || attempt <= 0) {
      return null;
    }

    final factor = pow(multiplier, attempt - 1).toInt();
    final delayMs = initialDelay.inMilliseconds * factor;
    final boundedMs = min(delayMs, maxDelay.inMilliseconds);
    return Duration(milliseconds: boundedMs);
  }
}
