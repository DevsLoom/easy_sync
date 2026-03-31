import 'package:workmanager/workmanager.dart';

import '../../core/core.dart';
import '../../scheduler/background/sync_background_scheduler.dart';

typedef WorkmanagerSyncHandler =
    Future<void> Function(String taskName, Map<String, dynamic>? inputData);

typedef SyncTaskStateStoreFactory = SyncTaskStateStore Function();

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask(WorkmanagerSyncBridge.executeTask);
}

class WorkmanagerSyncBridge {
  static WorkmanagerSyncHandler? _handler;
  static final Map<String, _WorkmanagerTaskBinding> _taskBindings =
      <String, _WorkmanagerTaskBinding>{};

  @Deprecated('Use registerTaskMapping to execute SyncEngine internally.')
  static void setHandler(WorkmanagerSyncHandler handler) {
    _handler = handler;
  }

  static void registerTaskMapping({
    required String taskName,
    required List<SyncTaskRegistration> taskRegistrations,
    required SyncTaskStateStoreFactory stateStoreFactory,
    List<SyncPrecondition> globalPreconditions = const <SyncPrecondition>[],
    SyncLogger logger = const NoopSyncLogger(),
    RetryScheduleCallback? onRetryScheduled,
    Duration? taskTimeout,
    bool debugMode = false,
    bool isolateTaskFailures = true,
    SyncRateLimit rateLimit = const SyncRateLimit.disabled(),
    SyncCircuitBreaker circuitBreaker = const SyncCircuitBreaker.disabled(),
    DateTime Function()? clock,
  }) {
    _taskBindings[taskName] = _WorkmanagerTaskBinding(
      taskRegistrations: taskRegistrations,
      stateStoreFactory: stateStoreFactory,
      globalPreconditions: globalPreconditions,
      logger: logger,
      onRetryScheduled: onRetryScheduled,
      taskTimeout: taskTimeout,
      debugMode: debugMode,
      isolateTaskFailures: isolateTaskFailures,
      rateLimit: rateLimit,
      circuitBreaker: circuitBreaker,
      clock: clock,
    );
  }

  static void unregisterTaskMapping(String taskName) {
    _taskBindings.remove(taskName);
  }

  static void clearTaskMappings() {
    _taskBindings.clear();
  }

  static Future<bool> executeTask(
    String taskName,
    Map<String, dynamic>? inputData,
  ) async {
    try {
      final handler = _handler;
      if (handler != null) {
        await handler(taskName, inputData);
        return true;
      }

      final binding = _taskBindings[taskName];
      if (binding == null) {
        return false;
      }

      final engine = SyncEngine(
        taskRegistrations: binding.taskRegistrations,
        stateStore: binding.stateStoreFactory(),
        globalPreconditions: binding.globalPreconditions,
        logger: binding.logger,
        onRetryScheduled: binding.onRetryScheduled,
        taskTimeout: binding.taskTimeout,
        debugMode: binding.debugMode,
        isolateTaskFailures: binding.isolateTaskFailures,
        rateLimit: binding.rateLimit,
        circuitBreaker: binding.circuitBreaker,
        executionHistory: binding.executionHistory,
        consecutiveFailures: binding.consecutiveFailures,
        openCircuits: binding.openCircuits,
        clock: binding.clock,
      );

      try {
        await engine.runAll(
          SyncPolicyType.background,
          metadata: _metadataFromInputData(inputData),
        );
      } finally {
        await engine.dispose();
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, Object?> _metadataFromInputData(
    Map<String, dynamic>? inputData,
  ) {
    if (inputData == null) {
      return const <String, Object?>{};
    }

    return <String, Object?>{
      for (final entry in inputData.entries) entry.key: entry.value,
    };
  }
}

class WorkmanagerBackgroundScheduler implements SyncBackgroundScheduler {
  WorkmanagerBackgroundScheduler({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  Future<void> initialize({
    @Deprecated(
      'No longer used by workmanager. Configure debug handlers via workmanager APIs.',
    )
    bool isInDebugMode = false,
  }) {
    return _workmanager.initialize(backgroundDispatcher);
  }

  /// Android-only helper from workmanager.
  ///
  /// Returns `null` when the underlying platform does not support this API.
  Future<bool?> isScheduledByUniqueName(String uniqueName) async {
    try {
      return await _workmanager.isScheduledByUniqueName(uniqueName);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancelAll() {
    return _workmanager.cancelAll();
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) {
    return _workmanager.cancelByUniqueName(uniqueName);
  }

  @override
  Future<void> scheduleOneOff({
    required String uniqueName,
    required String taskName,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  }) {
    final delay = initialDelay ?? Duration.zero;
    return _workmanager.registerOneOffTask(
      uniqueName,
      taskName,
      inputData: inputData,
      initialDelay: delay,
    );
  }

  @override
  Future<void> schedulePeriodic({
    required String uniqueName,
    required String taskName,
    required Duration frequency,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
  }) {
    final delay = initialDelay ?? Duration.zero;
    return _workmanager.registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: frequency,
      inputData: inputData,
      initialDelay: delay,
    );
  }
}

class _WorkmanagerTaskBinding {
  _WorkmanagerTaskBinding({
    required this.taskRegistrations,
    required this.stateStoreFactory,
    required this.globalPreconditions,
    required this.logger,
    required this.onRetryScheduled,
    required this.taskTimeout,
    required this.debugMode,
    required this.isolateTaskFailures,
    required this.rateLimit,
    required this.circuitBreaker,
    required this.clock,
  });

  final List<SyncTaskRegistration> taskRegistrations;
  final SyncTaskStateStoreFactory stateStoreFactory;
  final List<SyncPrecondition> globalPreconditions;
  final SyncLogger logger;
  final RetryScheduleCallback? onRetryScheduled;
  final Duration? taskTimeout;
  final bool debugMode;
  final bool isolateTaskFailures;
  final SyncRateLimit rateLimit;
  final SyncCircuitBreaker circuitBreaker;
  final Map<String, List<DateTime>> executionHistory =
      <String, List<DateTime>>{};
  final Map<String, int> consecutiveFailures = <String, int>{};
  final Map<String, DateTime?> openCircuits = <String, DateTime?>{};
  final DateTime Function()? clock;
}
