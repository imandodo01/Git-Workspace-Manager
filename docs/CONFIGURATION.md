# Configuration

## 1. Files

The repository contains templates only:
- `config/settings.example.json`
- `config/repositories.example.json`

The user creates local copies:
- `config/settings.json`
- `config/repositories.json`

Local files are ignored by Git and must never be committed. GWM should explain how to create them when missing.

## 2. Settings

The initial settings schema is documented by the example file. It covers:
- Workspace root.
- Recursive discovery and excluded directories.
- Default remote and synchronization strategy.
- Report formats and retention.
- Log retention.
- VS Code integration.
- Execution defaults.

All paths must be normalized and validated. Prefer paths relative to the GWM directory only where that behavior is explicit; the workspace root may be absolute. Do not silently guess a workspace location.

## 3. Repository registry

The registry may explicitly include repositories by path and optionally override the default remote or enable/disable synchronization per repository. A repository registry entry must not contain credentials.

The first implementation may support either explicit registry mode or discovery mode. If both are supported, define deterministic precedence and duplicate handling.

## 4. Defaults and validation

- Invalid JSON is a configuration error; do not silently replace it.
- Missing local configuration may be initialized from examples only with clear user feedback, or the tool may provide a documented setup command.
- The configured workspace root must exist and be a directory before scanning.
- Reject paths outside the workspace root unless a later, explicit requirement changes the single-workspace boundary.
- Reject unsupported sync strategies rather than silently falling back.
- Never store Git credentials, access tokens, private keys, or passwords in configuration.

## 5. Example configuration

See the JSON templates in `config/`. Their values are illustrative and must not contain personal machine paths.
