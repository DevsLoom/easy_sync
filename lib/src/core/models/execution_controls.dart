import 'package:meta/meta.dart';

@immutable
/// Sliding-window rate limit configuration for sync task execution.
class SyncRateLimit {
  /// Creates a disabled rate limit.
  const SyncRateLimit.disabled()
    : enabled = false,
      maxExecutions = 0,
      per = Duration.zero;

  /// Creates a sliding-window rate limit.
  const SyncRateLimit.slidingWindow({
    required this.maxExecutions,
    required this.per,
  }) : enabled = true;

  /// Whether rate limiting is enabled.
  final bool enabled;

  /// Maximum number of executions allowed in the configured window.
  final int maxExecutions;

  /// Window size used for counting recent executions.
  final Duration per;
}

@immutable
/// Circuit breaker configuration for temporarily halting failing tasks.
class SyncCircuitBreaker {
  /// Creates a disabled circuit breaker.
  const SyncCircuitBreaker.disabled()
    : enabled = false,
      failureThreshold = 0,
      openFor = Duration.zero;

  /// Creates a standard circuit breaker.
  const SyncCircuitBreaker.standard({
    required this.failureThreshold,
    required this.openFor,
  }) : enabled = true;

  /// Whether the circuit breaker is enabled.
  final bool enabled;

  /// Number of consecutive failures required to open the circuit.
  final int failureThreshold;

  /// Duration to keep the circuit open before allowing execution again.
  final Duration openFor;
}
