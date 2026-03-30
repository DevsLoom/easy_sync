import 'package:easy_sync/easy_sync.dart';
import 'package:test/test.dart';

void main() {
  group('SyncOrchestrator', () {
    test('runs task successfully and resets attempts', () async {
      final store = InMemorySyncTaskStateStore();
      final orchestrator = SyncOrchestrator(
        taskRegistrations: [
          SyncTaskRegistration(task: _FakeTask.success(id: 'a')),
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
            task: _FakeTask.success(id: 'a'),
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
          SyncTaskRegistration(task: _FakeTask.failure(id: 'a')),
        ],
        stateStore: store,
        retryPolicy: const ExponentialBackoffRetryPolicy(
          initialDelay: Duration(seconds: 3),
          maxAttempts: 1,
        ),
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
      expect(state.status, SyncTaskStatus.waitingRetry);
      expect(state.attempt, 1);
      expect(scheduled['a'], const Duration(seconds: 3));
      expect(state.nextRetryAt, isNotNull);
    });
  });
}

class _FakeTask implements SyncTask {
  _FakeTask.success({required this.id}) : _result = SyncTaskResult.success();

  _FakeTask.failure({required this.id})
    : _result = SyncTaskResult.failure(error: StateError('boom'));

  @override
  final String id;

  final SyncTaskResult _result;

  @override
  String get description => 'Fake $id';

  @override
  Future<SyncTaskResult> run(SyncContext context) async => _result;
}
