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

class UploadDataTask implements SyncTask {
  UploadDataTask({required this.api, required this.getToken});

  final ApiClient api;
  final Future<String?> Function() getToken;

  @override
  String get key => 'upload_data';

  @override
  SyncPolicy get policy => const SyncPolicy(
        appOpen: true,
        background: true,
      );

  @override
  List<SyncPrecondition> get preconditions => <SyncPrecondition>[
        const RequiresNetworkPrecondition(),
        CustomPrecondition((context) async {
          final token = await getToken();
          if (token == null) {
            return PreconditionResult.blocked(reason: 'no_auth');
          }
          return PreconditionResult.allow();
        }),
      ];

  @override
  SyncTaskHandler get handler => _UploadDataHandler(api: api);
}

class _UploadDataHandler implements SyncTaskHandler {
  _UploadDataHandler({required this.api});

  final ApiClient api;

  @override
  Future<SyncResult> execute(SyncContext context) async {
    await api.upload();
    return SyncResult.success();
  }
}

// This precondition is app-specific custom logic.
// It is not part of easy_sync.
class CustomPrecondition implements SyncPrecondition {
  CustomPrecondition(this._check);

  final Future<PreconditionResult> Function(SyncContext context) _check;

  @override
  String get name => 'custom';

  @override
  Future<PreconditionResult> check(SyncContext context) => _check(context);
}

Future<void> setupSync(ApiClient api, Future<String?> Function() getToken) async {
  final easySync = EasySync.initialize(
    tasks: <SyncTask>[
      UploadDataTask(api: api, getToken: getToken),
    ],
  );

  // Pull to refresh
  await easySync.runAll();

  // Button click for a single task
  await easySync.runTask('upload_data');
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
