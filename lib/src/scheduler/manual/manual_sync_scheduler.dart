import '../../core/core.dart';

class ManualSyncScheduler {
  ManualSyncScheduler(this._orchestrator);

  final SyncOrchestrator _orchestrator;

  Future<void> trigger({Map<String, Object?> metadata = const {}}) {
    return _orchestrator.syncManually(metadata: metadata);
  }
}
