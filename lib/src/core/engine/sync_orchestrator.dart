import '../core.dart';

@Deprecated('Use SyncEngine directly.')
class SyncOrchestrator extends SyncEngine {
  SyncOrchestrator({
    required super.taskRegistrations,
    required super.stateStore,
    super.globalPreconditions = const <SyncPrecondition>[],
    super.logger = const NoopSyncLogger(),
    super.onRetryScheduled,
    super.clock,
  });

  Future<void> syncOnAppOpen({Map<String, Object?> metadata = const {}}) {
    return runAll(SyncPolicyType.appOpen, metadata: metadata);
  }

  Future<void> syncManually({Map<String, Object?> metadata = const {}}) {
    return runAll(SyncPolicyType.manual, metadata: metadata);
  }

  Future<void> syncInBackground({Map<String, Object?> metadata = const {}}) {
    return runAll(SyncPolicyType.background, metadata: metadata);
  }

  Future<void> retryTask(
    String taskId, {
    Map<String, Object?> metadata = const {},
  }) {
    return runTask(taskId,
        policyType: SyncPolicyType.manual, metadata: metadata);
  }
}
