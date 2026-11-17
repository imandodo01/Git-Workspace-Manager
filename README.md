# Git Workspace Manager (GWM)

A small, portable, Windows-first utility for safely inspecting and synchronizing multiple Git repositories from one configured workspace.

GWM is designed to reduce repetitive repository maintenance without hiding Git state or taking control away from the developer. It updates repositories that are safe to fast-forward and produces a readable report for anything requiring human attention.

## Status

**M1 foundation in progress.** The read-only PowerShell scan, repository inspection module, CMD launcher, fetch safety primitives, and guarded fast-forward executor are available on `feature/m1-foundation`. The executor is not yet connected to the launcher or Scan command. The user has verified the previous 25-test suite on Windows PowerShell 5.1; the latest 35-test suite still requires local verification.

## Goals

- Manage repositories beneath one configurable workspace root.
- Discover repositories or use an explicit local registry.
- Inspect working-tree state, branches, upstreams, and local/remote divergence.
- Fetch remote state and fast-forward only when safe.
- Skip unsafe or ambiguous states rather than attempting automatic repair.
- Produce HTML and JSON reports plus a concise terminal summary.
- Help the developer open repositories requiring attention in VS Code.
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
- VS Code is optional and only needed for the editor integration.

No database, background service, or mandatory external module is planned.

## Quick start (planned)

1. Clone this repository and check out `feature/m1-foundation` while M1 is under review.
2. Copy `config/settings.example.json` to `config/settings.json`.
3. Set `workspace.root` to an existing workspace directory (for example, `E:/Work`).
4. Leave `config/repositories.json` absent to use discovery mode; create it only when you want an explicit repository list.
5. Run `Start-GWM.cmd` or `powershell.exe -NoProfile -File .\\scripts\\GWM.ps1`.
6. Run tests with `Invoke-Pester .\\tests` (Pester 3.4 syntax).

## Safety model

The Scan command is read-only. A separate guarded fast-forward executor is implemented in the PowerShell module but is not yet exposed through the launcher. It fetches the configured remote, checks that the repository is clean and attached, verifies that the upstream belongs to that remote, pins the fetched target SHA, rechecks state, uses FF-only semantics, and verifies the result. Dirty, ahead, diverged, detached, no-upstream, and ambiguous states are not updated. State rechecks reduce but cannot eliminate races with other processes editing or operating on the same repository.

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

MIT. See [LICENSE](LICENSE).
