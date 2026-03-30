import 'task_state.dart';
import 'task_state_store.dart';

class InMemorySyncTaskStateStore implements SyncTaskStateStore {
  final Map<String, SyncTaskState> _states = <String, SyncTaskState>{};

  @override
  SyncTaskState getOrCreate(String taskId) {
    return _states.putIfAbsent(taskId, () => SyncTaskState.initial(taskId));
  }

  @override
  Future<List<SyncTaskState>> list() async {
    return _states.values.toList(growable: false);
  }

  @override
  Future<void> save(SyncTaskState state) async {
    _states[state.taskId] = state;
  }
}
