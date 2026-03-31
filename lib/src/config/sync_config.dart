import '../core/core.dart';

/// Shared sync configuration defaults for custom integrations.
class SyncConfig {
  /// Creates a sync configuration container.
  const SyncConfig({
    this.globalPreconditions = const <SyncPrecondition>[],
    this.defaultPolicy = const SyncPolicy(),
    this.logger = const NoopSyncLogger(),
  });

  /// Preconditions applied globally to all tasks.
  final List<SyncPrecondition> globalPreconditions;

  /// Default policy used by custom integrations.
  final SyncPolicy defaultPolicy;

  /// Logger used by sync components.
  final SyncLogger logger;
}
