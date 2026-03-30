import '../core/core.dart';
import 'sync_task_registration.dart';

typedef RetryScheduleCallback =
    Future<void> Function({
      required String taskId,
      required Duration delay,
      required Map<String, Object?> metadata,
    });

class SyncOrchestrator {
  SyncOrchestrator({
    required List<SyncTaskRegistration> taskRegistrations,
    required SyncTaskStateStore stateStore,
    this.globalPreconditions = const <SyncPrecondition>[],
    this.retryPolicy = const NoRetryPolicy(),
    this.logger = const NoopSyncLogger(),
    this.onRetryScheduled,
    DateTime Function()? clock,
  }) : _stateStore = stateStore,
       _clock = clock ?? DateTime.now,
       _registrations = {
         for (final registration in taskRegistrations)
           registration.task.id: registration,
       };

  final Map<String, SyncTaskRegistration> _registrations;
  final SyncTaskStateStore _stateStore;
  final List<SyncPrecondition> globalPreconditions;
  final RetryPolicy retryPolicy;
  final SyncLogger logger;
  final RetryScheduleCallback? onRetryScheduled;
  final DateTime Function() _clock;

  Future<void> syncOnAppOpen({Map<String, Object?> metadata = const {}}) {
    return runAll(trigger: SyncTrigger.appOpen, metadata: metadata);
  }

  Future<void> syncManually({Map<String, Object?> metadata = const {}}) {
    return runAll(trigger: SyncTrigger.manual, metadata: metadata);
  }

  Future<void> syncInBackground({Map<String, Object?> metadata = const {}}) {
    return runAll(trigger: SyncTrigger.background, metadata: metadata);
  }

  Future<void> retryTask(
    String taskId, {
    Map<String, Object?> metadata = const {},
  }) {
    return _runTaskById(
      taskId: taskId,
      trigger: SyncTrigger.retry,
      metadata: metadata,
    );
  }

  Future<void> runAll({
    required SyncTrigger trigger,
    Map<String, Object?> metadata = const {},
  }) async {
    for (final taskId in _registrations.keys) {
      await _runTaskById(taskId: taskId, trigger: trigger, metadata: metadata);
    }
  }

  Future<void> _runTaskById({
    required String taskId,
    required SyncTrigger trigger,
    required Map<String, Object?> metadata,
  }) async {
    final registration = _registrations[taskId];
    if (registration == null) {
      logger.warn('Task "$taskId" is not registered; skipping execution.');
      return;
    }

    final now = _clock();
    final context = SyncContext(
      trigger: trigger,
      timestamp: now,
      metadata: metadata,
    );

    final unmet = await _firstUnmetPrecondition(
      context,
      taskPreconditions: registration.preconditions,
    );
    if (unmet != null) {
      final skippedState = _stateStore
          .getOrCreate(taskId)
          .copyWith(
            status: SyncTaskStatus.skipped,
            lastFinishedAt: now,
            lastTrigger: trigger,
            clearNextRetryAt: true,
          );
      await _stateStore.save(skippedState);
      logger.info('Task "$taskId" skipped: ${unmet.reason ?? unmet.name}.');
      return;
    }

    final previousState = _stateStore.getOrCreate(taskId);
    final attempt = previousState.attempt + 1;

    await _stateStore.save(
      previousState.copyWith(
        status: SyncTaskStatus.running,
        attempt: attempt,
        lastStartedAt: now,
        lastTrigger: trigger,
        clearLastError: true,
      ),
    );

    SyncTaskResult result;
    try {
      result = await registration.task.run(context);
    } catch (error, stackTrace) {
      result = SyncTaskResult.failure(error: error, stackTrace: stackTrace);
    }

    final finishedAt = _clock();

    if (result.success) {
      await _stateStore.save(
        _stateStore
            .getOrCreate(taskId)
            .copyWith(
              status: SyncTaskStatus.succeeded,
              attempt: 0,
              lastFinishedAt: finishedAt,
              clearLastError: true,
              clearNextRetryAt: true,
            ),
      );
      return;
    }

    if (result.skipped) {
      await _stateStore.save(
        _stateStore
            .getOrCreate(taskId)
            .copyWith(
              status: SyncTaskStatus.skipped,
              lastFinishedAt: finishedAt,
              clearNextRetryAt: true,
            ),
      );
      return;
    }

    final error =
        result.error ?? StateError('Task "$taskId" failed with unknown error.');
    final delay = retryPolicy.nextDelay(attempt: attempt, error: error);

    if (delay != null) {
      final nextRetryAt = finishedAt.add(delay);
      await _stateStore.save(
        _stateStore
            .getOrCreate(taskId)
            .copyWith(
              status: SyncTaskStatus.waitingRetry,
              lastError: error.toString(),
              lastFinishedAt: finishedAt,
              nextRetryAt: nextRetryAt,
            ),
      );

      if (onRetryScheduled != null) {
        await onRetryScheduled!(
          taskId: taskId,
          delay: delay,
          metadata: metadata,
        );
      }
      logger.warn('Task "$taskId" failed and retry was scheduled in $delay.');
      return;
    }

    await _stateStore.save(
      _stateStore
          .getOrCreate(taskId)
          .copyWith(
            status: SyncTaskStatus.failed,
            lastError: error.toString(),
            lastFinishedAt: finishedAt,
            clearNextRetryAt: true,
          ),
    );
    logger.error(
      'Task "$taskId" failed and no retry will be attempted.',
      error: error,
    );
  }

  Future<_PreconditionFailure?> _firstUnmetPrecondition(
    SyncContext context, {
    required List<SyncPrecondition> taskPreconditions,
  }) async {
    final all = <SyncPrecondition>[
      ...globalPreconditions,
      ...taskPreconditions,
    ];
    for (final precondition in all) {
      final result = await precondition.evaluate(context);
      if (!result.isMet) {
        return _PreconditionFailure(
          name: precondition.name,
          reason: result.reason,
        );
      }
    }
    return null;
  }

  Future<List<SyncTaskState>> states() => _stateStore.list();
}

class _PreconditionFailure implements SyncPrecondition {
  _PreconditionFailure({required this.name, this.reason});

  @override
  final String name;

  final String? reason;

  @override
  Future<PreconditionResult> evaluate(SyncContext context) {
    return Future<PreconditionResult>.value(
      PreconditionResult.unmet(reason: reason),
    );
  }
}
