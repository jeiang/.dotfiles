# Hermes Activation (one-time)

**Delete this file after Hermes is enabled and Phase E passes.** Recurring
Hermes operations (publication approvals, cron jobs, knowledge base rules)
live in `hermes.md`.

Total: roughly 2 hours across five phases. Each phase is safe to stop after.

## Phase A — accounts and hardware (~45 min, browser + hcloud)

1. In Telegram, ask @BotFather for two new bots: the Hermes bot and the
  publisher bot. Save both tokens for Phase B.
2. Ask @userinfobot for your numeric Telegram user ID. Save it for Phase B.
3. Create the private, empty GitHub repository `jeiang/infrastructure-knowledge`.
4. Create a fine-grained GitHub PAT limited to `jeiang/.dotfiles` and
  `jeiang/infrastructure-knowledge`, with Contents and Pull requests
  read/write. Save it for Phase B.
5. Create a 10 GiB Hetzner Volume named `legion-hermes`, attach it to
  legion-node3, and note its numeric ID. On the node, format it:
  `mkfs.ext4 /dev/disk/by-id/scsi-0HC_Volume_<ID>`.

Done when: two bot tokens, one user ID, one PAT, and one formatted Volume ID
are in hand.

## Phase B — secrets (~15 min, dev shell)

Run `just sops-edit` and add these four entries. Do not print the values.

1. `hermes/env`: `TELEGRAM_BOT_TOKEN` (Hermes bot), `TELEGRAM_ALLOWED_USERS`
  (your user ID), `TELEGRAM_HOME_CHANNEL`.
2. `hermes/auth.json`: the Hermes OAuth seed.
3. `hermes/codex-auth.json`: the Codex OAuth seed (`~/.codex/auth.json` from
  a logged-in machine).
4. `hermes/publisher-env`: `HERMES_PUBLISHER_TELEGRAM_BOT_TOKEN` (publisher
  bot), `HERMES_PUBLISHER_TELEGRAM_ALLOWED_USER` (your user ID), and
  `GH_TOKEN` (the PAT from Phase A).

Done when: `just sops-edit` shows all four keys.

## Phase C — enable and merge (~10 min + one CI run)

1. In `modules/hosts/legion/_service-inventory.nix`, hermes entry: set
  `enabled = true;` and add `hcloudVolumeId = "<ID from Phase A>";` to
  `volume`.
2. Run `just fmt` then `just check`.
3. Commit as `feat(hermes): enable hermes on legion-node3`, open a PR, merge
  when CI is green.

Done when: main contains the enabled entry.

## Phase D — deploy and seed (~20 min, terminal + Telegram)

1. Run `just deploy legion-node3`.
2. Check `systemctl status hermes-agent hermes-publisher` on the node; both
  must be active. The publisher seeds `/mnt/hermes/mirrors/` on start.
3. If hermes-agent logs an auth failure, authenticate the seeded Codex CLI
  as the `hermes` user and confirm `gpt-5.6-terra` is accepted.
4. Create the worktrees as `hermes`, cloned from the local mirrors (Hermes
  owns them and never holds a GitHub credential):

  ```fish
  sudo -u hermes git config --global --add safe.directory /mnt/hermes/mirrors/jeiang__.dotfiles.git
  sudo -u hermes git config --global --add safe.directory /mnt/hermes/mirrors/jeiang__infrastructure-knowledge.git
  sudo -u hermes git -C /mnt/hermes/worktrees clone /mnt/hermes/mirrors/jeiang__.dotfiles.git cornn-flaek
  sudo -u hermes git -C /mnt/hermes/worktrees clone /mnt/hermes/mirrors/jeiang__infrastructure-knowledge.git infrastructure-knowledge
  ```

5. Send `/start` to the publisher bot once, then create the two cron jobs
  with the commands in `hermes.md`.

Done when: both services are active and both worktrees exist.

## Phase E — test (~20 min, Telegram + terminal)

1. DM the Hermes bot from an unapproved account and post in a group: both
  must be ignored.
2. `cat /mnt/hermes/reports/current.json` on the node: `collected_at` must
  be within the last 15 minutes.
3. Ask Hermes for a test publication request, wait for the publisher's
  announcement (pinned commit + diffstat), `/reject` it, request again,
  `/approve` it: a draft PR must appear. Repeat the `/approve <id>`: it
  must be refused as already used.
4. Negative cases: a request naming any other repository must be rejected;
  amend the branch tip after an announcement and `/approve`: it must be
  refused as moved.
5. Check `systemctl status restic-backups-hermes`, then run the restore
  procedure in `restore.md` into a temporary directory only.

Done when: all five pass. Then delete this file.
