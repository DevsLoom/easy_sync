import 'dart:async';

import 'package:easy_sync/easy_sync.dart';
import 'package:test/test.dart';

void main() {
  group('SyncOrchestrator', () {
    test('runs task successfully and resets attempts', () async {
      final store = InMemorySyncTaskStateStore();
      final orchestrator = SyncOrchestrator(
        taskRegistrations: [
          SyncTaskRegistration(task: _FakeTask.success(key: 'a')),
        ],
        stateStore: store,
      );

      await orchestrator.syncManually();

      final state = store.getOrCreate('a');
      expect(state.status, SyncTaskStatus.success);
      expect(state.attempt, 0);
      expect(state.lastError, isNull);
    });

    test('skips task when precondition is unmet', () async {
      final store = InMemorySyncTaskStateStore();
      final orchestrator = SyncOrchestrator(
        taskRegistrations: [
          SyncTaskRegistration(
            task: _FakeTask.success(key: 'a'),
            preconditions: [
              PredicatePrecondition(
                name: 'network',
                predicate: (_) async => false,
              ),
            ],
          ),
        ],
        stateStore: store,
      );

      await orchestrator.syncOnAppOpen();

      final state = store.getOrCreate('a');
      expect(state.status, SyncTaskStatus.blocked);
      expect(state.attempt, 0);
    });

    test('schedules retry when task fails and policy returns delay', () async {
      final scheduled = <String, Duration>{};
      final store = InMemorySyncTaskStateStore();
      final orchestrator = SyncOrchestrator(
        taskRegistrations: [
          SyncTaskRegistration(task: _FakeTask.failure(key: 'a')),
        ],
        stateStore: store,
        onRetryScheduled:
            ({
              required String taskId,
              required Duration delay,
              required Map<String, Object?> metadata,
            }) async {
              scheduled[taskId] = delay;
            },
      );

      await orchestrator.syncInBackground();

      final state = store.getOrCreate('a');
      expect(state.status, SyncTaskStatus.failed);
      expect(state.attempt, 1);
      expect(scheduled['a'], const Duration(seconds: 3));
      expect(state.nextRetryAt, isNotNull);
    });

    test(
      'does not schedule retry when task failure is non-retryable',
      () async {
        final scheduled = <String, Duration>{};
        final store = InMemorySyncTaskStateStore();
        final orchestrator = SyncOrchestrator(
          taskRegistrations: [
            SyncTaskRegistration(task: _FakeTask.nonRetryableFailure(key: 'a')),
          ],
          stateStore: store,
          onRetryScheduled:
              ({
                required String taskId,
                required Duration delay,
                required Map<String, Object?> metadata,
              }) async {
                scheduled[taskId] = delay;
              },
        );

        await orchestrator.syncInBackground();

        final state = store.getOrCreate('a');
        expect(state.status, SyncTaskStatus.failed);
        expect(state.attempt, 1);
        expect(scheduled, isEmpty);
        expect(state.nextRetryAt, isNull);
      },
    );
  });

  group('SyncEngine', () {
    test('emits state updates while running task', () async {
      final store = InMemorySyncTaskStateStore();
      final engine = SyncEngine(
        taskRegistrations: [
          SyncTaskRegistration(task: _FakeTask.success(key: 'stream-task')),
        ],
        stateStore: store,
      );

      final updates = <SyncTaskStatus>[];
      final subscription = engine.stateUpdates.listen((state) {
        if (state.taskId == 'stream-task') {
          updates.add(state.status);
        }
      });

      await engine.runTask('stream-task');
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(updates, contains(SyncTaskStatus.running));
      expect(updates, contains(SyncTaskStatus.success));
    });

    test('prevents duplicate execution for same task key', () async {
      final store = InMemorySyncTaskStateStore();
      final delayedHandler = _DelayedCountingHandler();
      final engine = SyncEngine(
        taskRegistrations: [
          SyncTaskRegistration(
            task: _TaskWithHandler(
              key: 'single-flight',
              handler: delayedHandler,
            ),
          ),
        ],
        stateStore: store,
      );

      final first = engine.runTask('single-flight');
      final second = engine.runTask('single-flight');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(delayedHandler.count, 1);

      delayedHandler.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(delayedHandler.count, 1);
      expect(store.getOrCreate('single-flight').status, SyncTaskStatus.success);
    });

    test('marks task as failed when execution times out', () async {
      final store = InMemorySyncTaskStateStore();
      final engine = SyncEngine(
        taskRegistrations: [
          SyncTaskRegistration(
            task: _TaskWithHandler(
              key: 'timeout-task',
              handler: _SlowSuccessHandler(
                delay: const Duration(milliseconds: 50),
              ),
            ),
          ),
        ],
        stateStore: store,
        taskTimeout: const Duration(milliseconds: 10),
      );

      await engine.runTask('timeout-task');

      final state = store.getOrCreate('timeout-task');
      expect(state.status, SyncTaskStatus.failed);
      expect(state.lastError, contains('timed out'));
      expect(state.attempt, 1);
    });

    test('isolates task crash and continues runAll execution', () async {
      final store = InMemorySyncTaskStateStore();
      final healthyTask = _CountingTask(key: 'healthy-task');

      final engine = SyncEngine(
        taskRegistrations: [
          SyncTaskRegistration(
            task: _TaskWithHandler(
              key: 'broken-task',
              handler: _FakeTaskHandler(SyncResult.success()),
            ),
            preconditions: [
              PredicatePrecondition(
                name: 'crashing-precondition',
                predicate: (_) async =>
                    throw StateError('precondition crashed'),
              ),
            ],
          ),
          SyncTaskRegistration(task: healthyTask),
        ],
        stateStore: store,
      );

      await engine.runAll(SyncPolicyType.background);

      expect(store.getOrCreate('broken-task').status, SyncTaskStatus.failed);
      expect(store.getOrCreate('healthy-task').status, SyncTaskStatus.success);
      expect(healthyTask.executionCount, 1);
    });

    test('emits debug logs when debug mode is enabled', () async {
      final logger = _CollectingLogger();
      final engine = SyncEngine(
        taskRegistrations: [
          SyncTaskRegistration(task: _FakeTask.success(key: 'debug-task')),
        ],
        stateStore: InMemorySyncTaskStateStore(),
        logger: logger,
        debugMode: true,
      );

      await engine.runTask('debug-task');

      expect(logger.infos.any((msg) => msg.contains('[DEBUG]')), isTrue);
    });

    test('blocks task when sliding-window rate limit is exceeded', () async {
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final task = _CountingTask(key: 'rate-limited-task');
      final store = InMemorySyncTaskStateStore();
      final engine = SyncEngine(
        taskRegistrations: [SyncTaskRegistration(task: task)],
        stateStore: store,
        rateLimit: const SyncRateLimit.slidingWindow(
          maxExecutions: 1,
          per: Duration(minutes: 1),
        ),
        clock: () => now,
      );

      await engine.runTask('rate-limited-task');
      await engine.runTask('rate-limited-task');

      final blockedState = store.getOrCreate('rate-limited-task');
      expect(task.executionCount, 1);
      expect(blockedState.status, SyncTaskStatus.blocked);
      expect(blockedState.lastError, contains('Rate limit exceeded'));

      now = now.add(const Duration(minutes: 2));
      await engine.runTask('rate-limited-task');

      final finalState = store.getOrCreate('rate-limited-task');
      expect(task.executionCount, 2);
      expect(finalState.status, SyncTaskStatus.success);
    });

    test('opens circuit breaker after repeated failures', () async {
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final store = InMemorySyncTaskStateStore();
      final engine = SyncEngine(
        taskRegistrations: [
          SyncTaskRegistration(
            task: _TaskWithHandler(
              key: 'circuit-task',
              handler: _FakeTaskHandler(
                SyncResult.failure(error: StateError('server down')),
              ),
            ),
          ),
        ],
        stateStore: store,
        circuitBreaker: const SyncCircuitBreaker.standard(
          failureThreshold: 2,
          openFor: Duration(minutes: 5),
        ),
        clock: () => now,
      );

      await engine.runTask('circuit-task');
      await engine.runTask('circuit-task');
      await engine.runTask('circuit-task');

      final blockedState = store.getOrCreate('circuit-task');
      expect(blockedState.status, SyncTaskStatus.blocked);
      expect(blockedState.lastError, contains('Circuit breaker open until'));

      now = now.add(const Duration(minutes: 6));
      await engine.runTask('circuit-task');

      final recoveredState = store.getOrCreate('circuit-task');
      expect(recoveredState.status, SyncTaskStatus.failed);
      expect(recoveredState.lastError, contains('Bad state: server down'));
    });
  });
}

