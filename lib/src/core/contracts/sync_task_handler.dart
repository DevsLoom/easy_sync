import '../models/sync_context.dart';
import '../models/sync_result.dart';

/// Executes sync work for a task.
abstract interface class SyncTaskHandler {
  /// Runs the sync task and returns its outcome.
  Future<SyncResult> execute(SyncContext context);
}
