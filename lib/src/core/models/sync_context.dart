import 'package:meta/meta.dart';

@immutable
class SyncContext {
  const SyncContext({
    this.metadata = const <String, Object?>{},
  });

  final Map<String, Object?> metadata;

  T? value<T>(String key) => metadata[key] as T?;
}
