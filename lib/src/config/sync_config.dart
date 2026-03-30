import '../core/core.dart';

class SyncConfig {
  const SyncConfig({
    this.globalPreconditions = const <SyncPrecondition>[],
    this.retryPolicy = const NoRetryPolicy(),
    this.logger = const NoopSyncLogger(),
  });

  final List<SyncPrecondition> globalPreconditions;
  final RetryPolicy retryPolicy;
  final SyncLogger logger;
}
