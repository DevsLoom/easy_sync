import 'package:flutter/material.dart';

import 'package:easy_sync/easy_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final easySync = await EasySync.setup(
    tasks: <SyncTask>[_SampleSyncTask()],
    appOpenSync: true,
    background: EasySyncBackgroundConfig.periodic(
      uniqueName: 'easy-sync-periodic',
      frequency: const Duration(hours: 1),
      inputData: const <String, dynamic>{
        'source': 'example_periodic',
        'hasNetwork': true,
      },
    ),
    taskTimeout: const Duration(seconds: 20),
    isolateTaskFailures: true,
  );

  runApp(_ExampleApp(easySync: easySync));
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp({required this.easySync});

  final EasySync easySync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('easy_sync example')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              await easySync.runAll(
                metadata: const <String, Object?>{
                  'source': 'manual_button',
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

class _SampleSyncTask implements SyncTask {
  @override
  String get key => 'sample-task';

  @override
  SyncPolicy get policy =>
      const SyncPolicy(appOpen: true, manual: true, background: true);

  @override
  List<SyncPrecondition> get preconditions => <SyncPrecondition>[
    RequiresNetworkPrecondition(
      checker: (context) async => context.value<bool>('hasNetwork') ?? false,
    ),
  ];

  @override
  SyncTaskHandler get handler => _SampleSyncTaskHandler();
}

class _SampleSyncTaskHandler implements SyncTaskHandler {
  @override
  Future<SyncResult> execute(SyncContext context) async {
    return SyncResult.success();
  }
}
