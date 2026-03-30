import '../core/core.dart';

class SyncConfig {
  const SyncConfig({
    this.globalPreconditions = const <SyncPrecondition>[],
    this.defaultPolicy = const SyncPolicy(),
    this.logger = const NoopSyncLogger(),
  });

  final List<SyncPrecondition> globalPreconditions;
  final SyncPolicy defaultPolicy;
  final SyncLogger logger;
}
