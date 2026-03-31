import 'package:meta/meta.dart';

@immutable
/// Context passed to task handlers and preconditions during execution.
class SyncContext {
  /// Creates a sync context with optional metadata.
  const SyncContext({this.metadata = const <String, Object?>{}});

  /// Arbitrary execution metadata attached to the current run.
  final Map<String, Object?> metadata;

  /// Reads a typed metadata value by key.
  T? value<T>(String key) => metadata[key] as T?;
}
