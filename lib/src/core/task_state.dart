import 'package:meta/meta.dart';

import 'sync_task_status.dart';
import 'sync_trigger.dart';

@immutable
class SyncTaskState {
  const SyncTaskState({
    required this.taskId,
    required this.status,
    required this.attempt,
    this.lastError,
    this.lastStartedAt,
    this.lastFinishedAt,
    this.nextRetryAt,
    this.lastTrigger,
  });

  factory SyncTaskState.initial(String taskId) => SyncTaskState(
        taskId: taskId,
        status: SyncTaskStatus.idle,
        attempt: 0,
      );

  final String taskId;
  final SyncTaskStatus status;
  final int attempt;
  final String? lastError;
  final DateTime? lastStartedAt;
  final DateTime? lastFinishedAt;
  final DateTime? nextRetryAt;
  final SyncTrigger? lastTrigger;

  SyncTaskState copyWith({
    SyncTaskStatus? status,
    int? attempt,
    String? lastError,
    bool clearLastError = false,
    DateTime? lastStartedAt,
    DateTime? lastFinishedAt,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    SyncTrigger? lastTrigger,
  }) {
    return SyncTaskState(
      taskId: taskId,
      status: status ?? this.status,
      attempt: attempt ?? this.attempt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastStartedAt: lastStartedAt ?? this.lastStartedAt,
      lastFinishedAt: lastFinishedAt ?? this.lastFinishedAt,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      lastTrigger: lastTrigger ?? this.lastTrigger,
    );
  }
}
