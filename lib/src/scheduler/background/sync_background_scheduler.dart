/// Platform scheduler interface used to register background work.
abstract interface class SyncBackgroundScheduler {
  /// Schedules periodic background work.
  Future<void> schedulePeriodic({
    required String uniqueName,
    required String taskName,
    required Duration frequency,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  });

  /// Schedules one-off background work.
  Future<void> scheduleOneOff({
    required String uniqueName,
    required String taskName,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  });

  /// Cancels a scheduled task by unique name.
  Future<void> cancelByUniqueName(String uniqueName);

  /// Cancels all scheduled tasks.
  Future<void> cancelAll();
}
