# Product Specification

## 1. Summary

Git Workspace Manager (GWM) is a portable Windows utility that scans a configured workspace containing multiple Git repositories, safely synchronizes repositories that can be updated without merging, and produces actionable reports for repositories requiring developer intervention.

## 2. Problem

Developers working across office and home machines may maintain many repositories. Repeating status checks and pulls repository by repository is tedious, while blindly running pulls across every directory can create confusing merge states or risk local work.

GWM centralizes the inspection and safe-update workflow while leaving conflict resolution and development decisions with the developer.

## 3. Goals

1. One command or double-click starts a local Scan; synchronization requires an explicit Sync mode.
2. All repositories in the configured workspace are considered consistently.
3. Local changes are preserved.
4. Safe updates use fast-forward-only semantics.
5. Repositories that need attention are explained in a readable report.
6. The tool is portable and configurable without editing source code.
7. A run produces structured results suitable for later automation.

## 4. Target users and platform

- Initial user: an individual developer maintaining repositories across Windows machines.
- Initial platform: Windows 10/11.
- Shell: Windows PowerShell 5.1 minimum target; PowerShell 7 compatibility desired.
- Git: Git for Windows, available through PATH.
- Editor: Visual Studio Code, optional.

## 5. Core workflow

Scan mode loads and validates configuration, discovers repositories, inspects local state against cached upstream refs, and writes a JSON report. It does not fetch or change repositories.

Sync mode loads and validates configuration, discovers repositories, and captures local state. Invalid repositories, detached HEAD, and branches without an upstream are classified before any fetch; the latter two require human attention and do not contact the configured remote. For the remaining repositories, Sync fetches only the configured remote, rechecks state, fast-forwards eligible repositories, verifies the result, and writes a separate JSON report. Sync is never the default mode.

## 6. Functional requirements

### FR-01 Configuration
- Read settings from a local JSON file.
- Read an optional explicit repository registry.
- Validate required values and report actionable configuration errors.
- Provide example templates that can be committed; local configuration is ignored by Git.

### FR-02 Repository discovery
- Support one configured workspace root.
- Support configurable recursive discovery.
- Do not traverse into a repository's internal directories or Git metadata.
- Support explicit include/exclude entries where needed.
- Avoid duplicate repository registration.
- Treat nested Git repositories and submodules deliberately; do not silently treat a submodule as an independent workspace repository unless configured.

### FR-03 Inspection
For each repository, capture as available:
- Repository path and display name.
- Current branch or detached-HEAD state.
- Remote and upstream tracking branch.
- Working-tree state, including staged, unstaged, and untracked files.
- Local and remote commit identifiers.
- Ahead and behind counts.
- Fetch result and synchronization result.
- Actionable reason when skipped or failed.

### FR-04 Synchronization
- Fetch remote state before deciding whether an update is possible.
- Never synchronize a dirty working tree.
- Never synchronize detached HEAD or a branch without an unambiguous upstream.
- Never automatically merge, rebase, reset, clean, stash, commit, push, or delete.
- Use fast-forward-only behavior.
- A repository-level failure must not prevent independent repositories from being processed.

### FR-05 Reporting
- Produce a concise terminal summary.
- Produce a self-contained HTML report.
- Produce a machine-readable JSON report.
- Include timestamp, duration, repository counts, per-repository status, branch/upstream, divergence counts, changed-file summary, and recommended next action.
- Escape untrusted values in HTML.
- Redact credential-bearing remote URL components.
- Retain report history according to configuration.

### FR-06 Editor integration
- Detect VS Code CLI availability.
- Provide a safe way to open an affected repository.
- Do not automatically open many windows without explicit user choice or configuration.

### FR-07 Execution modes
Initial implemented modes:
- **Scan (default):** inspect local state against cached upstream refs; no fetch and no working-tree mutation.
- **Sync (explicit):** fetch the configured remote and fast-forward eligible repositories only.

Report-only and selective modes remain future work. Command-line syntax: -Mode Scan or -Mode Sync.

## 7. Non-functional requirements

- Safety and data preservation take precedence over synchronization coverage.
- Deterministic behavior and explicit statuses.
- Readable code and actionable errors.
- No mandatory database, service, network API, or third-party PowerShell module.
- Reasonable performance for dozens of repositories.
- Portable configuration and no machine-specific paths in tracked files.
- Logs must not contain secrets.

## 8. Status model

Initial report statuses:
- UPDATED
- UP_TO_DATE
- NEEDS_ATTENTION
- SKIPPED
- FAILED
- SCAN_ONLY

A status must include a reason and, where practical, a recommended action. The implementation must define precedence where multiple conditions apply.

## 9. Acceptance criteria

- A clean repository behind its upstream by one or more commits is fast-forwarded.
- An up-to-date repository remains unchanged.
- A repository with staged, unstaged, or untracked changes is not pulled.
- A diverged repository is not merged or rebased and is clearly reported.
- A branch without upstream and detached HEAD are safely skipped.
- A fetch failure is reported without aborting other repositories.
- A non-fast-forward update is rejected.
- HTML output safely encodes repository names, paths, branch names, and Git-provided text.
- JSON output is valid and contains stable fields.
- Local settings, repository registry, reports, and logs are not committed.
- Integration tests use disposable repositories and verify that local commits and working-tree changes are preserved.

## 10. Out of scope

- Cross-platform support beyond Windows.
- GUI desktop application.
- Conflict resolution UI.
- Cloud synchronization or remote orchestration.
- Automatic push or commit.
- Credential management.
- DevEnv Manager integration in the initial release.

## 11. Future consideration: DevEnv Manager

GWM remains independent for the foreseeable scope. A future integration or consolidation with DevEnv Manager may be evaluated after both tools have stable boundaries and real usage. Any proposal must compare user value, coupling, maintenance cost, deployment complexity, and backward compatibility. This is a recorded possibility, not a current commitment or dependency.
