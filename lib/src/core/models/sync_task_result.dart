import 'package:meta/meta.dart';

@immutable
class SyncTaskResult {
  const SyncTaskResult._({
    required this.success,
    required this.skipped,
    this.skipReason,
    this.error,
    this.stackTrace,
  });

  factory SyncTaskResult.success() =>
      const SyncTaskResult._(success: true, skipped: false);

  factory SyncTaskResult.skipped({String? reason}) => SyncTaskResult._(
        success: false,
        skipped: true,
        skipReason: reason,
      );

  factory SyncTaskResult.failure(
          {required Object error, StackTrace? stackTrace}) =>
      SyncTaskResult._(
        success: false,
        skipped: false,
        error: error,
        stackTrace: stackTrace,
      );

  final bool success;
  final bool skipped;
  final String? skipReason;
  final Object? error;
  final StackTrace? stackTrace;
}
