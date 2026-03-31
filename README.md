# easy_sync

A Flutter sync orchestration package that standardizes app-open, manual, and background sync flows without imposing backend, auth, or database decisions.

## Overview

easy_sync helps you coordinate sync work as reusable tasks. You define task logic and policies, and the package handles orchestration concerns such as trigger filtering, retry backoff, task state tracking, and safe execution.

It is designed for teams that want consistent sync behavior across features without introducing tight coupling to any specific API, auth provider, or storage layer.

## Why This Package Exists

Many Flutter apps need the same sync capabilities:
- Run selected sync jobs when the app opens.
- Trigger sync manually from pull-to-refresh or a button.
- Run periodic/background sync when the platform allows it.
- Retry transient failures with backoff.
- Understand which task ran, failed, or was blocked.

easy_sync provides these orchestration primitives while letting your app keep ownership of business rules and data flow.

## Key Features

- Trigger-aware task policies: app-open, manual, background.
- Retry with exponential backoff for retryable failures.
- Per-task and global preconditions.
- Task state tracking with stream updates.
- Safe task isolation to avoid whole-run crashes.
- Optional per-task timeout control.
- Workmanager adapter for background execution integration.

## Use Cases

- Offline-first apps that sync local changes when connectivity returns.
- Content apps that refresh feeds at app-open and on user action.
- Business apps that periodically sync queue/analytics data in background.
- Any app that needs consistent sync behavior across multiple features.

## Installation

Add dependency:

```yaml
dependencies:
  easy_sync: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:easy_sync/easy_sync.dart';

class UploadPendingItemsTask implements SyncTask {
  UploadPendingItemsTask({
    required this.upload,
    required this.readAccessToken,
  });

  final Future<void> Function() upload;
  final Future<String?> Function() readAccessToken;

  @override
  String get key => 'upload_pending_items';

  @override
  SyncPolicy get policy => const SyncPolicy(
        appOpen: true,
        manual: true,
        background: true,
        retry: RetryConfig.exponential(
          initialDelay: Duration(seconds: 1),
          maxRetries: 4,
        ),
      );

  @override
  List<SyncPrecondition> get preconditions => <SyncPrecondition>[
        RequiresNetworkPrecondition(
          checker: (context) async => context.value<bool>('hasNetwork') ?? false,
        ),
        _AuthReadyPrecondition(readAccessToken: readAccessToken),
      ];

  @override
  SyncTaskHandler get handler => _UploadPendingItemsHandler(upload: upload);
}

class _UploadPendingItemsHandler implements SyncTaskHandler {
  _UploadPendingItemsHandler({required this.upload});

  final Future<void> Function() upload;

  @override
  Future<SyncResult> execute(SyncContext context) async {
    try {
      await upload();
      return SyncResult.success();
    } catch (error, stackTrace) {
      // Decide retryability in app logic.
      return SyncResult.retryable(error: error, stackTrace: stackTrace);
    }
  }
}

// App-level precondition example. Auth is intentionally app-owned.
class _AuthReadyPrecondition implements SyncPrecondition {
  _AuthReadyPrecondition({required this.readAccessToken});

  final Future<String?> Function() readAccessToken;

  @override
  String get name => 'auth-ready';

  @override
  Future<PreconditionResult> check(SyncContext context) async {
    final token = await readAccessToken();
    if (token == null) {
      return PreconditionResult.blocked(reason: 'Missing access token');
    }
    return PreconditionResult.allow();
  }
}

Future<EasySync> createSync() async {
  final easySync = EasySync.initialize(
    tasks: <SyncTask>[
      UploadPendingItemsTask(
        upload: () async {
          // Call your own repository/API layer here.
        },
        readAccessToken: () async {
          // Read from your own secure storage/auth module.
          return 'token';
        },
      ),
    ],
    taskTimeout: const Duration(seconds: 20),
    debugMode: false,
    isolateTaskFailures: true,
  );

  return easySync;
}
```

Manual triggers:

```dart
final easySync = await createSync();

// Pull-to-refresh style sync
final allStates = await easySync.runAll(
  metadata: <String, Object?>{
    'source': 'pull_to_refresh',
    'hasNetwork': true,
  },
);

// Run only one task
final taskState = await easySync.runTask(
  'upload_pending_items',
  metadata: <String, Object?>{
    'source': 'manual_button',
    'hasNetwork': true,
  },
);

print(allStates.length);
print(taskState.status);
```

## Core Concepts

