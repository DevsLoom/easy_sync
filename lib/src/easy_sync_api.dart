import 'adapters/workmanager/workmanager_adapter.dart';
import 'core/core.dart';
import 'scheduler/app_open/app_open_sync_scheduler.dart';
import 'scheduler/background/sync_background_scheduler.dart';
import 'package:workmanager/workmanager.dart';

enum EasySyncBackgroundMode { periodic, iosBackgroundFetch }

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
  EasySyncBackgroundConfig.enabled({
    Duration frequency = EasySync.defaultBackgroundFrequency,
  }) : this._(
         isEnabled: true,
         mode: EasySyncBackgroundMode.periodic,
         uniqueName: EasySync.defaultBackgroundUniqueName,
         taskName: EasySync.defaultBackgroundTaskName,
         frequency: _normalizeFrequency(frequency),
         inputData: EasySync.defaultBackgroundInputData,
         initialDelay: null,
         stateStoreFactory: null,
         driver: EasySyncBackgroundDriver.workmanager(),
       );

  EasySyncBackgroundConfig.disabled()
    : this._(
        isEnabled: false,
        mode: EasySyncBackgroundMode.periodic,
        uniqueName: EasySync.defaultBackgroundUniqueName,
        taskName: EasySync.defaultBackgroundTaskName,
        frequency: EasySync.defaultBackgroundFrequency,
        inputData: const <String, dynamic>{},
        initialDelay: null,
        stateStoreFactory: null,
        driver: null,
      );

  EasySyncBackgroundConfig.periodic({
    required this.uniqueName,
    required Duration frequency,
    this.taskName = EasySync.defaultBackgroundTaskName,
    this.inputData = const <String, dynamic>{},
    this.initialDelay,
    this.stateStoreFactory,
    EasySyncBackgroundDriver? driver,
  }) : isEnabled = true,
       mode = EasySyncBackgroundMode.periodic,
       driver = driver ?? EasySyncBackgroundDriver.workmanager(),
       frequency = _normalizeFrequency(frequency);

  EasySyncBackgroundConfig.iosBackgroundFetch({
    this.taskName = Workmanager.iOSBackgroundTask,
    this.inputData = const <String, dynamic>{},
    this.stateStoreFactory,
    EasySyncBackgroundDriver? driver,
  }) : isEnabled = true,
       mode = EasySyncBackgroundMode.iosBackgroundFetch,
       uniqueName = EasySync.defaultBackgroundUniqueName,
       frequency = EasySync.defaultBackgroundFrequency,
       initialDelay = null,
       driver = driver ?? EasySyncBackgroundDriver.workmanager();

  const EasySyncBackgroundConfig._({
    required this.isEnabled,
    required this.mode,
    required this.uniqueName,
    required this.taskName,
    required this.frequency,
    required this.inputData,
    required this.initialDelay,
    required this.stateStoreFactory,
    required this.driver,
  });

  final bool isEnabled;
  final EasySyncBackgroundMode mode;
  final String uniqueName;
  final String taskName;
  final Duration frequency;
  final Map<String, dynamic> inputData;
  final Duration? initialDelay;
  final SyncTaskStateStoreFactory? stateStoreFactory;
  final EasySyncBackgroundDriver? driver;

  static Duration _normalizeFrequency(Duration frequency) {
    if (frequency < EasySync.minimumBackgroundFrequency) {
      return EasySync.minimumBackgroundFrequency;
    }
    return frequency;
  }
}

class EasySync {
  static const String defaultBackgroundTaskName =
      'easy_sync.background.periodic';
  static const String defaultBackgroundUniqueName =
      'easy_sync.background.periodic.default';
  static const Duration defaultBackgroundFrequency = Duration(hours: 1);
  static const Duration minimumBackgroundFrequency = Duration(minutes: 15);
  static const Map<String, dynamic> defaultBackgroundInputData =
      <String, dynamic>{'source': 'easy_sync.background.periodic'};

  static Future<EasySync> setup({
    required List<SyncTask> tasks,
    bool appOpenSync = false,
    EasySyncBackgroundConfig? background,
    Duration? taskTimeout,
    bool debugMode = false,
    bool isolateTaskFailures = true,
  }) async {
    final taskRegistrations = <SyncTaskRegistration>[
      for (final task in tasks) SyncTaskRegistration(task: task),
    ];
    final resolvedStateStore = InMemorySyncTaskStateStore();
    final engine = SyncEngine(
      taskRegistrations: taskRegistrations,
      stateStore: resolvedStateStore,
      taskTimeout: taskTimeout,
      debugMode: debugMode,
      isolateTaskFailures: isolateTaskFailures,
    );

    final appOpenScheduler = appOpenSync ? AppOpenSyncScheduler(engine) : null;
    final easySync = EasySync._internal(
      taskRegistrations: taskRegistrations,
      stateStore: resolvedStateStore,
      engine: engine,
      appOpenScheduler: appOpenScheduler,
      backgroundTaskName: background != null && background.isEnabled
          ? background.taskName
          : null,
    );

    if (appOpenScheduler != null) {
      await appOpenScheduler.start();
    }

    if (background != null && background.isEnabled) {
      final driver = background.driver!;

      WorkmanagerSyncBridge.registerTaskMapping(
        taskName: background.taskName,
        taskRegistrations: taskRegistrations,
        stateStoreFactory:
            background.stateStoreFactory ?? InMemorySyncTaskStateStore.new,
        taskTimeout: taskTimeout,
        debugMode: debugMode,
        isolateTaskFailures: isolateTaskFailures,
      );

      await driver.initialize();
      if (background.mode == EasySyncBackgroundMode.periodic) {
        await driver.scheduler.schedulePeriodic(
          uniqueName: background.uniqueName,
          taskName: background.taskName,
          frequency: background.frequency,
          inputData: background.inputData,
          initialDelay: background.initialDelay,
        );
      }
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
