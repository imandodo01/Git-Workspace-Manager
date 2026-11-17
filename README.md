# Git Workspace Manager (GWM)

A small, portable, Windows-first utility for safely inspecting and synchronizing multiple Git repositories from one configured workspace.

GWM reduces repetitive repository maintenance without hiding Git state or taking control away from the developer. It updates repositories that are safe to fast-forward and produces a readable report for anything requiring human attention.

## Status

**M1 foundation in progress.** The local-only Scan command and explicit Sync command are available on feature/m1-foundation. Sync uses the guarded fast-forward executor; it is never the default mode. The user verified 35/35 tests on Windows PowerShell 5.1 with Pester 3.4.0 before command integration. The current 39-test suite still requires local verification.

## Goals

- Manage repositories beneath one configurable workspace root.
- Discover repositories or use an explicit local registry.
- Inspect working-tree state, branches, upstreams, and local/remote divergence.
- Keep Scan offline and read-only.
- Fetch and fast-forward only when explicitly running Sync and all safety checks pass.
- Skip unsafe or ambiguous states rather than attempting automatic repair.
- Produce JSON reports and a concise terminal summary.
- Keep configuration, reports, and logs local to the user's machine.

## Non-goals

- Replacing Git or VS Code.
- Automatically resolving merge conflicts.
- Automatically committing, pushing, creating merge commits, resolving conflicts, rebasing, stashing, resetting, cleaning, or deleting user work.
- Managing credentials or changing Git authentication.
- Becoming a general development-environment manager.
- Integrating with DevEnv Manager in the initial scope.

## Requirements

- Windows 10/11 (initial target).
- Git for Windows available on PATH.
- PowerShell 5.1 minimum target; PowerShell 7 compatibility is desired.
- No database, background service, or mandatory external module.

## Quick start

1. Clone this repository and check out feature/m1-foundation while M1 is under review.
2. Copy config/settings.example.json to config/settings.json.
3. Set workspace.root to an existing workspace directory (for example, E:/Work).
4. Leave config/repositories.json absent to use discovery mode; create it only when you want an explicit repository list.
5. Run a local-only scan:

   ~~~powershell
   .\Start-GWM.cmd
   ~~~

6. When ready to update eligible repositories, explicitly run:

   ~~~powershell
   .\Start-GWM.cmd -Mode Sync
   ~~~

7. Run tests with Invoke-Pester .\tests (Pester 3.4 syntax).

Scan is the default and does not fetch or change repositories. It compares local branches with the currently cached upstream tracking refs, so its result can be stale until a Sync fetch occurs. Sync fetches the configured remote and fast-forwards only eligible repositories.

## Safety model

- Scan is offline and read-only.
- Sync is an explicit opt-in command; there is no automatic or background synchronization.
- Dirty, ahead, diverged, detached, no-upstream, and ambiguous states are not updated.
- Fast-forward uses the exact fetched target SHA, rechecks state, and verifies the result.
- A repository failure does not stop independent repositories.
- Sync writes reports/latest-sync.json; Scan writes reports/latest-scan.json.
- Sync exits with code 0 when all repositories are updated or already current, 1 when at least one needs attention, and 2 when at least one repository fails.

See:
- [Specification](docs/SPECIFICATION.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Synchronization policy](docs/SYNC-POLICY.md)
- [Configuration](docs/CONFIGURATION.md)
- [Test plan](docs/TEST-PLAN.md)
- [Security](docs/SECURITY.md)

## Relationship to DevEnv Manager

GWM is an independent project with its own scope, implementation, tests, and release lifecycle. Future integration with DevEnv Manager may be evaluated if both projects mature and a clear benefit justifies the additional complexity. No shared runtime or code dependency is planned now.

## License

MIT. See LICENSE.
