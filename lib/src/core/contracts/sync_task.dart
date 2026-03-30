import '../models/sync_policy.dart';
import 'precondition.dart';
import 'sync_task_handler.dart';

abstract interface class SyncTask {
  String get key;

  SyncPolicy get policy;

  List<SyncPrecondition> get preconditions;

  SyncTaskHandler get handler;
}
