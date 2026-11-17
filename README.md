# Git Workspace Manager (GWM)

A small, portable, Windows-first utility for safely inspecting and synchronizing multiple Git repositories from one configured workspace.

GWM is designed to reduce repetitive repository maintenance without hiding Git state or taking control away from the developer. It updates repositories that are safe to fast-forward and produces a readable report for anything requiring human attention.

## Status

**Planning / M0 foundation.** This repository currently contains the project specification and engineering policies. The implementation has not started.

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
- Automatically committing, pushing, rebasing, merging, stashing, resetting, cleaning, or deleting user work.
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

1. Clone this repository.
2. Copy `config/settings.example.json` to `config/settings.json`.
3. Copy `config/repositories.example.json` to `config/repositories.json`, or use discovery mode.
4. Set the workspace root in local settings.
5. Run `Start-GWM.cmd` or `scripts/GWM.ps1`.

The launcher and runtime scripts will be added in a later implementation milestone.

## Safety model

GWM inspects before it acts. It may fetch remote metadata, but it only performs a pull-equivalent fast-forward when the repository is clean, on a valid local branch with a configured upstream, and the local branch is strictly behind the upstream. Diverged, dirty, detached, untracked-sensitive, or otherwise ambiguous states are reported for manual review. GWM never resets or overwrites local work.

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
