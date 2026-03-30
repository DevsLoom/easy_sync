import 'package:meta/meta.dart';

@immutable
class SyncResult {
  const SyncResult._({
    required this.success,
    required this.failure,
    required this.retryable,
    this.error,
    this.stackTrace,
  });

  factory SyncResult.success() =>
      const SyncResult._(success: true, failure: false, retryable: false);

  factory SyncResult.failure({Object? error, StackTrace? stackTrace}) =>
      SyncResult._(
        success: false,
        failure: true,
        retryable: false,
        error: error,
        stackTrace: stackTrace,
      );

  factory SyncResult.retryable({Object? error, StackTrace? stackTrace}) =>
      SyncResult._(
        success: false,
        failure: true,
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );

  final bool success;
  final bool failure;
  final bool retryable;
  final Object? error;
  final StackTrace? stackTrace;
}