class _FakeTask implements SyncTask {
  _FakeTask.success({required this.key})
    : _handler = _FakeTaskHandler(SyncResult.success()),
      policy = const SyncPolicy();

  _FakeTask.failure({required this.key})
    : _handler = _FakeTaskHandler(
        SyncResult.retryable(error: StateError('boom')),
      ),
      policy = const SyncPolicy(
        retry: RetryConfig.exponential(
          initialDelay: Duration(seconds: 3),
          maxRetries: 1,
        ),
      );

  _FakeTask.nonRetryableFailure({required this.key})
    : _handler = _FakeTaskHandler(
        SyncResult.failure(error: StateError('boom')),
      ),
      policy = const SyncPolicy(
        retry: RetryConfig.exponential(
          initialDelay: Duration(seconds: 3),
          maxRetries: 3,
        ),
      );

  @override
  final String key;

  @override
  final SyncPolicy policy;

  @override
  List<SyncPrecondition> get preconditions => const <SyncPrecondition>[];

  @override
  SyncTaskHandler get handler => _handler;

  final SyncTaskHandler _handler;
}

class _FakeTaskHandler implements SyncTaskHandler {
  _FakeTaskHandler(this._result);

  final SyncResult _result;

  @override
  Future<SyncResult> execute(SyncContext context) async => _result;
}

