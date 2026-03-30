import '../../core/core.dart';
import 'sync_background_scheduler.dart';

class BackgroundSyncScheduler {
  BackgroundSyncScheduler({
    required SyncOrchestrator orchestrator,
    SyncBackgroundScheduler? scheduler,
  })  : _orchestrator = orchestrator,
        _scheduler = scheduler;

  final SyncOrchestrator _orchestrator;
  final SyncBackgroundScheduler? _scheduler;

  Future<void> triggerNow({Map<String, Object?> metadata = const {}}) {
    return _orchestrator.syncInBackground(metadata: metadata);
  }

  Future<void> schedulePeriodic({
    required String uniqueName,
    required String taskName,
    required Duration frequency,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  }) async {
    final scheduler = _scheduler;
    if (scheduler == null) {
      throw StateError('No SyncBackgroundScheduler has been provided.');
    }

    await scheduler.schedulePeriodic(
      uniqueName: uniqueName,
      taskName: taskName,
      frequency: frequency,
      inputData: inputData,
      initialDelay: initialDelay,
    );
  }

  Future<void> scheduleOneOff({
    required String uniqueName,
    required String taskName,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  }) async {
    final scheduler = _scheduler;
    if (scheduler == null) {
      throw StateError('No SyncBackgroundScheduler has been provided.');
    }

    await scheduler.scheduleOneOff(
      uniqueName: uniqueName,
      taskName: taskName,
      inputData: inputData,
      initialDelay: initialDelay,
    );
  }
}
