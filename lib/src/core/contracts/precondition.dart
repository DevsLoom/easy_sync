import 'package:meta/meta.dart';

import '../models/sync_context.dart';

abstract interface class SyncPrecondition {
  String get name;

  Future<PreconditionResult> check(SyncContext context);
}

@immutable
class PreconditionResult {
  const PreconditionResult._({required this.allow, this.reason});

  factory PreconditionResult.allow() => const PreconditionResult._(allow: true);

  factory PreconditionResult.blocked({String? reason}) =>
      PreconditionResult._(allow: false, reason: reason);

  final bool allow;
  final String? reason;

  bool get blocked => !allow;

  @Deprecated('Use allow instead.')
  bool get isMet => allow;

  @Deprecated('Use blocked instead.')
  bool get isUnmet => blocked;
}

class PredicatePrecondition implements SyncPrecondition {
  PredicatePrecondition({required this.name, required this.predicate});

  @override
  final String name;

  final Future<bool> Function(SyncContext context) predicate;

  @override
  Future<PreconditionResult> check(SyncContext context) async {
    final isMet = await predicate(context);
    if (isMet) {
      return PreconditionResult.allow();
    }
    return PreconditionResult.blocked(reason: '$name is not met');
  }
}

class CompositePrecondition implements SyncPrecondition {
  CompositePrecondition({required this.name, required this.preconditions});

  @override
  final String name;

  final List<SyncPrecondition> preconditions;

  @override
  Future<PreconditionResult> check(SyncContext context) async {
    for (final precondition in preconditions) {
      final result = await precondition.check(context);
      if (result.blocked) {
        return PreconditionResult.blocked(
          reason: result.reason ?? '${precondition.name} is not met',
        );
      }
    }
    return PreconditionResult.allow();
  }
}
