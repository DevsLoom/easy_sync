import 'task_state.dart';

abstract interface class SyncTaskStateStore {
  SyncTaskState getOrCreate(String taskId);

  Future<void> save(SyncTaskState state);

  Future<List<SyncTaskState>> list();
}
