# Hermes Activation

`hermes` is staged in the Legion inventory with `enabled = false`. Do not flip
that value until all of the following are complete.

1. Run the 30-day VictoriaMetrics query below on legion-node3. The minimum
  available memory must leave at least 1 GiB after reserving Hermes' 1 GiB
  service limit, which requires 2 GiB before existing workload headroom.
  If it does not, keep the service disabled and revisit its placement.

  ```fish
  set -l start (date -u --date='30 days ago' +%FT%TZ)
  set -l end (date -u +%FT%TZ)
  curl -fsS --get http://127.0.0.1:8428/api/v1/query_range \
    --data-urlencode 'query=min_over_time(node_memory_MemAvailable_bytes{instance=~"legion-node3.*"}[30d])' \
    --data-urlencode "start=$start" \
    --data-urlencode "end=$end" \
    --data-urlencode 'step=1h'
  ```

2. Create and attach a 10 GiB `legion-hermes` Hetzner Volume, then add its
  numeric ID as `hcloudVolumeId` in `_service-inventory.nix`. Format it as
  ext4 only as part of the explicit provisioning action.
3. Add SOPS entries without printing their values:
  `hermes/env` (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, and
  `TELEGRAM_HOME_CHANNEL`), `hermes/auth.json` (Hermes OAuth seed),
  `hermes/codex-auth.json` (Codex OAuth seed), and `hermes/publisher-env`
  (`HERMES_PUBLISHER_TELEGRAM_BOT_TOKEN`,
  `HERMES_PUBLISHER_TELEGRAM_ALLOWED_USER`, and the publisher `GH_TOKEN`).
  The publisher token must have access only to `jeiang/.dotfiles` and
  `jeiang/infrastructure-knowledge`.
4. Create `jeiang/infrastructure-knowledge` privately on GitHub before the
  next step, so the publisher can mirror it.
5. Set `enabled = true`, deploy only legion-node3, then authenticate the
  seeded Codex CLI as the `hermes` user if the seed was not already valid.
  Confirm `gpt-5.6-terra` is accepted before treating the gateway as live.
6. On start, `hermes-publisher` seeds read-only bare mirrors of both allowed
  repositories under `/mnt/hermes/mirrors/`. Create the worktrees as the
  `hermes` user by cloning from those local mirrors — Hermes owns its
  worktrees outright and never holds a GitHub credential:

  ```fish
  sudo -u hermes git config --global --add safe.directory /mnt/hermes/mirrors/jeiang__.dotfiles.git
  sudo -u hermes git config --global --add safe.directory /mnt/hermes/mirrors/jeiang__infrastructure-knowledge.git
  sudo -u hermes git -C /mnt/hermes/worktrees clone /mnt/hermes/mirrors/jeiang__.dotfiles.git cornn-flaek
  sudo -u hermes git -C /mnt/hermes/worktrees clone /mnt/hermes/mirrors/jeiang__infrastructure-knowledge.git infrastructure-knowledge
  ```

  The `safe.directory` entries are needed because the mirrors belong to the
  `hermes-publisher` user. Mirrors refresh `main` whenever the publisher
  starts or announces a request; restart `hermes-publisher` to force one.
7. Send `/start` to the publisher bot from the allowed account once, so it
  can deliver request announcements to that DM.

## Knowledge Base

`jeiang/infrastructure-knowledge` is private, reviewed Markdown. Initialize
it with `README.md` plus `systems/`, `services/`, `runbooks/`, `research/`,
and `sources/`. Every imported or derived page records its source repository,
source revision, source path, and collection timestamp in front matter. Search
with GitHub code search or `rg`, then read only the matching Markdown; do not
add embeddings or vector storage. The repository is authoritative. Hermes
memory, session history, and approved skills are supporting stores only.

After activation, create the two Hermes cron jobs from the allowed Telegram DM.
`TELEGRAM_HOME_CHANNEL` makes `--deliver telegram` unambiguous.

```fish
sudo -u hermes env HOME=/mnt/hermes HERMES_HOME=/mnt/hermes/.hermes CODEX_HOME=/mnt/hermes/codex \
  hermes cron add '0 8 * * *' \
  'Read only /mnt/hermes/reports/current.json and the reviewed infrastructure knowledge Markdown. Send a concise operational briefing. Cite each claim with the snapshot collected_at and the Markdown source path and revision. Do not change files, credentials, services, or jobs.' \
  --name 'Operational briefing' --deliver telegram --workdir /mnt/hermes/worktrees

sudo -u hermes env HOME=/mnt/hermes HERMES_HOME=/mnt/hermes/.hermes CODEX_HOME=/mnt/hermes/codex \
  hermes cron add '0 9 * * 1' \
  'Read only the reviewed infrastructure knowledge Markdown and /mnt/hermes/reports/current.json. Report stale facts, missing source revisions, and configuration drift. Cite the source path, revision, and snapshot collected_at. Do not change files, credentials, services, or jobs.' \
  --name 'Knowledge and configuration freshness review' --deliver telegram --workdir /mnt/hermes/worktrees
```

To request publication, Hermes writes
`/mnt/hermes/worktrees/.publisher-requests/<id>.json` with `repository` (one
of the two allowed repositories; the worktree path is derived from policy,
never from the request), a `codex/` `branch`, the exact 40-hex `commit` the
branch tip must match, and draft PR `title`/`body`. The publisher announces
each request in the authorized DM with the pinned commit and a diffstat
against `main`, computed inside its private mirror — it never executes git
against Hermes-writable repository configuration. `/approve <id>` re-verifies
that the branch tip still equals the pinned commit and pushes exactly that
commit; a tip that moved after the announcement is rejected. The approval bot
accepts only `/approve <id>` or `/reject <id>` in the authorized private DM.

Validate Telegram authorization with an unapproved DM and a group message,
then check `systemctl status hermes-agent hermes-publisher
hermes-snapshot-aggregate` and `/mnt/hermes/reports/current.json`. Exercise a
publisher request once for approval, rejection, replay, wrong repository,
force-push rejection, and a branch tip moved after the request was announced.
Finish with `systemctl status restic-backups-hermes` and
the restore procedure in `docs/runbooks/restore.md`, restoring only into a
temporary directory rather than over live state.
