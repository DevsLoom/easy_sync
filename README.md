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

If you use background sync, also complete the native platform setup required by `workmanager` for Android and iOS.

### Native Setup For Background Sync

Use these steps before calling `WorkmanagerBackgroundScheduler.initialize()` and `schedulePeriodic()`.

#### Android

Android setup is the simple part.

1. Add `easy_sync` to your app.
2. Run `flutter pub get`.
3. Make sure your app uses Flutter's default generated Android setup.
4. No extra Android manifest or Application class setup is usually needed for basic workmanager usage.

In most apps, Android works after Dart-side initialization only.

#### iOS

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
    <string>com.yourapp.sync-background</string>
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
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.yourapp.sync-background",
      frequency: NSNumber(value: 20 * 60)
    )

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

Keep these rules in mind:
- Use the same identifier in `Info.plist` and `AppDelegate.swift`.
- iOS background execution is best-effort.
- Exact timing is not guaranteed.
- Real devices are more reliable than simulators for background testing.

If you want the most up-to-date native details, check the `workmanager` quick start as well, because platform requirements can change between plugin versions.

## Quick Start

Start with one task and trigger it manually.

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
      // Mark transient failures as retryable.
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

Future<void> example() async {
  final easySync = EasySync.initialize(
    tasks: <SyncTask>[
      UploadPendingItemsTask(
        upload: () async {
          // Call your own repository or API layer here.
        },
        readAccessToken: () async {
          // Read from your own auth or secure storage layer.
          return 'token';
        },
      ),
    ],
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

## Recommended Integration Order

Use this order in a real Flutter app:

1. Define your `SyncTask` implementations.
2. Initialize `EasySync` near app startup.
3. Register background task mappings with `WorkmanagerSyncBridge.registerTaskMapping()`.
4. Initialize `WorkmanagerBackgroundScheduler()`.
5. Schedule a periodic background job.
6. Trigger app-open sync on first load and on app resume.
7. Use manual sync from pull-to-refresh, buttons, or settings screens.

A good mental model is:
- `EasySync.initialize()` is for manual sync APIs and state streaming.
- `WorkmanagerSyncBridge.registerTaskMapping()` connects workmanager callbacks to your tasks.
- app-open sync is usually triggered from app lifecycle code.

## Full Example (main.dart)

This example shows a practical startup flow.

```dart
import 'package:flutter/material.dart';
import 'package:easy_sync/easy_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Define all sync tasks in one place.
  final tasks = <SyncTask>[
    UploadPendingItemsTask(
      upload: () async {
        // Call your repository or API layer.
      },
      readAccessToken: () async {
        // Read from your auth module.
        return 'token';
      },
    ),
  ];

  // 2) Create a shared state store for app-open and manual sync state.
  final stateStore = InMemorySyncTaskStateStore();

  // 3) Initialize EasySync for manual triggers and state stream access.
  final easySync = EasySync.initialize(
    tasks: tasks,
    stateStore: stateStore,
    taskTimeout: const Duration(seconds: 20),
    isolateTaskFailures: true,
  );

  // 4) Build registrations once so they can be reused by app-open and background flows.
  final taskRegistrations = <SyncTaskRegistration>[
    for (final task in tasks) SyncTaskRegistration(task: task),
  ];

  // 5) Create a SyncEngine for app-open lifecycle triggers.
  final appOpenEngine = SyncEngine(
    taskRegistrations: taskRegistrations,
    stateStore: stateStore,
    taskTimeout: const Duration(seconds: 20),
    isolateTaskFailures: true,
  );

  // 6) Register background mappings before scheduling jobs.
  WorkmanagerSyncBridge.registerTaskMapping(
    taskName: 'sync-background',
    taskRegistrations: taskRegistrations,
    stateStoreFactory: InMemorySyncTaskStateStore.new,
    taskTimeout: const Duration(seconds: 20),
    isolateTaskFailures: true,
  );

  // 7) Initialize the workmanager scheduler.
  final backgroundScheduler = WorkmanagerBackgroundScheduler();
  await backgroundScheduler.initialize();

  // 8) Schedule the periodic background job.
  await backgroundScheduler.schedulePeriodic(
    uniqueName: 'easy-sync-periodic',
    taskName: 'sync-background',
    frequency: const Duration(hours: 1),
    inputData: const <String, dynamic>{
      'source': 'periodic',
      'hasNetwork': true,
    },
  );

  runApp(
    MyApp(
      easySync: easySync,
      appOpenEngine: appOpenEngine,
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.easySync,
    required this.appOpenEngine,
  });

  final EasySync easySync;
  final SyncEngine appOpenEngine;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();

    // 9) Start listening to app lifecycle events.
    WidgetsBinding.instance.addObserver(this);

    // 10) Trigger app-open sync the first time the app is shown.
    widget.appOpenEngine.runAll(
      SyncPolicyType.appOpen,
      metadata: const <String, Object?>{
        'source': 'app_start',
        'hasNetwork': true,
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.easySync.dispose();
    widget.appOpenEngine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    // 11) Trigger app-open sync again when the app returns to foreground.
    widget.appOpenEngine.runAll(
      SyncPolicyType.appOpen,
      metadata: const <String, Object?>{
        'source': 'app_resume',
        'hasNetwork': true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('easy_sync example')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              // 12) Use manual sync from the UI when needed.
              await widget.easySync.runAll(
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

Use app lifecycle events to trigger tasks whose `SyncPolicy.appOpen` is `true`.

```dart
import 'package:flutter/widgets.dart';
import 'package:easy_sync/easy_sync.dart';

class SyncLifecycleController extends StatefulWidget {
  const SyncLifecycleController({
    super.key,
    required this.appOpenEngine,
    required this.child,
  });

  final SyncEngine appOpenEngine;
  final Widget child;

  @override
  State<SyncLifecycleController> createState() => _SyncLifecycleControllerState();
}

class _SyncLifecycleControllerState extends State<SyncLifecycleController>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Trigger once on first load.
    widget.appOpenEngine.runAll(
      SyncPolicyType.appOpen,
      metadata: const <String, Object?>{
        'source': 'app_start',
        'hasNetwork': true,
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    // Trigger again when the app returns to foreground.
    widget.appOpenEngine.runAll(
      SyncPolicyType.appOpen,
      metadata: const <String, Object?>{
        'source': 'app_resume',
        'hasNetwork': true,
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

Use app-open sync when you want tasks to run:
- on first launch into the app session
- when the user returns from background
- only for tasks that should refresh on foreground entry

## Manual Sync

Use `EasySync` from UI interactions such as pull-to-refresh or a button tap.

```dart
final easySync = EasySync.initialize(
  tasks: tasks,
  taskTimeout: const Duration(seconds: 20),
  isolateTaskFailures: true,
);

// Run all manual-enabled tasks.
await easySync.runAll(
  metadata: const <String, Object?>{
    'source': 'pull_to_refresh',
    'hasNetwork': true,
  },
);

// Run one task by key.
await easySync.runTask(
  'upload_pending_items',
  metadata: const <String, Object?>{
    'source': 'retry_button',
    'hasNetwork': true,
  },
);
```

## Background Sync

Use workmanager integration for periodic background execution.

```dart
final tasks = <SyncTask>[
  UploadPendingItemsTask(
    upload: () async {},
    readAccessToken: () async => 'token',
  ),
];

final taskRegistrations = <SyncTaskRegistration>[
  for (final task in tasks) SyncTaskRegistration(task: task),
];

WorkmanagerSyncBridge.registerTaskMapping(
  taskName: 'sync-background',
  taskRegistrations: taskRegistrations,
  stateStoreFactory: InMemorySyncTaskStateStore.new,
  taskTimeout: const Duration(seconds: 20),
  isolateTaskFailures: true,
);

final scheduler = WorkmanagerBackgroundScheduler();
await scheduler.initialize();
await scheduler.schedulePeriodic(
  uniqueName: 'easy-sync-periodic',
  taskName: 'sync-background',
  frequency: const Duration(hours: 1),
  inputData: const <String, dynamic>{
    'source': 'periodic',
    'hasNetwork': true,
  },
);
```

Keep in mind:
- Android uses WorkManager semantics.
- iOS uses BGTaskScheduler semantics via `workmanager`.
- background timing is not guaranteed
- iOS background timing is especially best-effort

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

Where should I call `EasySync.initialize()`?
- Near app startup, usually in `main()` before `runApp()`.

Where should I configure background sync?
- During app startup, before scheduling periodic work.

When should I trigger app-open sync?
- In `initState()` for the first app load and again when the app resumes.
