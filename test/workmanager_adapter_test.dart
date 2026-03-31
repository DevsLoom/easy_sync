import 'package:easy_sync/easy_sync.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    WorkmanagerSyncBridge.clearTaskMappings();
  });

  group('WorkmanagerSyncBridge', () {
    test('executes only background-enabled mapped tasks', () async {
      final backgroundTask = _CountingTask(
        key: 'bg-enabled',
        policy: const SyncPolicy(background: true),
      );
      final nonBackgroundTask = _CountingTask(
        key: 'bg-disabled',
        policy: const SyncPolicy(background: false),
      );

      WorkmanagerSyncBridge.registerTaskMapping(
        taskName: 'sync-background',
        taskRegistrations: [
          SyncTaskRegistration(task: backgroundTask),
          SyncTaskRegistration(task: nonBackgroundTask),
        ],
        stateStoreFactory: InMemorySyncTaskStateStore.new,
      );

      final ok = await WorkmanagerSyncBridge.executeTask(
        'sync-background',
        <String, dynamic>{'source': 'periodic'},
      );

      expect(ok, isTrue);
      expect(backgroundTask.executionCount, 1);
      expect(nonBackgroundTask.executionCount, 0);
    });

    test('returns false when no mapping exists for task name', () async {
      final ok = await WorkmanagerSyncBridge.executeTask('unknown-task', null);
      expect(ok, isFalse);
    });

    test('returns false when isolate-safe execution throws', () async {
      final task = _CountingTask(
        key: 'bg-enabled',
        policy: const SyncPolicy(background: true),
      );

      WorkmanagerSyncBridge.registerTaskMapping(
        taskName: 'sync-background',
        taskRegistrations: [SyncTaskRegistration(task: task)],
        stateStoreFactory: () {
          throw StateError('cannot build state store');
        },
      );

      final ok = await WorkmanagerSyncBridge.executeTask(
        'sync-background',
        null,
      );

      expect(ok, isFalse);
      expect(task.executionCount, 0);
    });

    test(
      'isolates crashing task and still runs remaining background tasks',
      () async {
        final healthyTask = _CountingTask(
          key: 'healthy-bg-task',
          policy: const SyncPolicy(background: true),
        );

        WorkmanagerSyncBridge.registerTaskMapping(
          taskName: 'sync-background',
          taskRegistrations: [
            SyncTaskRegistration(
              task: _CountingTask(
                key: 'crashing-bg-task',
                policy: const SyncPolicy(background: true),
              ),
              preconditions: [
                PredicatePrecondition(
                  name: 'crashing-precondition',
                  predicate: (_) async => throw StateError('boom'),
                ),
              ],
            ),
            SyncTaskRegistration(task: healthyTask),
          ],
          stateStoreFactory: InMemorySyncTaskStateStore.new,
        );

        final ok = await WorkmanagerSyncBridge.executeTask(
          'sync-background',
          <String, dynamic>{'source': 'periodic'},
        );

        expect(ok, isTrue);
        expect(healthyTask.executionCount, 1);
      },
    );

    test('applies mapped rate limit to background task execution', () async {
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final task = _CountingTask(
        key: 'limited-bg-task',
        policy: const SyncPolicy(background: true),
      );

      WorkmanagerSyncBridge.registerTaskMapping(
        taskName: 'sync-background',
        taskRegistrations: [SyncTaskRegistration(task: task)],
        stateStoreFactory: InMemorySyncTaskStateStore.new,
        rateLimit: const SyncRateLimit.slidingWindow(
          maxExecutions: 1,
          per: Duration(minutes: 1),
        ),
        clock: () => now,
      );

      final first = await WorkmanagerSyncBridge.executeTask(
        'sync-background',
        const <String, dynamic>{'source': 'periodic'},
      );
      final second = await WorkmanagerSyncBridge.executeTask(
        'sync-background',
        const <String, dynamic>{'source': 'periodic'},
      );

      expect(first, isTrue);
      expect(second, isTrue);
      expect(task.executionCount, 1);

      now = now.add(const Duration(minutes: 2));
      await WorkmanagerSyncBridge.executeTask(
        'sync-background',
        const <String, dynamic>{'source': 'periodic'},
      );

      expect(task.executionCount, 2);
    });

    test(
      'applies mapped circuit breaker to background task execution',
      () async {
        var now = DateTime(2026, 1, 1, 10, 0, 0);
        final failingTask = _AlwaysFailTask(
          key: 'failing-bg-task',
          policy: const SyncPolicy(background: true),
        );

        WorkmanagerSyncBridge.registerTaskMapping(
          taskName: 'sync-background',
          taskRegistrations: [SyncTaskRegistration(task: failingTask)],
          stateStoreFactory: InMemorySyncTaskStateStore.new,
          circuitBreaker: const SyncCircuitBreaker.standard(
            failureThreshold: 2,
            openFor: Duration(minutes: 5),
          ),
          clock: () => now,
        );

        await WorkmanagerSyncBridge.executeTask('sync-background', null);
        await WorkmanagerSyncBridge.executeTask('sync-background', null);
        await WorkmanagerSyncBridge.executeTask('sync-background', null);

        expect(failingTask.executionCount, 2);

        now = now.add(const Duration(minutes: 6));
        await WorkmanagerSyncBridge.executeTask('sync-background', null);

        expect(failingTask.executionCount, 3);
      },
    );
  });
}

class _CountingTask implements SyncTask {
  _CountingTask({required this.key, required this.policy});

  @override
  final String key;

  @override
  final SyncPolicy policy;

  int executionCount = 0;

  @override
  List<SyncPrecondition> get preconditions => const <SyncPrecondition>[];

  @override
  SyncTaskHandler get handler => _CountingTaskHandler(this);
}

class _CountingTaskHandler implements SyncTaskHandler {
  _CountingTaskHandler(this._task);

  final _CountingTask _task;

  @override
  Future<SyncResult> execute(SyncContext context) async {
    _task.executionCount += 1;
    return SyncResult.success();
  }
}

class _AlwaysFailTask implements SyncTask {
  _AlwaysFailTask({required this.key, required this.policy});

  @override
  final String key;

  @override
  final SyncPolicy policy;

  int executionCount = 0;

  @override
  List<SyncPrecondition> get preconditions => const <SyncPrecondition>[];

  @override
  SyncTaskHandler get handler => _AlwaysFailTaskHandler(this);
}

class _AlwaysFailTaskHandler implements SyncTaskHandler {
  _AlwaysFailTaskHandler(this._task);

  final _AlwaysFailTask _task;

  @override
  Future<SyncResult> execute(SyncContext context) async {
    _task.executionCount += 1;
    return SyncResult.failure(error: StateError('backend unavailable'));
  }
}
