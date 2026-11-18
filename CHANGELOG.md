# Changelog

All notable changes to Git Workspace Manager (GWM) are documented here.

The format follows Keep a Changelog conventions. Versions will use Semantic Versioning once releases begin.

## [Unreleased]

### Added
- Added a shared versioned Scan/Sync report envelope and a standalone HTML renderer module. HTML output is not yet wired into the CLI; M2-B verification is pending.

### Planned
- M2 reporting and observability: shared versioned report contract, self-contained HTML, report history/retention, and safe local run logs.
- M3 workflow and usability: selective repository operations, clearer setup/configuration validation, and optional VS Code actions.
- M4 release hardening: PowerShell compatibility, performance, CI, security review, and v1.0 release preparation.

## M1 — Foundation (merged)

- Added explicit -Mode Sync command path while keeping Scan as the default local-only, read-only mode.
- Added separate JSON reports for Scan and Sync, per-repository status output, and Sync exit codes.
- Added guarded fast-forward execution, exact fetched-target pinning, state rechecks, and post-update verification.
- Added disposable local Git integration tests and safety regression coverage.
- Classified detached and no-upstream branches before fetch so missing remotes do not mask the actionable NEEDS_ATTENTION state.
- User confirmed all 41 tests pass on Windows PowerShell 5.1 with Pester 3.4.0.
- Merged to main in commit d47379c7a8b51e8cdb6a76042eb3549864ecb620.
