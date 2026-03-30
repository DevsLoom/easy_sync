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
      expect(state.status, SyncTaskStatus.succeeded);
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
      expect(state.status, SyncTaskStatus.skipped);
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
      expect(state.status, SyncTaskStatus.waitingRetry);
      expect(state.attempt, 1);
      expect(scheduled['a'], const Duration(seconds: 3));
      expect(state.nextRetryAt, isNotNull);
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
