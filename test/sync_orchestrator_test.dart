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
        onRetryScheduled: ({
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
  });
}

class _FakeTask implements SyncTask {
  _FakeTask.success({required this.key})
      : _handler = _FakeTaskHandler(SyncResult.success()),
        policy = const SyncPolicy();

  _FakeTask.failure({required this.key})
      : _handler =
            _FakeTaskHandler(SyncResult.retryable(error: StateError('boom'))),
        policy = const SyncPolicy(
          retry: RetryConfig.exponential(
            initialDelay: Duration(seconds: 3),
            maxAttempts: 1,
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
