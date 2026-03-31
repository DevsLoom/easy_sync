import '../../core/core.dart';

/// High-level helper for manually triggering sync.
class ManualSyncScheduler {
  /// Creates a manual sync scheduler.
  ManualSyncScheduler(this._orchestrator);

  final SyncOrchestrator _orchestrator;

  /// Triggers manual sync immediately.
  Future<void> trigger({Map<String, Object?> metadata = const {}}) {
    return _orchestrator.syncManually(metadata: metadata);
  }
}
