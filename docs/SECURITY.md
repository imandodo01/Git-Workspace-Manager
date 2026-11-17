# Security and Privacy

## 1. Local-first design

GWM runs locally and invokes the installed Git CLI. It does not require a server, cloud account, database, or external API.

## 2. Credentials

- Git authentication remains the responsibility of Git Credential Manager, SSH agent, or the user's existing Git setup.
- Never ask users to paste tokens or passwords into GWM configuration.
- Never log environment variables, credential helper output, private keys, or full remote URLs if they may contain credentials.
- Redact URL user-info and other known credential patterns before reporting remotes.
- Do not change credential helpers or authentication configuration.

## 3. Process invocation

- Invoke Git with safely separated arguments rather than concatenating untrusted strings into a shell command.
- Treat repository paths, branch names, remote names, and Git output as untrusted data.
- Validate paths and enforce the configured workspace boundary.
- Do not execute commands or scripts discovered inside managed repositories.

## 4. HTML and JSON reports

- HTML-encode all Git- and filesystem-derived values before rendering.
- Do not include remote scripts, external stylesheets, analytics, or active content.
- Write reports as local files with ordinary user permissions.
- Ensure JSON serialization is standards-compliant.
- Avoid collecting file contents; report paths and status metadata only.

## 5. Logs and data minimization

- Store local logs and reports under the GWM directory by default.
- Ignore local configuration, reports, and logs in Git.
- Do not record file contents, secrets, or unnecessary personal metadata.
- Document retention and provide a way to disable or limit history.

## 6. Operational safety

GWM must not perform destructive Git operations or rewrite history. A failed or ambiguous state results in a report and manual intervention, not an attempted repair.
