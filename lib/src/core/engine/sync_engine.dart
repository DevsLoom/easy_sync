import 'dart:async';

import '../core.dart';

/// Core task execution engine responsible for orchestration, retries, and state updates.
class SyncEngine {
  /// Creates a sync execution engine.
  ///
  /// [taskRegistrations] are indexed by task key.
  /// [stateStore] persists the latest task state.
  /// [globalPreconditions] are evaluated for every task.
  /// [logger] receives engine log output.
  /// [onRetryScheduled] is notified when retries are queued.
  /// [taskTimeout] limits a single task run.
  /// [debugMode] enables extra diagnostics.
  /// [isolateTaskFailures] prevents one task failure from aborting others.
  /// [rateLimit] limits how often tasks can execute.
  /// [circuitBreaker] temporarily opens after repeated failures.
  /// [executionHistory], [consecutiveFailures], and [openCircuits] allow restoring
  /// in-memory execution control state.
  /// [clock] overrides the time source for testing.
  SyncEngine({
    required List<SyncTaskRegistration> taskRegistrations,
    required SyncTaskStateStore stateStore,
    this.globalPreconditions = const <SyncPrecondition>[],
    this.logger = const NoopSyncLogger(),
    this.onRetryScheduled,
    this.taskTimeout,
    this.debugMode = false,
    this.isolateTaskFailures = true,
    this.rateLimit = const SyncRateLimit.disabled(),
    this.circuitBreaker = const SyncCircuitBreaker.disabled(),
    Map<String, List<DateTime>>? executionHistory,
    Map<String, int>? consecutiveFailures,
    Map<String, DateTime?>? openCircuits,
    DateTime Function()? clock,
  }) : _stateStore = stateStore,
       _clock = clock ?? DateTime.now,
       _executions = executionHistory ?? <String, List<DateTime>>{},
       _consecutiveFailures = consecutiveFailures ?? <String, int>{},
       _openCircuits = openCircuits ?? <String, DateTime?>{},
       _registrations = {
         for (final registration in taskRegistrations)
           registration.task.key: registration,
       };

  final Map<String, SyncTaskRegistration> _registrations;
  final SyncTaskStateStore _stateStore;

  /// Preconditions evaluated before every task-specific precondition.
  final List<SyncPrecondition> globalPreconditions;

  /// Logger used for engine diagnostics.
  final SyncLogger logger;

  /// Optional callback invoked when a retry is scheduled.
  final RetryScheduleCallback? onRetryScheduled;

  /// Optional maximum runtime allowed for a single task execution.
  final Duration? taskTimeout;

  /// Whether debug-oriented behavior is enabled.
  final bool debugMode;

  /// Whether task failures should be isolated from sibling task execution.
  final bool isolateTaskFailures;

  /// Rate limit applied before a task can start.
  final SyncRateLimit rateLimit;

  /// Circuit breaker applied before a task can start.
  final SyncCircuitBreaker circuitBreaker;
  final DateTime Function() _clock;

  final Map<String, Future<void>> _runningTasks = <String, Future<void>>{};
  final Map<String, List<DateTime>> _executions;
  final Map<String, int> _consecutiveFailures;
  final Map<String, DateTime?> _openCircuits;
  final StreamController<SyncTaskState> _stateUpdates =
      StreamController<SyncTaskState>.broadcast();

  /// Stream of emitted task state updates.
  Stream<SyncTaskState> get stateUpdates => _stateUpdates.stream;

  /// Registers a single task at runtime.
  void registerTask(SyncTaskRegistration registration) {
    _registrations[registration.task.key] = registration;
  }

  /// Registers multiple tasks at runtime.
  void registerTasks(List<SyncTaskRegistration> registrations) {
    for (final registration in registrations) {
      registerTask(registration);
    }
  }

  /// Runs a single task by key.
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

  /// Runs all tasks allowed by the given [policyType].
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

  /// Returns the latest known states for all tasks.
  Future<List<SyncTaskState>> states() => _stateStore.list();

  /// Releases engine resources.
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

    final openUntil = _openCircuitUntil(taskKey, now);
    if (openUntil != null) {
      final blockedState = _stateStore
          .getOrCreate(taskKey)
          .copyWith(
            status: SyncTaskStatus.blocked,
            lastFinishedAt: now,
            lastTrigger: trigger,
            lastError:
                'Circuit breaker open until ${openUntil.toIso8601String()}',
            clearNextRetryAt: true,
          );
      await _saveAndEmit(blockedState);
      logger.warn(
        'Task "$taskKey" blocked by circuit breaker until ${openUntil.toIso8601String()}.',
      );
      return;
    }

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

    if (!_canExecuteUnderRateLimit(taskKey, now)) {
      final blockedState = _stateStore
          .getOrCreate(taskKey)
          .copyWith(
            status: SyncTaskStatus.blocked,
            lastFinishedAt: now,
            lastTrigger: trigger,
            lastError:
                'Rate limit exceeded (${rateLimit.maxExecutions}/${rateLimit.per.inSeconds}s window)',
            clearNextRetryAt: true,
          );
      await _saveAndEmit(blockedState);
      logger.warn('Task "$taskKey" blocked by rate limit policy.');
      return;
    }

    _recordExecution(taskKey, now);

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
      _recordSuccess(taskKey);
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

    _recordFailure(taskKey, finishedAt);

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

  DateTime? _openCircuitUntil(String taskKey, DateTime now) {
    if (!circuitBreaker.enabled) {
      return null;
    }

    final openUntil = _openCircuits[taskKey];
    if (openUntil == null) {
      return null;
    }

    if (now.isAfter(openUntil) || now.isAtSameMomentAs(openUntil)) {
      _openCircuits[taskKey] = null;
      _consecutiveFailures[taskKey] = 0;
      return null;
    }

    return openUntil;
  }

  bool _canExecuteUnderRateLimit(String taskKey, DateTime now) {
    if (!rateLimit.enabled) {
      return true;
    }

    final history = _executions.putIfAbsent(taskKey, () => <DateTime>[]);
    final windowStart = now.subtract(rateLimit.per);
    history.removeWhere((timestamp) => timestamp.isBefore(windowStart));
    return history.length < rateLimit.maxExecutions;
  }

  void _recordExecution(String taskKey, DateTime now) {
    if (!rateLimit.enabled) {
      return;
    }

    final history = _executions.putIfAbsent(taskKey, () => <DateTime>[]);
    history.add(now);
  }

  void _recordSuccess(String taskKey) {
    if (!circuitBreaker.enabled) {
      return;
    }

    _consecutiveFailures[taskKey] = 0;
    _openCircuits[taskKey] = null;
  }

  void _recordFailure(String taskKey, DateTime finishedAt) {
    if (!circuitBreaker.enabled) {
      return;
    }

    final failures = (_consecutiveFailures[taskKey] ?? 0) + 1;
    _consecutiveFailures[taskKey] = failures;

    if (failures >= circuitBreaker.failureThreshold) {
      _openCircuits[taskKey] = finishedAt.add(circuitBreaker.openFor);
      logger.warn(
        'Task "$taskKey" circuit breaker opened for ${circuitBreaker.openFor}.',
      );
    }
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

/// Callback fired when a retry has been scheduled.
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