class _TaskWithHandler implements SyncTask {
  _TaskWithHandler({required this.key, required this.handler});

  @override
  final String key;

  @override
  final SyncTaskHandler handler;

  @override
  SyncPolicy get policy => const SyncPolicy();

  @override
  List<SyncPrecondition> get preconditions => const <SyncPrecondition>[];
}

class _DelayedCountingHandler implements SyncTaskHandler {
  final Completer<void> _completer = Completer<void>();
  int count = 0;

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  @override
  Future<SyncResult> execute(SyncContext context) async {
    count += 1;
    await _completer.future;
    return SyncResult.success();
  }
}

class _SlowSuccessHandler implements SyncTaskHandler {
  _SlowSuccessHandler({required this.delay});

  final Duration delay;

  @override
  Future<SyncResult> execute(SyncContext context) async {
    await Future<void>.delayed(delay);
    return SyncResult.success();
  }
}

class _CountingTask implements SyncTask {
  _CountingTask({required this.key});

  @override
  final String key;

  int executionCount = 0;

  @override
  SyncPolicy get policy => const SyncPolicy(background: true);

  @override
  List<SyncPrecondition> get preconditions => const <SyncPrecondition>[];

  @override
  SyncTaskHandler get handler => _CountingTaskHandler(this);
}

class _CountingTaskHandler implements SyncTaskHandler {
  _CountingTaskHandler(this.task);

  final _CountingTask task;

  @override
  Future<SyncResult> execute(SyncContext context) async {
    task.executionCount += 1;
    return SyncResult.success();
  }
}

class _CollectingLogger implements SyncLogger {
  final List<String> infos = <String>[];

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void info(String message) {
    infos.add(message);
  }

  @override
  void warn(String message) {}
}
