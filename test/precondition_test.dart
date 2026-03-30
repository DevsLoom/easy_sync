import 'package:easy_sync/easy_sync.dart';
import 'package:test/test.dart';

void main() {
  group('PreconditionResult', () {
    test('allow result is allowed and not blocked', () {
      final result = PreconditionResult.allow();
      expect(result.allow, isTrue);
      expect(result.blocked, isFalse);
    });

    test('blocked result carries reason', () {
      final result = PreconditionResult.blocked(reason: 'No internet');
      expect(result.allow, isFalse);
      expect(result.blocked, isTrue);
      expect(result.reason, 'No internet');
    });
  });

  group('RequiresNetworkPrecondition', () {
    test('allows when hasNetwork metadata is true', () async {
      final precondition = RequiresNetworkPrecondition();
      final context = SyncContext(metadata: {'hasNetwork': true});

      final result = await precondition.check(context);
      expect(result.allow, isTrue);
    });

    test('blocks when hasNetwork metadata is false', () async {
      final precondition = RequiresNetworkPrecondition();
      final context = SyncContext(metadata: {'hasNetwork': false});

      final result = await precondition.check(context);
      expect(result.blocked, isTrue);
      expect(result.reason, isNotNull);
    });
  });

  group('Custom preconditions', () {
    test('supports auth-style custom precondition without auth implementation',
        () async {
      final precondition = PredicatePrecondition(
        name: 'auth-check',
        predicate: (context) async =>
            context.value<bool>('isSignedIn') ?? false,
      );

      final result =
          await precondition.check(SyncContext(metadata: {'isSignedIn': true}));
      expect(result.allow, isTrue);
    });

    test('supports subscription and feature-flag checks', () async {
      final subscription = PredicatePrecondition(
        name: 'subscription-check',
        predicate: (context) async =>
            (context.value<String>('plan') ?? 'free') != 'free',
      );
      final featureFlag = PredicatePrecondition(
        name: 'feature-flag-check',
        predicate: (context) async =>
            context.value<bool>('syncEnabled') ?? false,
      );

      final composite = CompositePrecondition(
        name: 'access-checks',
        preconditions: [subscription, featureFlag],
      );

      final result = await composite.check(
        SyncContext(metadata: {'plan': 'pro', 'syncEnabled': true}),
      );

      expect(result.allow, isTrue);
    });
  });
}
