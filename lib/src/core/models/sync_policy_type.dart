/// High-level policy buckets used when selecting task execution mode.
enum SyncPolicyType {
  /// App-open triggered execution.
  appOpen,

  /// Manually-triggered execution.
  manual,

  /// Background-triggered execution.
  background,
}
