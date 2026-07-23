# Hermes Operations

Hermes normally works inside `/mnt/hermes/worktrees`. Codex gives it write
access there, including Git metadata, and read-only HTTP access to public
Internet addresses. Private, loopback, link-local, metadata, local binding,
mutating HTTP methods, and the Nix daemon socket are blocked.

Hermes and the Approved Command Runner share the `hermes-workspace` ACL. Files
and directories created by either identity remain writable by both. The runner
has no credentials, executes one command at a time, is limited to 500 MiB and
one CPU, and retains at most 64 KiB from each output stream. Nix and devenv
commands require approval because only the runner can reach the Nix daemon;
daemon-side downloads are outside the runner's public-network and memory
limits.

## Approval requests

Use the helper instead of writing request JSON:

```sh
hermes-request command --cwd cornn-flaek --timeout 600 \
  --reason 'validate the requested NixOS change' 'just check'

hermes-request service restart hermes-agent.service \
  --reason 'load the approved agent configuration'

hermes-request publication \
  --source cornn-flaek \
  --branch codex/example \
  --commit 0123456789abcdef0123456789abcdef01234567 \
  --title 'feat(hermes): example' \
  --body 'Requested Hermes change.' \
  --reason 'publish the reviewed branch'
```

The Approval Broker sends the exact command, working directory, timeout,
reason, and request hash to the authorized Telegram DM. Approve or reject it
once:

```text
/approve cmd-<id>
/reject cmd-<id>
/status cmd-<id>
/cancel cmd-<id>
```

Hermes can also use `hermes-request status`, `wait`, or `cancel`. Cancellation
sends `SIGTERM` to the command process group and `SIGKILL` after five seconds.
Results are durable for 30 days. A dispatcher restart after claiming a service
request marks it uncertain instead of risking a second execution.

Allowed service actions are:

| Unit | Actions |
| --- | --- |
| `hermes-agent.service` | start, stop, restart |
| `hermes-approval-broker.service` | restart |
| `hermes-snapshot-aggregate.service` | start |
| `hermes-memory-batch.service` | start |
| `restic-backups-hermes.service` | start |
| Their timer units | start, stop, restart |

State initialization, daemon reload, enable/disable, arbitrary units, and root
shell commands are never accepted. `status` is allowed for every listed unit
and is dispatched without an approval prompt because it is read-only.

## Publication

Publication sources are fixed by NixOS policy:

| Source | Repository | Worktree |
| --- | --- | --- |
| `cornn-flaek` | `jeiang/.dotfiles` | `cornn-flaek` |
| `knowledge-base` | `jeiang/knowledge-base` | `knowledge-base` |
| `knowledge-base-memory` | `jeiang/knowledge-base` | `knowledge-base-memory` |

The broker accepts only a `codex/` branch and an exact 40-hex commit. It imports
that branch into its private mirror, verifies the tip again on approval, and
pushes only the pinned commit. It creates a ready PR, marks an existing matching
draft ready, or updates an existing ready PR. Hermes and the command runner
have no GitHub credential or `gh`.

Mirrors under `/mnt/hermes/mirrors` refresh on broker startup and publication
review. Restart `hermes-approval-broker` through an approved service request to
force a refresh.

## Knowledge and memory

General knowledge is written only when the user explicitly requests or directs
it. Hermes chooses and evolves subject folders during that work. A structural
reorganization uses a dedicated PR and must validate internal Markdown links.

Native memory lives at
`knowledge-base-memory/memories/hermes/{MEMORY.md,USER.md}`. Systemd binds that
directory over Hermes' native memory directory. Hermes updates the files
automatically. At 04:00 UTC, `hermes-memory-batch` stages only those two files,
commits them on `codex/memory`, and creates one publication approval request.
Newer changes remain dirty while a request is pending.

## Health and recovery

Check:

```sh
systemctl status \
  hermes-agent \
  hermes-approval-broker \
  hermes-approval-dispatcher \
  hermes-command-runner \
  hermes-snapshot-aggregate.timer \
  hermes-memory-batch.timer \
  restic-backups-hermes.timer

systemctl list-timers hermes-memory-batch.timer hermes-snapshot-aggregate.timer
```

Confirm `/mnt/hermes/reports/current.json` has a recent `collected_at`. Restore
the Hermes Backup Set with `restore.md` into a temporary directory, never over
live state.
