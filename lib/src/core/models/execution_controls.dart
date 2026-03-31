import 'package:meta/meta.dart';

@immutable
class SyncRateLimit {
  const SyncRateLimit.disabled()
    : enabled = false,
      maxExecutions = 0,
      per = Duration.zero;

  const SyncRateLimit.slidingWindow({
    required this.maxExecutions,
    required this.per,
  }) : enabled = true;

  final bool enabled;
  final int maxExecutions;
  final Duration per;
}

@immutable
class SyncCircuitBreaker {
  const SyncCircuitBreaker.disabled()
    : enabled = false,
      failureThreshold = 0,
      openFor = Duration.zero;

  const SyncCircuitBreaker.standard({
    required this.failureThreshold,
    required this.openFor,
  }) : enabled = true;

  final bool enabled;
  final int failureThreshold;
  final Duration openFor;
}
