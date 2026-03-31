# easy_sync

A Flutter sync orchestration package that standardizes app-open, manual, and background sync flows without imposing backend, auth, or database decisions.

## Overview

`easy_sync` helps you organize sync work into reusable tasks.

It is designed for apps that need to:
- run sync on app open
- trigger sync manually from the UI
- schedule background sync with workmanager
- retry transient failures with backoff
- track task state in a predictable way

The package is:
- auth-agnostic
- backend-agnostic
- database-agnostic
- reusable across different Flutter apps

## Installation

Add the package to your app:

```yaml
dependencies:
  easy_sync: ^0.1.0
```

Then install dependencies:

```bash
flutter pub get
```

If you enable background sync, complete the platform setup in the `Native Setup For Background Sync` section below.

## Quick Start

Set up `easy_sync` with a minimal task:

```dart
import 'package:easy_sync/easy_sync.dart';

class SimpleSyncTask implements SyncTask {

  @override
  String get key => 'simple';

  @override
  SyncPolicy get policy => const SyncPolicy(
        manual: true,
      );

  @override
  List<SyncPrecondition> get preconditions => [];

  @override
  SyncTaskHandler get handler => _SimpleSyncHandler();
}

class _SimpleSyncHandler implements SyncTaskHandler {

  @override
  Future<SyncResult> execute(SyncContext context) async {
    return SyncResult.success();
  }
}

Future<void> example() async {
  final easySync = await EasySync.setup(
    tasks: <SyncTask>[SimpleSyncTask()],
    appOpenSync: true,
    background: EasySyncBackgroundConfig.enabled(
      frequency: const Duration(hours: 1),
    ),
    taskTimeout: const Duration(seconds: 20),
    isolateTaskFailures: true,
  );

  await easySync.runAll(
    metadata: const <String, Object?>{
      'source': 'manual',
      'hasNetwork': true,
    },
  );

  await easySync.dispose();
}
```

See the Full Example below for a production-ready setup with retry handling, preconditions, and background sync configuration.

## Recommended Integration Order

Follow this simple flow in your app:

1. Define your `SyncTask` classes
2. Call `EasySync.setup(...)` during app startup (usually in `main()`)
3. Pass the returned `EasySync` instance into your app
4. Trigger manual sync from the UI when needed (`runAll()` / `runTask()`)
5. Let `easy_sync` handle app-open and background sync automatically

## Full Example (main.dart)

This example shows a practical startup flow.

```dart
import 'package:flutter/material.dart';
import 'package:easy_sync/easy_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final easySync = await EasySync.setup(
    // 1) Define your app tasks.
    tasks: <SyncTask>[
      UploadPendingItemsTask(
        upload: () async {
          // Call your repository or API layer.
        },
        readAccessToken: () async {
          // Read from your auth module.
          return 'token';
        },
      ),
    ],
    // 2) Automatically trigger app-open sync on start and resume.
    appOpenSync: true,
    // 3) Enable background sync with the common configuration path.
    background: EasySyncBackgroundConfig.enabled(
      frequency: const Duration(hours: 1),
    ),
    // 4) Optional execution safety settings.
    taskTimeout: const Duration(seconds: 20),
    isolateTaskFailures: true,
  );

  // 5) The app only needs the returned EasySync instance.
  runApp(MyApp(easySync: easySync));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.easySync});

  final EasySync easySync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('easy_sync example')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              // 6) Manual sync stays simple.
              await easySync.runAll(
                metadata: const <String, Object?>{
                  'source': 'button_tap',
                  'hasNetwork': true,
                },
              );
            },
            child: const Text('Run Manual Sync'),
          ),
        ),
      ),
    );
  }
}

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
      return SyncResult.retryable(error: error, stackTrace: stackTrace);
    }
  }
}

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
```

## App Open Sync

For the common case, set `appOpenSync: true` in `EasySync.setup()`.

```dart
final easySync = await EasySync.setup(
  tasks: tasks,
  appOpenSync: true,
);
```

This automatically:
- triggers app-open tasks once on startup
- listens for `AppLifecycleState.resumed`
- triggers app-open tasks again when the app returns to foreground

## Manual Sync

Use the returned `EasySync` instance from UI interactions such as pull-to-refresh or a button tap.

```dart
await easySync.runAll(
  metadata: const <String, Object?>{
    'source': 'pull_to_refresh',
    'hasNetwork': true,
  },
);

await easySync.runTask(
  'upload_pending_items',
  metadata: const <String, Object?>{
    'source': 'retry_button',
    'hasNetwork': true,
  },
);
```

## Background Sync

For the common case, provide `EasySyncBackgroundConfig.enabled()` to `EasySync.setup()`.

```dart
final easySync = await EasySync.setup(
  tasks: tasks,
  background: EasySyncBackgroundConfig.enabled(
    frequency: const Duration(hours: 1),
  ),
);
```

To explicitly disable background scheduling while keeping the rest of `setup()` the same:

```dart
final easySync = await EasySync.setup(
  tasks: tasks,
  background: EasySyncBackgroundConfig.disabled(),
);
```

Keep in mind:
- Android uses WorkManager semantics.
- iOS uses BGTaskScheduler semantics via `workmanager`.
- Android periodic work has a practical 15 minute minimum interval behavior.
- If you pass less than 15 minutes, `easy_sync` clamps it to 15 minutes.
- background timing is not guaranteed
- iOS background timing is especially best-effort

## Native Setup For Background Sync

Use these steps before enabling background sync through `EasySync.setup(...)`.

### Android

Android setup is the simple part.

1. Add `easy_sync` to your app.
2. Run `flutter pub get`.
3. Make sure your app uses Flutter's default generated Android setup.
4. No extra Android manifest or Application class setup is usually needed for basic workmanager usage.

