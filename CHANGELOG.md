# Changelog

All notable changes to Git Workspace Manager (GWM) are documented here.

The format follows Keep a Changelog conventions. Versions will use Semantic Versioning once releases begin.

## [Unreleased]

### Added
- Initial product specification and acceptance criteria.
- Initial architecture and synchronization safety policy.
- Configuration templates and portability guidance.
- Test plan, security guidance, and agent instructions.
- Recorded future integration possibility with DevEnv Manager; no current dependency.

## Unreleased — M1 command integration

- Added explicit -Mode Sync command path while keeping Scan as the default local-only, read-only mode.
- Added separate JSON reports for Scan and Sync, per-repository status output, and Sync exit codes.
- Added command-level tests for offline Scan, guarded Sync, and dirty-work preservation.
- Added Sync command failure exit-code coverage for failed fetches.
- Classified detached and no-upstream branches before fetch so missing remotes do not mask the actionable NEEDS_ATTENTION state.
- Added executor and CLI regression coverage for no-upstream repositories when origin is absent.
