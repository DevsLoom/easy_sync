import 'dart:async';

import '../core.dart';

class SyncEngine {
  SyncEngine({
    required List<SyncTaskRegistration> taskRegistrations,
    required SyncTaskStateStore stateStore,
    this.globalPreconditions = const <SyncPrecondition>[],
    this.logger = const NoopSyncLogger(),
    this.onRetryScheduled,
    this.taskTimeout,
    this.debugMode = false,
    this.isolateTaskFailures = true,
    DateTime Function()? clock,
  }) : _stateStore = stateStore,
       _clock = clock ?? DateTime.now,
       _registrations = {
         for (final registration in taskRegistrations)
           registration.task.key: registration,
       };

  final Map<String, SyncTaskRegistration> _registrations;
  final SyncTaskStateStore _stateStore;
  final List<SyncPrecondition> globalPreconditions;
  final SyncLogger logger;
  final RetryScheduleCallback? onRetryScheduled;
  final Duration? taskTimeout;
  final bool debugMode;
  final bool isolateTaskFailures;
  final DateTime Function() _clock;

  final Map<String, Future<void>> _runningTasks = <String, Future<void>>{};
  final StreamController<SyncTaskState> _stateUpdates =
      StreamController<SyncTaskState>.broadcast();

  Stream<SyncTaskState> get stateUpdates => _stateUpdates.stream;

  void registerTask(SyncTaskRegistration registration) {
    _registrations[registration.task.key] = registration;
  }

  void registerTasks(List<SyncTaskRegistration> registrations) {
    for (final registration in registrations) {
      registerTask(registration);
    }
  }

