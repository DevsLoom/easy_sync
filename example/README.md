# easy_sync Example Guide

This example guide shows one practical setup pattern for apps using easy_sync.

A minimal runnable snippet is also available at `example/main.dart`.

## Scenario

- Manual sync from pull-to-refresh.
- App-open sync when user returns to the app.
- Periodic background sync using workmanager.

## Example Setup Outline

1. Define tasks implementing SyncTask.
2. Add app-owned preconditions (auth, feature flags, local state checks).
3. Create EasySync for manual triggers.
4. Register WorkmanagerSyncBridge mapping for background triggers.
5. Schedule periodic task with WorkmanagerBackgroundScheduler.

## Minimal Example Skeleton

```dart
import 'package:easy_sync/easy_sync.dart';

Future<void> bootstrapSync(List<SyncTask> tasks) async {
  final easySync = EasySync.initialize(
    tasks: tasks,
    taskTimeout: const Duration(seconds: 20),
    isolateTaskFailures: true,
  );

  // Manual trigger (for example, refresh button)
  await easySync.runAll(
    metadata: const <String, Object?>{
      'source': 'manual',
      'hasNetwork': true,
    },
  );

  final registrations = <SyncTaskRegistration>[
    for (final task in tasks) SyncTaskRegistration(task: task),
  ];

  WorkmanagerSyncBridge.registerTaskMapping(
    taskName: 'sync-background',
    taskRegistrations: registrations,
    stateStoreFactory: InMemorySyncTaskStateStore.new,
  );

  final scheduler = WorkmanagerBackgroundScheduler();
  await scheduler.initialize();
  await scheduler.schedulePeriodic(
    uniqueName: 'easy-sync-periodic',
    taskName: 'sync-background',
    frequency: const Duration(hours: 1),
  );
}
```

## Important Notes

- Provide native platform workmanager configuration before relying on background execution.
- iOS background timing is best-effort and not guaranteed.
- Keep task handlers idempotent and retry-aware.
