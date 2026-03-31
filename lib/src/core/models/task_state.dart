import 'package:meta/meta.dart';

import 'sync_task_status.dart';
import 'sync_trigger.dart';

@immutable
/// Snapshot of the latest known runtime state for a sync task.
class SyncTaskState {
  /// Creates a task state snapshot.
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

  /// Creates an initial idle state for [taskId].
  factory SyncTaskState.initial(String taskId) =>
      SyncTaskState(taskId: taskId, status: SyncTaskStatus.idle, attempt: 0);

  /// Unique task identifier.
  final String taskId;

  /// Current task status.
  final SyncTaskStatus status;

  /// Current attempt count for the active failure cycle.
  final int attempt;

  /// Last captured error message, if any.
  final String? lastError;

  /// Timestamp of the latest task start.
  final DateTime? lastStartedAt;

  /// Timestamp of the latest task completion.
  final DateTime? lastFinishedAt;

  /// Scheduled time for the next retry, if any.
  final DateTime? nextRetryAt;

  /// Most recent trigger that ran this task.
  final SyncTrigger? lastTrigger;

  /// Alias for [taskId].
  String get taskKey => taskId;

  /// Creates a copy of this state with the provided field changes.
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
