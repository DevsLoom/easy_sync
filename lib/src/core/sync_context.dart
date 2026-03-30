import 'package:meta/meta.dart';

import 'sync_trigger.dart';

@immutable
class SyncContext {
  const SyncContext({
    required this.trigger,
    required this.timestamp,
    this.metadata = const <String, Object?>{},
  });

  final SyncTrigger trigger;
  final DateTime timestamp;
  final Map<String, Object?> metadata;

  T? value<T>(String key) => metadata[key] as T?;
}
