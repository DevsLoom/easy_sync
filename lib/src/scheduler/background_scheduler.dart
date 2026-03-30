abstract interface class SyncBackgroundScheduler {
  Future<void> schedulePeriodic({
    required String uniqueName,
    required String taskName,
    required Duration frequency,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  });

  Future<void> scheduleOneOff({
    required String uniqueName,
    required String taskName,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  });

  Future<void> cancelByUniqueName(String uniqueName);

  Future<void> cancelAll();
}
