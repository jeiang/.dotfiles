# Hermes Operations

This file covers the flows that recur for as long as Hermes runs.

## Publication requests

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

Mirrors under `/mnt/hermes/mirrors/` refresh `main` whenever the publisher
starts or announces a request; restart `hermes-publisher` to force one.
Hermes pulls repository content only from those local mirrors.

## Knowledge Base

`jeiang/knowledge-base` is private, reviewed Markdown, starting with
infrastructure facts and growing to broader topics over time. Initialize
it with `README.md` plus `systems/`, `services/`, `runbooks/`, `research/`,
and `sources/`. Every imported or derived page records its source repository,
source revision, source path, and collection timestamp in front matter. Search
with GitHub code search or `rg`, then read only the matching Markdown; do not
add embeddings or vector storage. The repository is authoritative. Hermes
memory, session history, and approved skills are supporting stores only.

## Cron jobs

Create (or recreate after state loss) the two Hermes cron jobs from the
allowed Telegram DM. `TELEGRAM_HOME_CHANNEL` makes `--deliver telegram`
unambiguous.

```fish
sudo -u hermes env HOME=/mnt/hermes HERMES_HOME=/mnt/hermes/.hermes CODEX_HOME=/mnt/hermes/codex \
  hermes cron add '0 8 * * *' \
  'Read only /mnt/hermes/reports/current.json and the reviewed knowledge-base Markdown. Send a concise operational briefing. Cite each claim with the snapshot collected_at and the Markdown source path and revision. Do not change files, credentials, services, or jobs.' \
  --name 'Operational briefing' --deliver telegram --workdir /mnt/hermes/worktrees

sudo -u hermes env HOME=/mnt/hermes HERMES_HOME=/mnt/hermes/.hermes CODEX_HOME=/mnt/hermes/codex \
  hermes cron add '0 9 * * 1' \
  'Read only the reviewed knowledge-base Markdown and /mnt/hermes/reports/current.json. Report stale facts, missing source revisions, and configuration drift. Cite the source path, revision, and snapshot collected_at. Do not change files, credentials, services, or jobs.' \
  --name 'Knowledge and configuration freshness review' --deliver telegram --workdir /mnt/hermes/worktrees
```

## Health check

`systemctl status hermes-agent hermes-publisher hermes-snapshot-aggregate`,
then confirm `/mnt/hermes/reports/current.json` has a `collected_at` within
the last 15 minutes. Backups: `systemctl status restic-backups-hermes`; the
restore procedure is in `restore.md` — restore only into a temporary
directory, never over live state.
