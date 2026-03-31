## 0.2.0

### Added

- Function-first task API with `SyncTask.fn(...)` for simpler integrations.
- iOS Background Fetch mode support via `EasySyncBackgroundConfig.iosBackgroundFetch(...)`.
- Android schedule inspection helper `WorkmanagerBackgroundScheduler.isScheduledByUniqueName(...)`.
- Execution controls: rate limiting (`SyncRateLimit`) and circuit breaker (`SyncCircuitBreaker`).
- Engine and background-bridge support for rate limit and circuit breaker runtime behavior.
- Expanded tests for background behavior, execution controls, and setup propagation.
- Documentation updates for iOS mode choices and execution controls.

## 0.1.0

Initial public release.

### Added

- Core sync orchestration with trigger-aware task policies.
- Manual, app-open, and background sync flows.
- Retry support with configurable exponential backoff.
- Preconditions for network and app-defined readiness checks.
- Task state tracking and stream updates.
- Workmanager adapter for background dispatch integration.
- Safe execution options including timeout and task-failure isolation.

### Notes

- easy_sync is auth-agnostic, backend-agnostic, and database-agnostic.
- iOS background execution timing is best-effort and not guaranteed.
