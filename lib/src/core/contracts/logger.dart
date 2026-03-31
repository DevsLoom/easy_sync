/// Logging interface used by sync components.
abstract interface class SyncLogger {
  /// Emits an informational message.
  void info(String message);

  /// Emits a warning message.
  void warn(String message);

  /// Emits an error message with optional error details.
  void error(String message, {Object? error, StackTrace? stackTrace});
}

/// A logger implementation that discards all messages.
class NoopSyncLogger implements SyncLogger {
  /// Creates a no-op logger.
  const NoopSyncLogger();

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}
}

/// A logger implementation that prints messages to stdout.
class PrintSyncLogger implements SyncLogger {
  /// Creates a print-based logger.
  const PrintSyncLogger({this.includeTimestamp = true});

  /// Whether timestamps are prepended to printed log messages.
  final bool includeTimestamp;

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    final buffer = StringBuffer(_prefix('ERROR'))..write(message);
    if (error != null) {
      buffer.write(' | error=$error');
    }
    if (stackTrace != null) {
      buffer.write(' | stackTrace=$stackTrace');
    }
    print(buffer.toString());
  }

  @override
  void info(String message) {
    print('${_prefix('INFO')}$message');
  }

  @override
  void warn(String message) {
    print('${_prefix('WARN')}$message');
  }

  String _prefix(String level) {
    if (!includeTimestamp) {
      return '[$level] ';
    }

    final now = DateTime.now().toIso8601String();
    return '[$now][$level] ';
  }
}
