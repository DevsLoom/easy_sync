/// Runtime status of a sync task.
enum SyncTaskStatus {
  /// Task has not started yet.
  idle,

  /// Task is currently running.
  running,

  /// Task completed successfully.
  success,

  /// Task finished with a failure.
  failed,

  /// Task was blocked before execution.
  blocked,
}
