import '../models/sync_context.dart';
import 'precondition.dart';

typedef NetworkAvailabilityChecker = Future<bool> Function(SyncContext context);

class RequiresNetworkPrecondition implements SyncPrecondition {
  RequiresNetworkPrecondition({NetworkAvailabilityChecker? checker})
      : _checker = checker ?? _defaultChecker;

  final NetworkAvailabilityChecker _checker;

  @override
  String get name => 'requires-network';

  @override
  Future<PreconditionResult> check(SyncContext context) async {
    final online = await _checker(context);
    if (online) {
      return PreconditionResult.allow();
    }
    return PreconditionResult.blocked(reason: 'Network is unavailable');
  }

  static Future<bool> _defaultChecker(SyncContext context) async {
    return context.value<bool>('hasNetwork') ?? false;
  }
}
