import '../core/core.dart';

class SyncTaskRegistration {
  const SyncTaskRegistration({
    required this.task,
    this.preconditions = const <SyncPrecondition>[],
  });

  final SyncTask task;
  final List<SyncPrecondition> preconditions;
}
