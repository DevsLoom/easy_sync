import 'package:easy_sync/easy_sync.dart';

Future<void> main() async {
  final easySync = EasySync.initialize(
    tasks: <SyncTask>[_SampleSyncTask()],
    isolateTaskFailures: true,
  );

  await easySync.runAll(
    metadata: const <String, Object?>{
      'source': 'example_main',
      'hasNetwork': true,
    },
  );

  await easySync.dispose();
}

class _SampleSyncTask implements SyncTask {
  @override
  String get key => 'sample-task';

  @override
  SyncPolicy get policy =>
      const SyncPolicy(appOpen: true, manual: true, background: false);

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
