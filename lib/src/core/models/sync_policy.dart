import 'package:meta/meta.dart';

import 'retry_config.dart';
import 'sync_trigger.dart';

@immutable
/// Controls when a task is allowed to execute.
class SyncPolicy {
  /// Creates a sync policy.
  const SyncPolicy({
    this.appOpen = true,
    this.manual = true,
    this.background = true,
    this.interval,
    this.retry = const RetryConfig.disabled(),
  });

  /// Whether the task can run on app open.
  final bool appOpen;

  /// Whether the task can run when manually triggered.
  final bool manual;

  /// Whether the task can run from background execution.
  final bool background;

  /// Optional interval hint for integrations that want cadence metadata.
  final Duration? interval;

  /// Retry configuration applied after retryable failures.
  final RetryConfig retry;

  /// Returns whether this policy allows the given [trigger].
  bool allows(SyncTrigger trigger) {
    switch (trigger) {
      case SyncTrigger.appOpen:
        return appOpen;
      case SyncTrigger.manual:
        return manual;
      case SyncTrigger.background:
        return background;
      case SyncTrigger.retry:
        return retry.enabled;
    }
  }
}
