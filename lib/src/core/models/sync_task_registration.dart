import '../contracts/precondition.dart';
import '../contracts/sync_task.dart';

class SyncTaskRegistration {
  const SyncTaskRegistration({
    required this.task,
    this.preconditions = const <SyncPrecondition>[],
  });

  final SyncTask task;
  final List<SyncPrecondition> preconditions;
}
