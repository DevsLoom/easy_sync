import '../core.dart';

@Deprecated('Use SyncEngine directly.')
/// Backward-compatible wrapper around [SyncEngine].
class SyncOrchestrator extends SyncEngine {
  /// Creates a sync orchestrator.
  SyncOrchestrator({
    required super.taskRegistrations,
    required super.stateStore,
    super.globalPreconditions = const <SyncPrecondition>[],
    super.logger = const NoopSyncLogger(),
    super.onRetryScheduled,
    super.clock,
  });

  /// Runs all tasks allowed on app-open triggers.
  Future<void> syncOnAppOpen({Map<String, Object?> metadata = const {}}) {
    return runAll(SyncPolicyType.appOpen, metadata: metadata);
  }

  /// Runs all tasks allowed on manual triggers.
  Future<void> syncManually({Map<String, Object?> metadata = const {}}) {
    return runAll(SyncPolicyType.manual, metadata: metadata);
  }

  /// Runs all tasks allowed on background triggers.
  Future<void> syncInBackground({Map<String, Object?> metadata = const {}}) {
    return runAll(SyncPolicyType.background, metadata: metadata);
  }

  /// Retries a single task manually.
  Future<void> retryTask(
    String taskId, {
    Map<String, Object?> metadata = const {},
  }) {
    return runTask(
      taskId,
      policyType: SyncPolicyType.manual,
      metadata: metadata,
    );
  }
}
