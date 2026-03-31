import 'adapters/workmanager/workmanager_adapter.dart';
import 'core/core.dart';
import 'scheduler/app_open/app_open_sync_scheduler.dart';
import 'scheduler/background/sync_background_scheduler.dart';

class EasySyncBackgroundDriver {
  EasySyncBackgroundDriver({required this.scheduler, required this.initialize});

  factory EasySyncBackgroundDriver.workmanager({
    WorkmanagerBackgroundScheduler? scheduler,
  }) {
    final resolvedScheduler = scheduler ?? WorkmanagerBackgroundScheduler();

    return EasySyncBackgroundDriver(
      scheduler: resolvedScheduler,
      initialize: resolvedScheduler.initialize,
    );
  }

  final SyncBackgroundScheduler scheduler;
  final Future<void> Function() initialize;
}

class EasySyncBackgroundConfig {
  EasySyncBackgroundConfig.periodic({
    required this.uniqueName,
    required this.frequency,
    this.taskName = EasySync.defaultBackgroundTaskName,
    this.inputData = const <String, dynamic>{},
    this.initialDelay,
    this.stateStoreFactory,
    EasySyncBackgroundDriver? driver,
  }) : driver = driver ?? EasySyncBackgroundDriver.workmanager();

  final String uniqueName;
  final String taskName;
  final Duration frequency;
  final Map<String, dynamic> inputData;
  final Duration? initialDelay;
  final SyncTaskStateStoreFactory? stateStoreFactory;
  final EasySyncBackgroundDriver driver;
}

class EasySync {
  static const String defaultBackgroundTaskName =
      'easy_sync.background.periodic';

  static Future<EasySync> setup({
    required List<SyncTask> tasks,
    bool appOpenSync = false,
    EasySyncBackgroundConfig? background,
    SyncTaskStateStore? stateStore,
    List<SyncPrecondition> globalPreconditions = const <SyncPrecondition>[],
    SyncLogger logger = const NoopSyncLogger(),
    RetryScheduleCallback? onRetryScheduled,
    Duration? taskTimeout,
    bool debugMode = false,
    bool isolateTaskFailures = true,
    DateTime Function()? clock,
  }) async {
    final taskRegistrations = <SyncTaskRegistration>[
      for (final task in tasks) SyncTaskRegistration(task: task),
    ];
    final resolvedStateStore = stateStore ?? InMemorySyncTaskStateStore();
    final engine = SyncEngine(
      taskRegistrations: taskRegistrations,
      stateStore: resolvedStateStore,
      globalPreconditions: globalPreconditions,
      logger: logger,
      onRetryScheduled: onRetryScheduled,
      taskTimeout: taskTimeout,
      debugMode: debugMode,
      isolateTaskFailures: isolateTaskFailures,
      clock: clock,
    );

    final appOpenScheduler = appOpenSync ? AppOpenSyncScheduler(engine) : null;
    final easySync = EasySync._internal(
      taskRegistrations: taskRegistrations,
      stateStore: resolvedStateStore,
      engine: engine,
      appOpenScheduler: appOpenScheduler,
      backgroundTaskName: background?.taskName,
    );

    if (appOpenScheduler != null) {
      await appOpenScheduler.start();
    }

    if (background != null) {
      WorkmanagerSyncBridge.registerTaskMapping(
        taskName: background.taskName,
        taskRegistrations: taskRegistrations,
        stateStoreFactory:
            background.stateStoreFactory ?? InMemorySyncTaskStateStore.new,
        globalPreconditions: globalPreconditions,
        logger: logger,
        onRetryScheduled: onRetryScheduled,
        taskTimeout: taskTimeout,
        debugMode: debugMode,
        isolateTaskFailures: isolateTaskFailures,
        clock: clock,
      );

      await background.driver.initialize();
      await background.driver.scheduler.schedulePeriodic(
        uniqueName: background.uniqueName,
        taskName: background.taskName,
        frequency: background.frequency,
        inputData: background.inputData,
        initialDelay: background.initialDelay,
      );
    }

    return easySync;
  }

  factory EasySync.initialize({
    required List<SyncTask> tasks,
    SyncTaskStateStore? stateStore,
    List<SyncPrecondition> globalPreconditions = const <SyncPrecondition>[],
    SyncLogger logger = const NoopSyncLogger(),
    RetryScheduleCallback? onRetryScheduled,
    Duration? taskTimeout,
    bool debugMode = false,
    bool isolateTaskFailures = true,
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
      taskTimeout: taskTimeout,
      debugMode: debugMode,
      isolateTaskFailures: isolateTaskFailures,
      clock: clock,
    );
  }

  EasySync({
    required List<SyncTaskRegistration> taskRegistrations,
    required SyncTaskStateStore stateStore,
    List<SyncPrecondition> globalPreconditions = const <SyncPrecondition>[],
    SyncLogger logger = const NoopSyncLogger(),
    RetryScheduleCallback? onRetryScheduled,
    Duration? taskTimeout,
    bool debugMode = false,
    bool isolateTaskFailures = true,
    DateTime Function()? clock,
  }) : _stateStore = stateStore,
       _taskRegistrations = taskRegistrations,
       _engine = SyncEngine(
         taskRegistrations: taskRegistrations,
         stateStore: stateStore,
         globalPreconditions: globalPreconditions,
         logger: logger,
         onRetryScheduled: onRetryScheduled,
         taskTimeout: taskTimeout,
         debugMode: debugMode,
         isolateTaskFailures: isolateTaskFailures,
         clock: clock,
       ),
       _appOpenScheduler = null,
       _backgroundTaskName = null;

  EasySync._internal({
    required List<SyncTaskRegistration> taskRegistrations,
    required SyncTaskStateStore stateStore,
    required SyncEngine engine,
    AppOpenSyncScheduler? appOpenScheduler,
    String? backgroundTaskName,
  }) : _stateStore = stateStore,
       _taskRegistrations = taskRegistrations,
       _engine = engine,
       _appOpenScheduler = appOpenScheduler,
       _backgroundTaskName = backgroundTaskName;

  final SyncTaskStateStore _stateStore;
  final List<SyncTaskRegistration> _taskRegistrations;
  final SyncEngine _engine;
  final AppOpenSyncScheduler? _appOpenScheduler;
  final String? _backgroundTaskName;

  Stream<SyncTaskState> get stateStream => _engine.stateUpdates;

  @Deprecated('Use stateStream instead.')
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

  Future<void> dispose() async {
    _appOpenScheduler?.stop();

    final backgroundTaskName = _backgroundTaskName;
    if (backgroundTaskName != null) {
      WorkmanagerSyncBridge.unregisterTaskMapping(backgroundTaskName);
    }

    await _engine.dispose();
  }
}
