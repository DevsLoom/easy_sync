import 'package:easy_sync/easy_sync.dart';
import 'package:test/test.dart';

void main() {
  group('ExponentialBackoffRetryPolicy', () {
    test('returns increasing delay until max attempts', () {
      const policy = ExponentialBackoffRetryPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 8),
        maxAttempts: 3,
      );

      expect(
        policy.nextDelay(attempt: 1, error: Exception('x')),
        const Duration(seconds: 1),
      );
      expect(
        policy.nextDelay(attempt: 2, error: Exception('x')),
        const Duration(seconds: 2),
      );
      expect(
        policy.nextDelay(attempt: 3, error: Exception('x')),
        const Duration(seconds: 4),
      );
      expect(policy.nextDelay(attempt: 4, error: Exception('x')), isNull);
    });

    test('caps delay by maxDelay', () {
      const policy = ExponentialBackoffRetryPolicy(
        initialDelay: Duration(seconds: 5),
        maxDelay: Duration(seconds: 6),
        maxAttempts: 5,
      );

      expect(
        policy.nextDelay(attempt: 2, error: Exception('x')),
        const Duration(seconds: 6),
      );
    });
  });
}
