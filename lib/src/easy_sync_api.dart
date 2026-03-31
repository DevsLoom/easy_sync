import 'core/core.dart';

class EasySync {
  factory EasySync.initialize({
    required List<SyncTask> tasks,
    SyncTaskStateStore? stateStore,
    List<SyncPrecondition> globalPreconditions = const <SyncPrecondition>[],
    SyncLogger logger = const NoopSyncLogger(),
    RetryScheduleCallback? onRetryScheduled,
    DateTime Function()? clock,
  }) {
    return EasySync(
      taskRegistrations: <SyncTaskRegistration>[
        for (final task in tasks) SyncTaskRegistration(task: task),
      ],
      stateStore: stateStore ?? InMemorySyncTaskStateStore(),
      globalPreconditions: globalPreconditions,
      logger: logger,
      onRetryScheduled: onRetryScheduled,
      clock: clock,
    );
  }

  EasySync({
    required List<SyncTaskRegistration> taskRegistrations,
    required SyncTaskStateStore stateStore,
    List<SyncPrecondition> globalPreconditions = const <SyncPrecondition>[],
    SyncLogger logger = const NoopSyncLogger(),
    RetryScheduleCallback? onRetryScheduled,
    DateTime Function()? clock,
  }) : _stateStore = stateStore,
       _taskRegistrations = taskRegistrations,
       _engine = SyncEngine(
         taskRegistrations: taskRegistrations,
         stateStore: stateStore,
         globalPreconditions: globalPreconditions,
         logger: logger,
         onRetryScheduled: onRetryScheduled,
         clock: clock,
       );

  final SyncTaskStateStore _stateStore;
  final List<SyncTaskRegistration> _taskRegistrations;
  final SyncEngine _engine;

  Stream<SyncTaskState> get stateUpdates => _engine.stateUpdates;

  Future<SyncTaskState> runTask(
    String taskKey, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    await _engine.runTask(
      taskKey,
      policyType: SyncPolicyType.manual,
      metadata: metadata,
    );

    return _stateStore.getOrCreate(taskKey);
  }

  Future<List<SyncTaskState>> runAll({
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    await _engine.runAll(SyncPolicyType.manual, metadata: metadata);
    final states = await _engine.states();
    final manualTaskKeys = _taskRegistrations
        .where(
          (registration) => registration.task.policy.allows(SyncTrigger.manual),
        )
        .map((registration) => registration.task.key)
        .toSet();

    return states
        .where((state) => manualTaskKeys.contains(state.taskId))
        .toList();
  }

  Future<void> dispose() => _engine.dispose();
}
