/// Source that initiated a sync run.
enum SyncTrigger {
  /// Triggered when the app is opened or resumed.
  appOpen,

  /// Triggered by direct application code or user interaction.
  manual,

  /// Triggered from background execution infrastructure.
  background,

  /// Triggered as a scheduled retry after failure.
  retry,
}