In most apps, Android works after Dart-side initialization only.

### iOS

iOS needs explicit native setup.

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the `Runner` target.
3. Set the minimum deployment target to iOS 14.0 or later.
4. Open `Signing & Capabilities`.
5. Add `Background Modes`.
6. Enable the background mode that matches your scheduling approach.

For periodic background sync with workmanager, use BGTaskScheduler-style setup:

Add these keys in `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <!-- Example: if your app id is ca.devsloom.testapp -->
  <string>ca.devsloom.testapp.sync-background</string>
</array>
```

Then register the same identifier in `ios/Runner/AppDelegate.swift`:

```swift
import UIKit
import Flutter
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Use your own app's bundle-style identifier here.
    // Example:
    // if your app id is ca.devsloom.testapp
    // then use ca.devsloom.testapp.sync-background
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "ca.devsloom.testapp.sync-background",
      frequency: NSNumber(value: 20 * 60)
    )

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

Keep these rules in mind:
- Use the same identifier in `Info.plist` and `AppDelegate.swift`.
- A safe pattern is: `<your-app-id>.sync-background`.
- iOS background execution is best-effort.
- Exact timing is not guaranteed.
- Real devices are more reliable than simulators for background testing.

If you want the most up-to-date native details, check the `workmanager` quick start as well, because platform requirements can change between plugin versions.

## Advanced Usage

The high-level `EasySync.setup()` API is meant for the common integration path.

Use the lower-level APIs when you need custom control over:
- task registration creation
- state store lifecycle
- app-open scheduling behavior
- background bridge registration
- scheduler initialization timing

Available lower-level APIs:
- `EasySync.initialize(...)`
- `EasySyncBackgroundConfig.periodic(...)`
- `SyncEngine`
- `SyncTaskRegistration`
- `WorkmanagerSyncBridge.registerTaskMapping(...)`
- `WorkmanagerBackgroundScheduler.initialize()`
- `WorkmanagerBackgroundScheduler.schedulePeriodic(...)`

Example:

```dart
final easySync = EasySync.initialize(
  tasks: tasks,
  stateStore: InMemorySyncTaskStateStore(),
);

final taskRegistrations = <SyncTaskRegistration>[
  for (final task in tasks) SyncTaskRegistration(task: task),
];

WorkmanagerSyncBridge.registerTaskMapping(
  taskName: 'sync-background',
  taskRegistrations: taskRegistrations,
  stateStoreFactory: InMemorySyncTaskStateStore.new,
);

final scheduler = WorkmanagerBackgroundScheduler();
await scheduler.initialize();
await scheduler.schedulePeriodic(
  uniqueName: 'easy-sync-periodic',
  taskName: 'sync-background',
  frequency: const Duration(hours: 1),
);
```

Use `EasySyncBackgroundConfig.periodic(...)` when you need to customize values such as:
- `uniqueName`
- `taskName`
- `inputData`
- `stateStoreFactory`
- `initialDelay`
- custom scheduler driver for advanced integrations or testing

## Core Concepts

- `SyncTask`: a uniquely keyed unit of sync work
- `SyncPolicy`: controls whether a task can run on app-open, manual, or background triggers
- `SyncTaskHandler`: contains the actual sync implementation
- `SyncPrecondition`: blocks execution until requirements are met
- `SyncResult`: reports success, failure, or retryable failure
- `SyncTaskState`: stores the latest known runtime state for a task
- `EasySync`: convenience API for manual sync and state streaming
- `WorkmanagerSyncBridge`: connects workmanager callbacks to your task registrations

## Preconditions

Preconditions decide whether a task is allowed to run.

Use them for checks such as:
- network availability
- authentication readiness
- account state
- feature flags

Example:

```dart
class AuthReadyPrecondition implements SyncPrecondition {
  AuthReadyPrecondition(this.readAccessToken);

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
```

## Retry

Retries are controlled by `SyncPolicy.retry` and only happen when your handler returns `SyncResult.retryable(...)`.

```dart
@override
SyncPolicy get policy => const SyncPolicy(
      manual: true,
      background: true,
      retry: RetryConfig.exponential(
        initialDelay: Duration(seconds: 1),
        maxRetries: 4,
      ),
    );
```

This produces delays like:
- 1s
- 2s
- 4s
- 8s

Use retry only for transient failures such as:
- temporary network issues
- short-lived server errors
- temporary dependency failures

## State Tracking

Use `stateStream` to observe task changes.

```dart
final subscription = easySync.stateStream.listen((state) {
  print(
    'task=${state.taskKey} status=${state.status.name} attempt=${state.attempt}',
  );
});

await subscription.cancel();
```

This is useful for:
- loading indicators
- sync history UI
- retry messaging
- debug logging

## Platform Notes

- Android background work follows WorkManager behavior.
- iOS background work follows BGTaskScheduler behavior through `workmanager`.
- Some devices and OS versions may delay or skip background work.
- For native setup details, use the `workmanager` package documentation.

## Limitations

- `easy_sync` does not provide authentication.
- `easy_sync` does not provide API clients.
- `easy_sync` does not provide local database integration.
- background execution timing is not guaranteed
- iOS background execution is best-effort and may be infrequent

## FAQ

Does `easy_sync` include authentication?
- No. It is intentionally auth-agnostic.

Does `easy_sync` include API client or database code?
- No. It is backend-agnostic and database-agnostic.

Where should I call `EasySync.setup()`?
- Near app startup, usually in `main()` before `runApp()`.

Where should I configure background sync?
- During app startup, before scheduling periodic work.

When should I trigger app-open sync?
- Set `appOpenSync: true` in `EasySync.setup()` for the common case.
