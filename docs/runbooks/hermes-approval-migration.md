# Hermes Approval Migration

**Delete this file after the Approval Broker, Approved Command Runner, and
Knowledge Base memory checkout pass the live checks below.**

This migration targets `legion-node3`. Do not deploy or delete existing memory
without a separate explicit confirmation.

1. Confirm `/mnt/hermes/worktrees/.publisher-requests` contains no pending
    legacy requests.
2. Merge the Knowledge Base seed containing `memories/hermes/MEMORY.md`,
    `memories/hermes/USER.md`, `.gitignore`, and `AGENTS.md`.
3. Create `/mnt/hermes/worktrees/knowledge-base-memory` from the local
    publisher mirror, switch it to `codex/memory`, and confirm the memory files
    exist.
4. Stop `hermes-agent`.
5. Obtain explicit destructive confirmation, then delete only the old
    `/mnt/hermes/.hermes/memories/MEMORY.md` and `USER.md`.
6. Run `just deploy legion-node3`.
7. Verify the services and timers listed in `hermes.md`.
8. As Hermes and `hermes-command`, create and edit files and Git metadata
    beneath `/mnt/hermes/worktrees`; confirm each identity can modify the
    other's files.
9. Confirm ordinary public GET requests work while private addresses, local
    binding, mutating methods, protected files, and direct Nix daemon access
    fail.
10. Approve a bounded command and a Nix command. Confirm one-shot execution,
    status, cancellation, timeout, 64 KiB output limits, serialization, and the
    500 MiB systemd memory limit.
11. Confirm disallowed service actions fail and an allowed structured action
    succeeds.
12. Publish a test branch and confirm the exact commit appears in a ready PR.
13. Start `hermes-memory-batch`, confirm it creates one approval request, and
    confirm the memory files are visible through Hermes' native memory path.
14. Confirm `restic-backups-hermes.timer` remains active and its latest run
    succeeded.

Delete this file after all checks pass.
