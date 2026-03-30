# easy_sync

`easy_sync` is a production-ready, backend-agnostic Flutter package for sync orchestration.

It provides a clean architecture for:
- App open sync
- Manual sync
- Background sync (via Workmanager adapter)
- Retry with backoff
- Task state tracking
- Generic preconditions (network, auth, custom logic)

## Non-goals

This package intentionally does **not** include:
- API client logic
- Authentication implementation
- Token storage
- App business logic

You define these in your app and provide them through interfaces.

## Architecture

```text
lib/
  easy_sync.dart
  src/
    core/
      - models and contracts
      - retry policies
      - precondition abstractions
      - state store interfaces
    scheduler/
      - sync orchestration engine
      - task registration
      - background scheduler interface
    adapters/
      workmanager/
        - Workmanager bridge and scheduler adapter
```

## Quick start

```dart
import 'package:easy_sync/easy_sync.dart';

class UploadTask implements SyncTask {
  @override
  String get id => 'upload';

  @override
  String get description => 'Upload pending records';

  @override
  Future<SyncTaskResult> run(SyncContext context) async {
    // Your app logic goes here.
    return SyncTaskResult.success();
  }
}

Future<void> main() async {
  final orchestrator = SyncOrchestrator(
    taskRegistrations: [
      SyncTaskRegistration(
        task: UploadTask(),
        preconditions: [
          PredicatePrecondition(
            name: 'network',
            predicate: (_) async => true,
          ),
          PredicatePrecondition(
            name: 'user-authenticated',
            predicate: (_) async => true,
          ),
        ],
      ),
    ],
    stateStore: InMemorySyncTaskStateStore(),
    retryPolicy: const ExponentialBackoffRetryPolicy(),
  );

  await orchestrator.syncOnAppOpen();
  await orchestrator.syncManually();
}
```

## Background sync with Workmanager

```dart
final scheduler = WorkmanagerBackgroundScheduler();

WorkmanagerSyncBridge.setHandler((taskName, inputData) async {
  // Map background task to orchestrator invocation.
  // Example: await orchestrator.syncInBackground(metadata: {'task': taskName});
});

await scheduler.initialize();

await scheduler.schedulePeriodic(
  uniqueName: 'periodic-sync',
  taskName: 'sync-all',
  frequency: const Duration(hours: 1),
);
```

## Testing strategy

- Unit test task logic independently.
- Unit test custom preconditions separately.
- Unit test orchestration by injecting fake tasks and fake state stores.
- Keep adapter tests focused on translation between interfaces.
