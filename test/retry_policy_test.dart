import 'package:easy_sync/easy_sync.dart';
import 'package:test/test.dart';

void main() {
  group('RetryConfig', () {
    test('returns increasing delay until max attempts', () {
      const config = RetryConfig.exponential(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 8),
        maxAttempts: 3,
      );

      expect(config.nextDelay(1), const Duration(seconds: 1));
      expect(config.nextDelay(2), const Duration(seconds: 2));
      expect(config.nextDelay(3), const Duration(seconds: 4));
      expect(config.nextDelay(4), isNull);
    });

    test('caps delay by maxDelay', () {
      const config = RetryConfig.exponential(
        initialDelay: Duration(seconds: 5),
        maxDelay: Duration(seconds: 6),
        maxAttempts: 5,
      );

      expect(config.nextDelay(2), const Duration(seconds: 6));
    });

    test('disabled config does not schedule retry', () {
      const config = RetryConfig.disabled();
      expect(config.nextDelay(1), isNull);
    });
  });
}
