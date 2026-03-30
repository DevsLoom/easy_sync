import '../models/sync_context.dart';
import '../models/sync_result.dart';

abstract interface class SyncTaskHandler {
  Future<SyncResult> execute(SyncContext context);
}
