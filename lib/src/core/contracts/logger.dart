abstract interface class SyncLogger {
  void info(String message);

  void warn(String message);

  void error(String message, {Object? error, StackTrace? stackTrace});
}

class NoopSyncLogger implements SyncLogger {
  const NoopSyncLogger();

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}
}

class PrintSyncLogger implements SyncLogger {
  const PrintSyncLogger({this.includeTimestamp = true});

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
