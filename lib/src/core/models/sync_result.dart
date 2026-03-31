import 'package:meta/meta.dart';

@immutable
/// Result returned by a sync task handler.
class SyncResult {
  /// Internal constructor used by helper factories.
  const SyncResult._({
    required this.success,
    required this.failure,
    required this.retryable,
    this.error,
    this.stackTrace,
  });

  /// Creates a successful sync result.
  factory SyncResult.success() =>
      const SyncResult._(success: true, failure: false, retryable: false);

  /// Creates a failed, non-retryable sync result.
  factory SyncResult.failure({Object? error, StackTrace? stackTrace}) =>
      SyncResult._(
        success: false,
        failure: true,
        retryable: false,
        error: error,
        stackTrace: stackTrace,
      );

  /// Creates a failed, retryable sync result.
  factory SyncResult.retryable({Object? error, StackTrace? stackTrace}) =>
      SyncResult._(
        success: false,
        failure: true,
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );

  /// Whether the task succeeded.
  final bool success;

  /// Whether the task failed.
  final bool failure;

  /// Whether the failure should be retried.
  final bool retryable;

  /// Optional error captured from execution.
  final Object? error;

  /// Optional stack trace associated with [error].
  final StackTrace? stackTrace;
}
