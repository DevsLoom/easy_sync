import 'dart:async';

import 'package:easy_sync/easy_sync.dart';
import 'package:flutter/widgets.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    WorkmanagerSyncBridge.clearTaskMappings();
  });

  group('EasySync', () {
    test('SyncTask.fn executes without a custom task class', () async {
      var count = 0;
      final easySync = EasySync.initialize(
        tasks: [
          SyncTask.fn(
            key: 'fn-task',
            manual: true,
            appOpen: false,
            background: false,
            run: (context) async {
              expect(context.value<String>('source'), 'manual');
              count += 1;
            },
          ),
        ],
      );

      final state = await easySync.runTask(
        'fn-task',
        metadata: const <String, Object?>{'source': 'manual'},
      );

      expect(count, 1);
      expect(state.status, SyncTaskStatus.success);

      await easySync.dispose();
    });

    test('SyncTask.fn keeps policy and preconditions configurable', () async {
      final precondition = PredicatePrecondition(
        name: 'has-token',
        predicate: (context) async => context.value<bool>('ready') ?? false,
      );
      final task = SyncTask.fn(
        key: 'fn-configurable',
        manual: true,
        appOpen: false,
        background: false,
        preconditions: [precondition],
        run: (_) async {},
      );

      expect(task.policy.manual, isTrue);
      expect(task.policy.appOpen, isFalse);
      expect(task.policy.background, isFalse);
      expect(task.preconditions, hasLength(1));
      expect(task.preconditions.single.name, 'has-token');
    });

    test('SyncTask.fn can map thrown errors to retryable results', () async {
      final result = await SyncTask.fn(
        key: 'fn-retryable',
        run: (_) async {
          throw StateError('temporary');
        },
        retryWhen: (error, stackTrace) => error is StateError,
      ).handler.execute(const SyncContext());

      expect(result.retryable, isTrue);
      expect(result.failure, isTrue);
      expect(result.success, isFalse);
    });

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

    test('setup configures app-open sync and periodic background', () async {
      WidgetsFlutterBinding.ensureInitialized();

      final task = _TestTask(
        key: 'setup-task',
        policy: const SyncPolicy(appOpen: true, manual: true, background: true),
      );
      final backgroundScheduler = _FakeBackgroundScheduler();

      final easySync = await EasySync.setup(
        tasks: [task],
        appOpenSync: true,
        background: EasySyncBackgroundConfig.periodic(
          uniqueName: EasySync.defaultBackgroundUniqueName,
          taskName: EasySync.defaultBackgroundTaskName,
          frequency: const Duration(hours: 1),
          driver: EasySyncBackgroundDriver(
            scheduler: backgroundScheduler,
            initialize: backgroundScheduler.initialize,
          ),
        ),
        debugMode: false,
      );

      expect(task.count, 1);
      final ok = await WorkmanagerSyncBridge.executeTask(
        EasySync.defaultBackgroundTaskName,
        const <String, dynamic>{'source': 'periodic'},
      );

      expect(ok, isTrue);
      expect(task.count, 2);

      await easySync.dispose();

      final missing = await WorkmanagerSyncBridge.executeTask(
        EasySync.defaultBackgroundTaskName,
        null,
      );
      expect(missing, isFalse);
    });

    test('disabled background skips automatic background setup', () async {
      WidgetsFlutterBinding.ensureInitialized();

      final easySync = await EasySync.setup(
        tasks: [
          _TestTask(
            key: 'disabled-background-task',
            policy: const SyncPolicy(background: true),
          ),
        ],
        background: EasySyncBackgroundConfig.disabled(),
      );

      final ok = await WorkmanagerSyncBridge.executeTask(
        EasySync.defaultBackgroundTaskName,
        null,
      );

      expect(ok, isFalse);

      await easySync.dispose();
    });

    test(
      'enabled background normalizes frequency to workmanager minimum',
      () async {
        final config = EasySyncBackgroundConfig.enabled(
          frequency: const Duration(minutes: 5),
        );

        expect(config.frequency, EasySync.minimumBackgroundFrequency);
      },
    );

    test(
      'advanced periodic config still allows custom scheduling values',
      () async {
        WidgetsFlutterBinding.ensureInitialized();

        final backgroundScheduler = _FakeBackgroundScheduler();

        final easySync = await EasySync.setup(
          tasks: [
            _TestTask(
              key: 'advanced-background-task',
              policy: const SyncPolicy(background: true),
            ),
          ],
          background: EasySyncBackgroundConfig.periodic(
            uniqueName: 'custom-unique',
            taskName: 'custom-task',
            frequency: const Duration(hours: 2),
            inputData: const <String, dynamic>{'source': 'advanced'},
            driver: EasySyncBackgroundDriver(
              scheduler: backgroundScheduler,
              initialize: backgroundScheduler.initialize,
            ),
          ),
        );

        expect(backgroundScheduler.initializeCount, 1);
        expect(backgroundScheduler.scheduledUniqueName, 'custom-unique');
        expect(backgroundScheduler.scheduledTaskName, 'custom-task');
        expect(
          backgroundScheduler.scheduledFrequency,
          const Duration(hours: 2),
        );

        await easySync.dispose();
      },
    );
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

class _FakeBackgroundScheduler implements SyncBackgroundScheduler {
  int initializeCount = 0;
  String? scheduledUniqueName;
  String? scheduledTaskName;
  Duration? scheduledFrequency;

  Future<void> initialize() async {
    initializeCount += 1;
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {}

  @override
  Future<void> scheduleOneOff({
    required String uniqueName,
    required String taskName,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  }) async {}

  @override
  Future<void> schedulePeriodic({
    required String uniqueName,
    required String taskName,
    required Duration frequency,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  }) async {
    scheduledUniqueName = uniqueName;
    scheduledTaskName = taskName;
    scheduledFrequency = frequency;
  }
}
