import 'package:workmanager/workmanager.dart';

import '../../scheduler/background_scheduler.dart';

typedef WorkmanagerSyncHandler =
    Future<void> Function(String taskName, Map<String, dynamic>? inputData);

class WorkmanagerSyncBridge {
  static WorkmanagerSyncHandler? _handler;

  static void setHandler(WorkmanagerSyncHandler handler) {
    _handler = handler;
  }

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((taskName, inputData) async {
      final handler = _handler;
      if (handler == null) {
        return false;
      }

      await handler(taskName, inputData);
      return true;
    });
  }
}

class WorkmanagerBackgroundScheduler implements SyncBackgroundScheduler {
  WorkmanagerBackgroundScheduler({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  Future<void> initialize({bool isInDebugMode = false}) {
    return _workmanager.initialize(
      WorkmanagerSyncBridge.callbackDispatcher,
      isInDebugMode: isInDebugMode,
    );
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
