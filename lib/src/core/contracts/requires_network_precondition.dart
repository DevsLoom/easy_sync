import '../models/sync_context.dart';
import 'precondition.dart';

/// Function signature used to determine current network availability.
typedef NetworkAvailabilityChecker = Future<bool> Function(SyncContext context);

/// A precondition that blocks execution while the app is offline.
class RequiresNetworkPrecondition implements SyncPrecondition {
  /// Creates a network precondition with an optional custom connectivity check.
  RequiresNetworkPrecondition({NetworkAvailabilityChecker? checker})
    : _checker = checker ?? _defaultChecker;

  final NetworkAvailabilityChecker _checker;

  @override
  /// Name used in blocked state reporting.
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
