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
        taskRegistrations: [
          SyncTaskRegistration(task: task),
        ],
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
