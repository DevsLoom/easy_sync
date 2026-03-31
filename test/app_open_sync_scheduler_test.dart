import 'dart:async';

import 'package:easy_sync/easy_sync.dart';
import 'package:flutter/widgets.dart';
import 'package:test/test.dart';

void main() {
  group('AppOpenSyncScheduler', () {
    test('runs app-open sync at start and on resume', () async {
      final appOpenAllowed = _CountingTask(
        key: 'allowed',
        policy: const SyncPolicy(appOpen: true),
      );
      final appOpenBlocked = _CountingTask(
        key: 'blocked',
        policy: const SyncPolicy(appOpen: false),
      );

      WidgetsBindingObserver? observer;
      final scheduler = AppOpenSyncScheduler(
        SyncOrchestrator(
          taskRegistrations: [
            SyncTaskRegistration(task: appOpenAllowed),
            SyncTaskRegistration(task: appOpenBlocked),
          ],
          stateStore: InMemorySyncTaskStateStore(),
        ),
        addObserver: (value) => observer = value,
        removeObserver: (_) => observer = null,
      );

      await scheduler.start();

      expect(appOpenAllowed.count, 1);
      expect(appOpenBlocked.count, 0);
      expect(observer, isNotNull);

      observer!.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(appOpenAllowed.count, 2);
      expect(appOpenBlocked.count, 0);
    });

    test('does not run on lifecycle changes after stop', () async {
      final task = _CountingTask(
        key: 'allowed',
        policy: const SyncPolicy(appOpen: true),
      );

      WidgetsBindingObserver? observer;
      final scheduler = AppOpenSyncScheduler(
        SyncOrchestrator(
          taskRegistrations: [
            SyncTaskRegistration(task: task),
          ],
          stateStore: InMemorySyncTaskStateStore(),
        ),
        addObserver: (value) => observer = value,
        removeObserver: (_) => observer = null,
      );

      await scheduler.start();
      scheduler.stop();

      final removedObserver = observer;
      expect(removedObserver, isNull);

      scheduler.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(task.count, 1);
    });

    test('start is idempotent', () async {
      final task = _CountingTask(
        key: 'allowed',
        policy: const SyncPolicy(appOpen: true),
      );

      var addObserverCalls = 0;
      final scheduler = AppOpenSyncScheduler(
        SyncOrchestrator(
          taskRegistrations: [
            SyncTaskRegistration(task: task),
          ],
          stateStore: InMemorySyncTaskStateStore(),
        ),
        addObserver: (_) => addObserverCalls += 1,
        removeObserver: (_) {},
      );

      await scheduler.start();
      await scheduler.start();

      expect(addObserverCalls, 1);
      expect(task.count, 1);
    });
  });
}

class _CountingTask implements SyncTask {
  _CountingTask({
    required this.key,
    required this.policy,
  });

  @override
  final String key;

  @override
  final SyncPolicy policy;

  @override
  List<SyncPrecondition> get preconditions => const <SyncPrecondition>[];

  int count = 0;

  @override
  SyncTaskHandler get handler => _CountingHandler(this);
}

class _CountingHandler implements SyncTaskHandler {
  _CountingHandler(this._task);

  final _CountingTask _task;

  @override
  Future<SyncResult> execute(SyncContext context) async {
    _task.count += 1;
    return SyncResult.success();
  }
}
