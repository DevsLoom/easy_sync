import '../../core/core.dart';

class AppOpenSyncScheduler {
  AppOpenSyncScheduler(this._orchestrator);

  final SyncOrchestrator _orchestrator;

  Future<void> trigger({Map<String, Object?> metadata = const {}}) {
    return _orchestrator.syncOnAppOpen(metadata: metadata);
  }
}
