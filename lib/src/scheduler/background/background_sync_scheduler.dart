import '../../core/core.dart';
import 'sync_background_scheduler.dart';

/// High-level helper for triggering and scheduling background sync.
class BackgroundSyncScheduler {
  /// Creates a background sync scheduler.
  BackgroundSyncScheduler({
    required SyncOrchestrator orchestrator,
    SyncBackgroundScheduler? scheduler,
  }) : _orchestrator = orchestrator,
       _scheduler = scheduler;

  final SyncOrchestrator _orchestrator;
  final SyncBackgroundScheduler? _scheduler;

  /// Triggers background-eligible tasks immediately.
  Future<void> triggerNow({Map<String, Object?> metadata = const {}}) {
    return _orchestrator.syncInBackground(metadata: metadata);
  }

  /// Schedules periodic background execution.
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

  /// Schedules a one-off background execution.
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
