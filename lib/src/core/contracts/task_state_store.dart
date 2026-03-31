import '../models/task_state.dart';

/// Storage abstraction for persisting sync task state.
abstract interface class SyncTaskStateStore {
  /// Returns the current state for [taskId], creating an initial value if needed.
  SyncTaskState getOrCreate(String taskId);

  /// Saves the latest state for a task.
  Future<void> save(SyncTaskState state);

  /// Lists all known task states.
  Future<List<SyncTaskState>> list();
}
