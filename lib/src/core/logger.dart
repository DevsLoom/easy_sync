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
