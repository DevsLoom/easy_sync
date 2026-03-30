import 'package:meta/meta.dart';

import 'retry_config.dart';
import 'sync_trigger.dart';

@immutable
class SyncPolicy {
  const SyncPolicy({
    this.appOpen = true,
    this.manual = true,
    this.background = true,
    this.interval,
    this.retry = const RetryConfig.disabled(),
  });

  final bool appOpen;
  final bool manual;
  final bool background;
  final Duration? interval;
  final RetryConfig retry;

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
