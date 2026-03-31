import 'package:meta/meta.dart';

import '../models/sync_context.dart';

/// A gate that decides whether a sync task is allowed to run.
abstract interface class SyncPrecondition {
  /// Human-readable name used in logs and blocked-state messages.
  String get name;

  /// Evaluates the precondition against the provided sync context.
  Future<PreconditionResult> check(SyncContext context);
}

@immutable
/// Result of evaluating a [SyncPrecondition].
class PreconditionResult {
  /// Internal constructor used by the factory helpers.
  const PreconditionResult._({required this.allow, this.reason});

  /// Creates a result that allows the task to continue.
  factory PreconditionResult.allow() => const PreconditionResult._(allow: true);

  /// Creates a result that blocks task execution.
  factory PreconditionResult.blocked({String? reason}) =>
      PreconditionResult._(allow: false, reason: reason);

  /// Whether execution is allowed.
  final bool allow;

  /// Optional explanation for why execution was blocked.
  final String? reason;

  /// Whether execution is blocked.
  bool get blocked => !allow;

  @Deprecated('Use allow instead.')
  /// Deprecated alias for [allow].
  bool get isMet => allow;

  @Deprecated('Use blocked instead.')
  /// Deprecated alias for [blocked].
  bool get isUnmet => blocked;
}

/// A precondition backed by an async boolean predicate.
class PredicatePrecondition implements SyncPrecondition {
  /// Creates a predicate-backed precondition.
  PredicatePrecondition({required this.name, required this.predicate});

  @override
  /// The display name of this precondition.
  final String name;

  /// The async predicate used to evaluate readiness.
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

/// A precondition that combines multiple child preconditions.
class CompositePrecondition implements SyncPrecondition {
  /// Creates a composite precondition.
  CompositePrecondition({required this.name, required this.preconditions});

  @override
  /// The display name of this precondition group.
  final String name;

  /// Child preconditions evaluated in order.
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
