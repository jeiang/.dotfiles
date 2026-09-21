# Runbook: Hermes

Operator runbook for the Hermes assistant (`modules/hermes/`, `modules/llm-server/`),
hosted on `artemis`. Review [`AGENTS.md`](../../AGENTS.md) before running any
command here.

## Topology

- **artemis** runs both halves natively as systemd services: `llm-server.service`
  (`modules/llm-server`, Qwen3.6-35B-A3B over ROCm, loopback `127.0.0.1:8080`)
  and `hermes-agent.service` (`modules/hermes`, the upstream `hermes-agent`
  NixOS module), which talks to that model as its only provider. Jev
  (TypeSafe System One) runs in code in front of Hermes — `modules/hermes/jev/`
  — never as a tool the agent itself picks.
- **legion-node1**..**legion-node4** are operational targets, not a Hermes
  host: Hermes reaches them over NetBird mesh SSH as the `hermes-ops` user
  (`modules/hermes-ops.nix`), under a per-node sudoers allowlist. artemis has
  no route to Hetzner's private `172.17.0.0/24`, so every hop rides the mesh.
- Hermes talks to Aidan over Telegram, and has a webhook adapter
  (`platforms.webhook`, bound to artemis's NetBird address, HMAC-signed) that
  Jev's mail and alert scripts post pre-built messages to.

## First-time setup

Do these in order; later steps depend on earlier ones.

### 1. Mint the secrets

`just sops-edit modules/hermes/secrets.yaml` edits `hermes.env` (a
dotenv-style blob) and `hermes.ssh-key`. Every key `hermes.env` needs, and
where it comes from:

| Key | Source |
| --- | --- |
| `TELEGRAM_BOT_TOKEN` | BotFather |
| `TELEGRAM_ALLOWED_USERS` | Aidan's Telegram numeric user ID(s) |
| `GITHUB_TOKEN` | a PAT with contents/PR access to `jeiang/knowledge-base`, used by `hermes-kb-export` via `gh auth git-credential` |
| `WEBHOOK_SECRET` | a random string you mint — must be this exact env var name, not `HERMES_WEBHOOK_SECRET` (the upstream gateway only merges `WEBHOOK_SECRET`) |
| `BRAVE_SEARCH_API_KEY` | a free-plan key from the Brave Search API dashboard |
| `GROQ_API_KEY` | a free-tier key from the Groq console, used for voice-note transcription |
| `ICLOUD_MAIL_USERNAME` | the bare iCloud short name (before `@icloud.com`) — iCloud IMAP auth takes the short name, not a full address |
| `ICLOUD_APP_PASSWORD` | an app-specific password from the Apple ID account page, shared by himalaya (mail) and vdirsyncer (calendar/contacts) |
| `TYPESAFE_API_KEY` | the TypeSafe System One key; every Jev integration (mail triage, alert triage, memory gate) calls this |
| `JEV_ALERT_TOKEN` | optional — a bearer token for `jev-alert-triage`'s listener. Without it, the listener falls back to a source-IP allowlist against `legion-node3`'s NetBird address; wiring the token into Alertmanager's `http_config` is a separate, currently unfinished step |

The CalDAV/CardDAV/mail *display* identity (`aidan@aidanpinard.co`) is a
literal in `modules/hermes/default.nix`, not a secret — only the mail
IMAP login (`ICLOUD_MAIL_USERNAME`) and the shared app password are secret.

### 2. Generate the hermes-ops keypair

```sh
nix shell nixpkgs#openssh -c ssh-keygen -t ed25519 -N "" -f /tmp/hermes-ops-key -C hermes-ops
```

- Private half: `just sops-edit modules/hermes/secrets.yaml`, set
  `hermes.ssh-key` to the file's contents.
- Public half: replace `REPLACE_ME` in `flake.lib.hermesOpsPublicKey`
  (`modules/hermes/default.nix`) with it. `modules/hermes-ops.nix` reads that
  one literal for every Legion node's `hermes-ops` `authorized_keys`, so this
  is the only place to edit.
- Delete `/tmp/hermes-ops-key*` once both halves are copied in.

### 3. Persist and deploy

`/var/lib/hermes` and `/var/cache/bonsai-models` are `persistence.directories`
entries on artemis (`modules/hosts/artemis/default.nix`) — the model weights
and Hermes' own state (memory, `.ssh`, the Jev mail database) all live there.
Before the first deploy of this stack, or any later change to those
persistence entries:

```sh
just migrate-persist <checkout>   # on artemis, as root
```

then deploy with `--boot` and reboot artemis (a live switch cannot adopt a
new persisted bind mount). After that, and after Legion has the
`hermes-ops` sudoers rules (`just deploy-legion --remote-build`), a normal
`just deploy artemis --skip-checks --remote-build` brings both services up.
First start of `llm-server-fetch.service` downloads and checksums ~22 GB of
weights before `llm-server.service` can answer.

### 4. First checks

```sh
just llm-status
```

confirms the model server is up and healthy before Hermes' own start depends
on it.

```sh
ssh artemis.jeiang.vpn systemctl start hermes-vdirsyncer-sync.service
ssh artemis.jeiang.vpn journalctl -u hermes-vdirsyncer-sync.service -e
```

runs the first calendar/contacts sync by hand: its `discover` step feeds a
bounded non-interactive `y` stream to accept each new remote collection, and
this is the one path in that flow not yet exercised against a live account.

Message the Telegram bot and confirm a reply — the smoke test for the
`TELEGRAM_BOT_TOKEN`/`TELEGRAM_ALLOWED_USERS` pair and the model connection
together. `ssh artemis.jeiang.vpn journalctl -u hermes-agent.service -e` if
nothing comes back.

Only once himalaya mail (the account above) is confirmed working should
`jev-mail-triage.timer` be trusted: it runs unconditionally every 15 minutes
once `hermes-agent` is deployed, and a broken himalaya config makes every run
a silent no-op (see Troubleshooting). Verify a manual run first:

```sh
ssh artemis.jeiang.vpn sudo -u hermes systemctl start jev-mail-triage.service
ssh artemis.jeiang.vpn journalctl -u jev-mail-triage.service -e
```

## Daily operations

- `just llm-stop` / `just llm-start` / `just llm-status` — the manual
  counterpart of the gamemode hooks (`modules/gaming.nix`) that free the
  dGPU for a game. Gamemode's `custom.start`/`custom.end` hooks only fire for
  a game actually launched under gamemode (Steam, Heroic); anything else
  needs a manual `just llm-stop` first.
- **Jev decision logs** — each script logs one line per judgment:
  `jev-mail: <id> bucket=... needs_reply=... importance=... dest=...(confidence)`,
  `jev-alert: <alertname> action=... restart_fixable=... blast_radius=...`.
  Read them with `ssh artemis.jeiang.vpn journalctl -u jev-mail-triage -u jev-alert-triage -u jev-alert-digest -e`.
- **The mail decision database** — `jev-mail-triage` keeps
  `$HERMES_HOME/jev-mail.db` (`/var/lib/hermes/.hermes/jev-mail.db`), an
  idempotency and history store, not a queue: `decisions` (one row per
  triaged message), `folder_history` (per-sender-domain move counts, what
  `destination_folder` reasons from), `meta` (the one-time seed flag).

  ```sh
  ssh artemis.jeiang.vpn sudo -u hermes sqlite3 /var/lib/hermes/.hermes/jev-mail.db \
    'select subject, bucket, importance, folder from decisions order by ts desc limit 20;'
  ```
- **Tuning the three thresholds** — each is a literal in its script, so
  changing one is a PR and a redeploy, not a runtime setting:
  `DEST_CONFIDENCE_THRESHOLD` (`jev_mail_triage.py`, raise to move fewer
  messages, lower to move more), `DURABLE_THRESHOLD` (`jev_memory_gate.py`,
  raise to keep less in memory), `CONTRADICTION_THRESHOLD`
  (`jev_memory_gate.py`, lower to bounce back more candidate writes).
- **Moving a unit between tiers** — edit `tier1Services` (whole service,
  every one of its units) or `tier1PickedUnits` (a single unit basename)
  in `modules/hermes-ops.nix`, then redeploy the node
  that owns it *and* artemis: `flake.lib.hermesOpsCommands` feeds both the
  node's sudoers rules and the approval gate's allowlist. A unit that is not
  tier 1 is tier 2 automatically — there is no second list to edit.
  `SERVERS.md`'s per-node tables are a snapshot of the result, not
  hand-maintained.
- **Approving a tier-2 command** — Hermes runs the command like any other;
  `modules/hermes/tier2` intercepts it and Hermes' own approval gate sends
  Aidan a Telegram prompt with the command and Allow Once / Allow Session /
  Always Allow / Deny buttons. Only Telegram users in
  `TELEGRAM_ALLOWED_USERS` can press them. Every button behaves as *once*:
  the gate mints a fresh approval key per invocation, so the next identical
  command asks again. Deny, an unanswered prompt (`approvals.timeout`, 300s)
  and any Jev webhook or cron turn (`unattended_mode`/`cron_mode: deny`) all
  mean the command did not run.
- **After deploying a tier change, confirm the gate loaded** — the Legion
  sudoers rules permit every tier-2 command outright; the approval prompt is
  the only thing in front of them, and it comes from a plugin that discovery
  can skip (a plugin whose name has drifted from `plugins.enabled` is simply
  not loaded, with a debug line and nothing else). `ssh artemis.jeiang.vpn
  sudo -u hermes hermes plugins list` must show `hermes-ops-tier2` enabled;
  `journalctl -u hermes-agent -g 'not in plugins.enabled'` shows it when it
  is not.
- **When a tier-2 command runs unasked** — `/yolo` in a Telegram session,
  and `approvals.mode: off`, bypass the approval layer for that session. The
  sudoers allowlist still bounds what can run; nothing outside tier 1 or
  tier 2 becomes possible. `/yolo` again turns it back off.
- **Tier 3** — refused by the gate on artemis before the SSH leaves the host,
  and unmatched by any sudoers rule on the node. Hermes prints the command
  for the operator. The gate also refuses an `execute_code` call that reaches
  a node with sudo, so the code sandbox cannot spawn its own ssh around the
  approval prompt.

## Knowledge base export

`hermes-kb-export.service`/`.timer` (weekly, `RandomizedDelaySec = 2h`) writes
a one-way snapshot into `jeiang/knowledge-base` and pushes it. Nothing from
that repo is ever read back into Hermes' own memory. Three record types:

- `journal/` — a dated copy of `MEMORY.md`.
- `self-actions/` — filenames of the last 7 days of session files, a
  best-effort digest of what ran, not a real action log.
- `facts/` — a `sqlite3 .dump` of the `holographic` fact store.

## Recovery

**Restore `/var/lib/hermes` from the artemis restic backup** — it is one of
the paths in artemis's `backupSet` (`modules/backups/default.nix`), so it
comes back through the standard artemis restore path
([`restore.md`](restore.md#artemis)):

```sh
ssh artemis.jeiang.vpn doas restic-persist restore <snapshot-id> --target /tmp/restore-persist --include '/persist/.backup-snapshot/var/lib/hermes'
```

Stop `hermes-agent.service` and the `jev-*` units before copying the restore
back over the live path, then start them again.

**Re-download the model weights** — `llm-server-fetch.service` only runs
while its target file is missing (`ConditionPathExists=!...`), so force a
re-fetch by removing the file first:

```sh
ssh artemis.jeiang.vpn doas rm /var/cache/bonsai-models/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
ssh artemis.jeiang.vpn doas systemctl start llm-server-fetch.service
ssh artemis.jeiang.vpn doas systemctl restart llm-server.service
```

**Rotating a secret** — `hermes/env` and `hermes/ssh-key` both list only
`hermes-agent.service` in `restartUnits`, so `just sops-edit` followed by a
deploy restarts that one unit automatically. The three `jev-*` units read the
same `hermes/env` file independently (`EnvironmentFile` for the oneshots,
`LoadCredential` snapshotted at start for the long-running
`jev-alert-triage.service`) and are **not** in that list — after rotating
`TYPESAFE_API_KEY`, `WEBHOOK_SECRET`, or `JEV_ALERT_TOKEN`, restart
`jev-alert-triage.service` by hand or it keeps using the stale value until
its next unrelated restart. The oneshot units (`jev-mail-triage`,
`jev-alert-digest`) pick up a rotated value on their own next timer tick.

## Troubleshooting

- **Model OOM / VRAM exhaustion under gaming** — the dGPU is shared between
  `llm-server.service` and a game; gamemode's `custom.start`/`custom.end`
  hooks (`modules/gaming.nix`) stop and restart `llm-server.service` around a
  gamemode-registered session. If a game was launched a way that bypasses
  gamemode (not through Steam or Heroic), the hook never fires. Check with
  `ssh artemis.jeiang.vpn systemctl status llm-server.service` and
  `rocm-smi --showmeminfo vram`; run `just llm-stop` manually before that
  game, `just llm-start` after.
- **Webhook 401** — the HMAC signature in `X-Webhook-Signature-V2` is over
  `<timestamp>.<body>` keyed with `WEBHOOK_SECRET`. A 401 means the caller's
  copy of `WEBHOOK_SECRET` (a `jev-*` unit's own `EnvironmentFile`/
  `LoadCredential` snapshot) has drifted from `hermes-agent.service`'s — see
  the rotation gap above — or the two hosts' clocks have drifted enough to
  fail the timestamp check. Confirm both with
  `ssh artemis.jeiang.vpn systemctl show hermes-agent.service jev-alert-triage.service -p Environment`
  (the value itself won't print, but a stale `ActiveEnterTimestamp` on one
  unit relative to the last `sops-edit` is the tell).
- **hermes-ops SSH refused** — check, in order: the public half of
  `hermes/ssh-key` is actually in `flake.lib.hermesOpsPublicKey` (not still
  `REPLACE_ME`); the `from=` restriction on each node's `authorized_keys`
  entry matches artemis's *current* NetBird peer address
  (`self.lib.netbirdPeers.artemis` — a re-enrolled peer changes this, and
  every Legion node needs the redeploy); and that Legion uses `sudo`, not
  `doas` — `hermes-ops` has no password of its own, so a wrong sudoers rule
  hangs or denies rather than failing with a clear password prompt. A first
  connection to a node after a fresh `/var/lib/hermes/.ssh` (first deploy, or
  any change that recreates the persisted directory) is trust-on-first-
  connect (`StrictHostKeyChecking accept-new`); nothing pins the real host
  key elsewhere in this repo.
