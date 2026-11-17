# Architecture Decision Records

This document records decisions that shape the initial scope. It is intentionally lightweight; use a separate ADR only when a decision needs substantial context or alternatives.

## D-001: Keep GWM independent from DevEnv Manager

- **Status:** Accepted
- **Decision:** GWM is a separate repository, application, test suite, and release unit.
- **Context:** DevEnv Manager has a broader environment-management scope. Combining the projects now would increase coupling and implementation cost before either boundary is proven through use.
- **Consequences:** GWM remains focused on multi-repository inspection, safe synchronization, and reporting. Future integration or consolidation may be evaluated after both projects mature, based on user value, coupling, maintenance cost, deployment complexity, and backward compatibility. This is a possibility, not a commitment.

## D-002: Windows-first PowerShell implementation

- **Status:** Accepted
- **Decision:** Use PowerShell and the installed Git CLI, targeting Windows PowerShell 5.1 compatibility and PowerShell 7 where practical.
- **Context:** The initial use case is a Windows home/office development workflow. A GUI, database, service, and third-party runtime dependencies are unnecessary for the first release.
- **Consequences:** Keep modules small, invoke Git safely with separated arguments, and test on disposable local repositories.

## D-003: One configurable workspace root

- **Status:** Accepted
- **Decision:** GWM manages repositories beneath one configured workspace root. Repository paths and machine-specific settings are local configuration, not source-controlled data.
- **Context:** The desired user experience is one place to manage the workspace and a portable public repository that can be configured on another machine.
- **Consequences:** Discovery and explicit registry entries must respect the configured workspace boundary. Support for arbitrary scattered repository paths is out of scope unless a later requirement justifies changing this model.

## D-004: Human-led conflict resolution

- **Status:** Accepted
- **Decision:** GWM detects and explains conditions requiring attention; the developer resolves them using VS Code or Git directly.
- **Context:** Git and VS Code already provide conflict-resolution tools. Building a second resolver would add complexity and risk.
- **Consequences:** Reports must provide enough state and actionable guidance. GWM never attempts automatic merge, rebase, reset, stash, or conflict resolution.

## D-005: Fast-forward-only synchronization

- **Status:** Accepted
- **Decision:** GWM only advances a clean local branch when it is strictly behind its configured upstream and can be fast-forwarded.
- **Context:** The utility must preserve local work and avoid introducing unexpected merge commits.
- **Consequences:** Dirty, detached, untracked, ahead, diverged, or ambiguous repositories are reported without updating the working branch. Fast-forward-only behavior is the final safety guard.
