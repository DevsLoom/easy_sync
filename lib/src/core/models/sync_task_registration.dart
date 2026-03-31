import '../contracts/precondition.dart';
import '../contracts/sync_task.dart';

/// Registration object that combines a task with extra preconditions.
class SyncTaskRegistration {
  /// Creates a task registration.
  const SyncTaskRegistration({
    required this.task,
    this.preconditions = const <SyncPrecondition>[],
  });

  /// Registered task.
  final SyncTask task;

  /// Optional extra preconditions layered on top of task-level preconditions.
  final List<SyncPrecondition> preconditions;
}