  Future<void> runTask(
    String taskKey, {
    SyncPolicyType policyType = SyncPolicyType.manual,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final running = _runningTasks[taskKey];
    if (running != null) {
      await running;
      return;
    }

    final future = _executeTaskSafely(
      taskKey: taskKey,
      trigger: _triggerFromPolicyType(policyType),
      metadata: metadata,
    );
    _runningTasks[taskKey] = future;

    try {
      await future;
    } finally {
      _runningTasks.remove(taskKey);
    }
  }

  Future<void> runAll(
    SyncPolicyType policyType, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    for (final registration in _registrations.values) {
      if (!registration.task.policy.allows(
        _triggerFromPolicyType(policyType),
      )) {
        continue;
      }

      try {
        await runTask(
          registration.task.key,
          policyType: policyType,
          metadata: metadata,
        );
      } catch (error, stackTrace) {
        logger.error(
          'Task "${registration.task.key}" crashed during runAll and was isolated.',
          error: error,
          stackTrace: stackTrace,
        );
        if (!isolateTaskFailures) {
          rethrow;
        }
      }
    }
  }

  Future<List<SyncTaskState>> states() => _stateStore.list();

  Future<void> dispose() async {
    await _stateUpdates.close();
  }

  Future<void> _executeTaskSafely({
    required String taskKey,
    required SyncTrigger trigger,
    required Map<String, Object?> metadata,
  }) async {
    try {
      await _executeTask(
        taskKey: taskKey,
        trigger: trigger,
        metadata: metadata,
      );
    } catch (error, stackTrace) {
      logger.error(
        'Task "$taskKey" crashed and was isolated safely.',
        error: error,
        stackTrace: stackTrace,
      );

      try {
        await _saveAndEmit(
          _stateStore
              .getOrCreate(taskKey)
              .copyWith(
                status: SyncTaskStatus.failed,
                lastError: error.toString(),
                lastFinishedAt: _clock(),
                clearNextRetryAt: true,
              ),
        );
      } catch (stateError, stateStack) {
        logger.error(
          'Failed to persist crash state for task "$taskKey".',
          error: stateError,
          stackTrace: stateStack,
        );
      }

      if (!isolateTaskFailures) {
        rethrow;
      }
    }
  }

  Future<void> _executeTask({
    required String taskKey,
    required SyncTrigger trigger,
    required Map<String, Object?> metadata,
  }) async {
    final registration = _registrations[taskKey];
    if (registration == null) {
      logger.warn('Task "$taskKey" is not registered; skipping execution.');
      return;
    }

    _debug('Executing task "$taskKey" with trigger "$trigger".');

    final now = _clock();
    final context = SyncContext(
      metadata: <String, Object?>{
        ...metadata,
        'policyType': _policyTypeFromTrigger(trigger).name,
        'trigger': trigger.name,
        'timestamp': now.toIso8601String(),
        'taskKey': taskKey,
      },
    );

    final blocked = await _firstBlockedPrecondition(
      context,
      taskPreconditions: <SyncPrecondition>[
        ...registration.task.preconditions,
        ...registration.preconditions,
      ],
    );
    if (blocked != null) {
      final blockedState = _stateStore
          .getOrCreate(taskKey)
          .copyWith(
            status: SyncTaskStatus.blocked,
            lastFinishedAt: now,
            lastTrigger: trigger,
            lastError: blocked.reason ?? blocked.name,
            clearNextRetryAt: true,
          );
      await _saveAndEmit(blockedState);
      logger.info(
        'Task "$taskKey" blocked: ${blocked.reason ?? blocked.name}.',
      );
      return;
    }

    final previousState = _stateStore.getOrCreate(taskKey);
    final attempt = previousState.attempt + 1;

    await _saveAndEmit(
      previousState.copyWith(
        status: SyncTaskStatus.running,
        attempt: attempt,
        lastStartedAt: now,
        lastTrigger: trigger,
        clearLastError: true,
      ),
    );

    SyncResult result;
    try {
      final execution = registration.task.handler.execute(context);
      if (taskTimeout == null) {
        result = await execution;
      } else {
        result = await execution.timeout(
          taskTimeout!,
          onTimeout: () => SyncResult.failure(
            error: TimeoutException(
              'Task "$taskKey" timed out after $taskTimeout',
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      result = SyncResult.failure(error: error, stackTrace: stackTrace);
    }

    final finishedAt = _clock();

    if (result.success) {
      await _saveAndEmit(
        _stateStore
            .getOrCreate(taskKey)
            .copyWith(
              status: SyncTaskStatus.success,
              attempt: 0,
              lastFinishedAt: finishedAt,
              clearLastError: true,
              clearNextRetryAt: true,
            ),
      );
      return;
    }

    final error =
        result.error ??
        StateError('Task "$taskKey" failed with unknown error.');

    final delay = result.retryable
        ? registration.task.policy.retry.nextDelay(attempt)
        : null;

    await _saveAndEmit(
      _stateStore
          .getOrCreate(taskKey)
          .copyWith(
            status: SyncTaskStatus.failed,
            lastError: error.toString(),
            lastFinishedAt: finishedAt,
            nextRetryAt: delay == null ? null : finishedAt.add(delay),
            clearNextRetryAt: delay == null,
          ),
    );

    if (delay != null) {
      if (onRetryScheduled != null) {
        await onRetryScheduled!(
          taskId: taskKey,
          delay: delay,
          metadata: metadata,
        );
      }

      unawaited(
        _scheduleRetry(taskKey: taskKey, delay: delay, metadata: metadata),
      );
      logger.warn('Task "$taskKey" failed and retry was scheduled in $delay.');
      return;
    }

    logger.error(
      'Task "$taskKey" failed and no retry will be attempted.',
      error: error,
      stackTrace: result.stackTrace,
    );
  }

  Future<void> _scheduleRetry({
    required String taskKey,
    required Duration delay,
    required Map<String, Object?> metadata,
  }) async {
    await Future<void>.delayed(delay);

    await runTask(
      taskKey,
      policyType: _policyTypeFromTrigger(SyncTrigger.retry),
      metadata: <String, Object?>{...metadata, 'scheduledRetry': true},
    );
  }

  Future<void> _saveAndEmit(SyncTaskState state) async {
    await _stateStore.save(state);
    _stateUpdates.add(state);
    _debug(
      'Task state updated: taskKey=${state.taskId}, status=${state.status.name}, attempt=${state.attempt}',
    );
  }

  Future<_PreconditionFailure?> _firstBlockedPrecondition(
    SyncContext context, {
    required List<SyncPrecondition> taskPreconditions,
  }) async {
    final all = <SyncPrecondition>[
      ...globalPreconditions,
      ...taskPreconditions,
    ];

    for (final precondition in all) {
      final result = await precondition.check(context);
      if (result.blocked) {
        return _PreconditionFailure(
          name: precondition.name,
          reason: result.reason,
        );
      }
    }
    return null;
  }

  void _debug(String message) {
    if (!debugMode) {
      return;
    }
    logger.info('[DEBUG] $message');
  }

  SyncTrigger _triggerFromPolicyType(SyncPolicyType policyType) {
    switch (policyType) {
      case SyncPolicyType.appOpen:
        return SyncTrigger.appOpen;
      case SyncPolicyType.manual:
        return SyncTrigger.manual;
      case SyncPolicyType.background:
        return SyncTrigger.background;
    }
  }

  SyncPolicyType _policyTypeFromTrigger(SyncTrigger trigger) {
    switch (trigger) {
      case SyncTrigger.appOpen:
        return SyncPolicyType.appOpen;
      case SyncTrigger.manual:
      case SyncTrigger.retry:
        return SyncPolicyType.manual;
      case SyncTrigger.background:
        return SyncPolicyType.background;
    }
  }
}

typedef RetryScheduleCallback =
    Future<void> Function({
      required String taskId,
      required Duration delay,
      required Map<String, Object?> metadata,
    });

class _PreconditionFailure implements SyncPrecondition {
  _PreconditionFailure({required this.name, this.reason});

  @override
  final String name;

  final String? reason;

  @override
  Future<PreconditionResult> check(SyncContext context) {
    return Future<PreconditionResult>.value(
      PreconditionResult.blocked(reason: reason),
    );
  }
}