- SyncTask: A uniquely keyed unit of sync work.
- SyncPolicy: Controls which triggers can run the task.
- SyncTaskHandler: Contains the executable sync logic.
- SyncPrecondition: Guards task execution (network/auth/custom checks).
- SyncResult: Declares success/failure/retryable outcome.
- SyncTaskState: Runtime state record for each task.
- EasySync: Convenience facade for manual task execution APIs.
- WorkmanagerSyncBridge: Adapter to map background callbacks to sync execution.

## API Examples

Listen to state updates:

```dart
final subscription = easySync.stateStream.listen((state) {
  print('task=${state.taskKey} status=${state.status.name} attempt=${state.attempt}');
});

// Later
await subscription.cancel();
```

Use custom retry scheduling callback:

```dart
final easySync = EasySync.initialize(
  tasks: tasks,
  onRetryScheduled: ({required taskId, required delay, required metadata}) async {
    // Optional: mirror next retry scheduling into app telemetry.
    print('retry task=$taskId in ${delay.inSeconds}s');
  },
);
```

## Preconditions

Preconditions are execution gates. If any precondition returns blocked, the task is marked blocked and handler logic is skipped.

Recommended usage:
- Keep preconditions lightweight and deterministic.
- Use app-owned checks for auth readiness, account state, feature flags, and storage health.
- Pass context values through metadata when appropriate (for example hasNetwork).

## Background Sync (Workmanager)

easy_sync integrates with workmanager for background execution registration and dispatching.

```dart
import 'package:easy_sync/easy_sync.dart';

Future<void> configureBackground(List<SyncTaskRegistration> taskRegistrations) async {
  // 1) Register mapping from workmanager task name -> easy_sync task set.
  WorkmanagerSyncBridge.registerTaskMapping(
    taskName: 'sync-background',
    taskRegistrations: taskRegistrations,
    stateStoreFactory: InMemorySyncTaskStateStore.new,
    isolateTaskFailures: true,
    taskTimeout: const Duration(seconds: 20),
  );

  // 2) Initialize workmanager dispatcher.
  final scheduler = WorkmanagerBackgroundScheduler();
  await scheduler.initialize(isInDebugMode: false);

  // 3) Schedule periodic job.
  await scheduler.schedulePeriodic(
    uniqueName: 'easy-sync-periodic',
    taskName: 'sync-background',
    frequency: const Duration(hours: 1),
    inputData: <String, dynamic>{'source': 'periodic'},
  );
}
```

### Platform Notes

- Android: WorkManager semantics apply.
- iOS: BGTaskScheduler semantics apply through workmanager.
- iOS timing is best-effort. Exact run time is not guaranteed.
- Background execution depends on OS policies, battery conditions, and app usage patterns.

## Platform Limitations

- No guarantee of exact background execution intervals.
- Background tasks may be deferred, coalesced, or skipped by the OS.
- iOS may run fewer background opportunities than Android.
- Requires native platform setup required by workmanager.

## Best Practices

- Keep task handlers idempotent.
- Return SyncResult.retryable only for transient failures.
- Keep preconditions fast and side-effect free.
- Use metadata to label trigger sources for observability.
- Store meaningful failure reasons for easier diagnosis.
- Start with conservative retry settings and tune from production behavior.

## Troubleshooting

Task always blocked:
- Verify preconditions and metadata values (for example hasNetwork).
- Confirm auth-related preconditions are app-side and returning allow.

Task retries are not happening:
- Ensure task policy includes retry configuration.
- Ensure handler returns SyncResult.retryable for transient failures.
- Confirm maxRetries has not already been exceeded.

Background task does not run when expected:
- Confirm workmanager native setup on each platform.
- Confirm task name used for scheduling matches registerTaskMapping.
- Remember background execution timing is not guaranteed.

## FAQ

Does easy_sync provide authentication?
- No. Authentication is app-owned by design.

Does easy_sync include API clients or database adapters?
- No. It is backend-agnostic and database-agnostic.

Can I use this without background sync?
- Yes. You can use only manual and app-open orchestration paths.

Can I track execution state in UI?
- Yes. Subscribe to stateStream.

## Contributing

Contributions are welcome.

Before opening a pull request:
- Run tests locally.
- Keep changes focused and documented.
- Include test coverage for behavior changes.

Project and contribution links should be set in pubspec metadata before publishing.

## License

This package is licensed under the MIT License.

Add a LICENSE file at the repository root if not already present.
