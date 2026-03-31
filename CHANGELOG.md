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
