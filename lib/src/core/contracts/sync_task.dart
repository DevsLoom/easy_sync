import 'dart:async';

import '../models/retry_config.dart';
import '../models/sync_context.dart';
import '../models/sync_policy.dart';
import '../models/sync_result.dart';
import 'precondition.dart';
import 'sync_task_handler.dart';

typedef SyncTaskRunCallback = FutureOr<void> Function(SyncContext context);
typedef SyncTaskRetryWhen = bool Function(Object error, StackTrace stackTrace);

abstract interface class SyncTask {
  factory SyncTask.fn({
    required String key,
    bool appOpen = true,
    bool manual = true,
    bool background = true,
    RetryConfig retry = const RetryConfig.disabled(),
    List<SyncPrecondition> preconditions = const <SyncPrecondition>[],
    required SyncTaskRunCallback run,
    SyncTaskRetryWhen? retryWhen,
  }) {
    return _FunctionSyncTask(
      key: key,
      appOpen: appOpen,
      manual: manual,
      background: background,
      retry: retry,
      preconditions: preconditions,
      run: run,
      retryWhen: retryWhen,
    );
  }

  String get key;

  SyncPolicy get policy;

  List<SyncPrecondition> get preconditions;

  SyncTaskHandler get handler;
}

final class _FunctionSyncTask implements SyncTask {
  _FunctionSyncTask({
    required this.key,
    required bool appOpen,
    required bool manual,
    required bool background,
    required RetryConfig retry,
    required List<SyncPrecondition> preconditions,
    required SyncTaskRunCallback run,
    SyncTaskRetryWhen? retryWhen,
  }) : policy = SyncPolicy(
         appOpen: appOpen,
         manual: manual,
         background: background,
         retry: retry,
       ),
       preconditions = List<SyncPrecondition>.unmodifiable(preconditions),
       handler = _FunctionSyncTaskHandler(run: run, retryWhen: retryWhen);

  @override
  final String key;

  @override
  final SyncPolicy policy;

  @override
  final List<SyncPrecondition> preconditions;

  @override
  final SyncTaskHandler handler;
}

final class _FunctionSyncTaskHandler implements SyncTaskHandler {
  const _FunctionSyncTaskHandler({required this.run, this.retryWhen});

  final SyncTaskRunCallback run;
  final SyncTaskRetryWhen? retryWhen;

  @override
  Future<SyncResult> execute(SyncContext context) async {
    try {
      await run(context);
      return SyncResult.success();
    } catch (error, stackTrace) {
      if (retryWhen?.call(error, stackTrace) ?? false) {
        return SyncResult.retryable(error: error, stackTrace: stackTrace);
      }

      return SyncResult.failure(error: error, stackTrace: stackTrace);
    }
  }
}
