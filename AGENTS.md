# AGENTS.md - OpenClawGateway public-safe handoff

This repository is the public, sanitized operations shell for a personal OpenClaw gateway workflow. Use Simplified Chinese when collaborating with the owner.

## Public Repository Boundary

- Keep this repository free of secrets, tokens, private endpoints, account-specific credentials, raw runtime logs, and complete machine recovery snapshots.
- Do not document exact token storage locations, provider keys, gateway passwords, private model endpoints, or credential-bearing config paths here.
- Full private handoff notes and recovery details belong to the private backup owner. Do not publish its repository coordinate or internal path here.
- If a detail is required for recovery but sensitive in a public repository, record only the owning role here and place the full content in the authorized private store.

## Project Role

`OpenClawGateway` holds public-safe scripts, docs, bootstrap notes, journal entries, and automation helpers for operating the gateway workflow. The public repo should explain intent and safe operating patterns without exposing private infrastructure.

Related local systems may include:

- The gateway runtime and its local configuration.
- Companion coding or automation tools.
- A local WeFlow bridge for message retrieval.
- Scheduled tasks that keep the workflow alive.

Treat specific host paths, account names, provider URLs, credentials, model routing, and scheduler internals as private unless already represented by a sanitized script or document.

## Working Rules

- Before pushing to this public repo, run the project-specific public-content check for token, API key, private key, gateway password, authorization headers, credential JSON patterns, account identifiers, and private handoff coordinates.
- Prefer high-level descriptions in public docs. Put exact recovery steps, credentials, machine-specific topology, and private troubleshooting notes under the private backup owner.
- Avoid `git add .` when the worktree contains generated logs, machine snapshots, screenshots, or exported config.
- If a public document needs to mention a private component, describe its role and link by repository name only.

## GitHub Backup Policy

The owner uses private GitHub repositories as trusted cloud backups for secrets and recovery material. That policy does not apply to this public repository.

- `PRIVATE` repositories may preserve complete backup material when that is the repository purpose.
- `PUBLIC` repositories must remain sanitized.
- Do not repeat secret values in chat responses or public docs, even when the values are backed up privately.

## Private Handoff Boundary

The full machine-specific handoff is intentionally undiscoverable from this PUBLIC repository. Resolve it only through the authorized private backup owner when a recovery task actually requires it.
