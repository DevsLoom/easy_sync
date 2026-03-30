import 'sync_context.dart';
import 'sync_task_result.dart';

abstract interface class SyncTask {
  String get id;

  String get description;

  Future<SyncTaskResult> run(SyncContext context);
}
