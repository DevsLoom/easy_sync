import 'package:meta/meta.dart';

import '../models/sync_context.dart';

abstract interface class SyncPrecondition {
  String get name;

  Future<PreconditionResult> evaluate(SyncContext context);
}

@immutable
class PreconditionResult {
  const PreconditionResult._({required this.isMet, this.reason});

  factory PreconditionResult.met() => const PreconditionResult._(isMet: true);

  factory PreconditionResult.unmet({String? reason}) =>
      PreconditionResult._(isMet: false, reason: reason);

  final bool isMet;
  final String? reason;
}

class PredicatePrecondition implements SyncPrecondition {
  PredicatePrecondition({required this.name, required this.predicate});

  @override
  final String name;

  final Future<bool> Function(SyncContext context) predicate;

  @override
  Future<PreconditionResult> evaluate(SyncContext context) async {
    final isMet = await predicate(context);
    if (isMet) {
      return PreconditionResult.met();
    }
    return PreconditionResult.unmet(reason: '$name is not met');
  }
}

class CompositePrecondition implements SyncPrecondition {
  CompositePrecondition({required this.name, required this.preconditions});

  @override
  final String name;

  final List<SyncPrecondition> preconditions;

  @override
  Future<PreconditionResult> evaluate(SyncContext context) async {
    for (final precondition in preconditions) {
      final result = await precondition.evaluate(context);
      if (!result.isMet) {
        return PreconditionResult.unmet(
          reason: result.reason ?? '${precondition.name} is not met',
        );
      }
    }
    return PreconditionResult.met();
  }
}
