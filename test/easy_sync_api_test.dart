import 'dart:async';

import 'package:easy_sync/easy_sync.dart';
import 'package:test/test.dart';

void main() {
  group('EasySync', () {
    test('runTask executes a task manually and returns final state', () async {
      final task = _TestTask(
        key: 'manual-task',
        policy: const SyncPolicy(manual: true),
      );
      final easySync = EasySync.initialize(tasks: [task]);

      final state = await easySync.runTask('manual-task');

      expect(task.count, 1);
      expect(state.taskId, 'manual-task');
      expect(state.status, SyncTaskStatus.success);
      expect(state.lastTrigger, SyncTrigger.manual);

      await easySync.dispose();
    });

    test('runAll executes only tasks with manual policy enabled', () async {
      final allowedTask = _TestTask(
        key: 'allowed',
        policy: const SyncPolicy(manual: true),
      );
      final blockedTask = _TestTask(
        key: 'blocked',
        policy: const SyncPolicy(manual: false),
      );

      final easySync = EasySync.initialize(tasks: [allowedTask, blockedTask]);

      final states = await easySync.runAll();

      expect(allowedTask.count, 1);
      expect(blockedTask.count, 0);
      expect(states.map((state) => state.taskId), contains('allowed'));
      expect(states.map((state) => state.taskId), isNot(contains('blocked')));

      await easySync.dispose();
    });

    test('stateStream emits task state transitions', () async {
      final task = _TestTask(
        key: 'stream-task',
        policy: const SyncPolicy(manual: true),
      );
      final easySync = EasySync.initialize(tasks: [task]);

      final statuses = <SyncTaskStatus>[];
      final keys = <String>[];
      final subscription = easySync.stateStream.listen((state) {
        if (state.taskKey == 'stream-task') {
          keys.add(state.taskKey);
          statuses.add(state.status);
        }
      });

      await easySync.runTask('stream-task');
      await Future<void>.delayed(Duration.zero);

      expect(keys, contains('stream-task'));
      expect(statuses, contains(SyncTaskStatus.running));
      expect(statuses, contains(SyncTaskStatus.success));

      await subscription.cancel();
      await easySync.dispose();
    });
  });
}

class _TestTask implements SyncTask {
  _TestTask({required this.key, required this.policy});

  @override
  final String key;

  @override
  final SyncPolicy policy;

  @override
  List<SyncPrecondition> get preconditions => const <SyncPrecondition>[];

  int count = 0;

  @override
  SyncTaskHandler get handler => _TestTaskHandler(this);
}

class _TestTaskHandler implements SyncTaskHandler {
  _TestTaskHandler(this._task);

  final _TestTask _task;

  @override
  Future<SyncResult> execute(SyncContext context) async {
    _task.count += 1;
    return SyncResult.success();
  }
}
