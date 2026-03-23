# Security Policy

## Reporting Vulnerabilities

If you discover a security vulnerability, please report it by emailing **hello@augent.app**. Do not open a public issue.

Please include as much detail as possible:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We aim to respond to security reports within **48 hours**.

## Scope

The following components are in scope for security reports:

- `setup.sh` — installer script
- `uninstall.sh` — uninstaller script
- Hook scripts (`src/hooks/`)
- Swift source code (`src/`)

## Privacy Commitment

This project is built with a strict privacy-first approach:

- **No data collection** — we do not collect any user data
- **No telemetry** — no usage metrics, crash reports, or analytics are sent anywhere
- **No analytics** — no tracking of any kind
- **No network traffic beyond localhost:27124** — the only network communication is between the hooks and Obsidian's Local REST API on your own machine
- **Fully auditable** — all source code is available in this repository

## Code Audit

We encourage users to audit the source code before installing. The `setup.sh` installer is intentionally written to be straightforward and readable so you can verify exactly what it does before running it.
