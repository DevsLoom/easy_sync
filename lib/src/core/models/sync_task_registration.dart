import '../contracts/precondition.dart';
import '../contracts/sync_task.dart';

class SyncTaskRegistration {
  const SyncTaskRegistration({
    required this.task,
    this.preconditions = const <SyncPrecondition>[],
  });

  final SyncTask task;

  // Optional extra preconditions layered on top of task-level preconditions.
  final List<SyncPrecondition> preconditions;
}
