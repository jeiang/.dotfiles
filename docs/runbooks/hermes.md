# Runbook: Hermes Agent

Operator runbook for the Hermes Agent (`modules/nixos/hermes/default.nix`,
placed on `legion-node3` per
`modules/hosts/legion/_service-inventory.nix`). Review
[`AGENTS.md`](../../AGENTS.md) before running any command here. See
[`docs/adr/0007-hold-scoped-credentials-in-the-agent.md`](../adr/0007-hold-scoped-credentials-in-the-agent.md)
for why the agent holds its own credentials instead of a broker.

## Secrets population

Do all of this before the first deploy that enables `hermes`.

### GitHub PAT

The module wires a single `GITHUB_TOKEN` into the agent's environment (read
by both `gh` and the module's git credential helper). GitHub's fine-grained
PATs apply one permission set uniformly to every repository the token can
reach -- a single token cannot mix "read on every repo" with "write on only
one," so the fewest-tokens option is the only one that fits `GITHUB_TOKEN`:

1. Go to <https://github.com/settings/personal-access-tokens>, "Generate new token".
2. **Resource owner**: the operator's account. **Repository access**: "Only select repositories" -> `jeiang/knowledge-base`.
3. **Permissions** -> Repository permissions -> **Contents**: "Read and write". Leave every other permission at "No access".
4. Generate the token and copy it -- this is the value that goes into `GITHUB_TOKEN` below.

Read access across the operator's other repositories is not part of this
token (see the ADR); it stays a stretch goal until the module grows a second
credential path for it.

### Telegram bot

1. Talk to [@BotFather](https://t.me/BotFather) on Telegram, `/newbot`, and copy the resulting bot token.
2. Get your own numeric Telegram user ID (e.g. message [@userinfobot](https://t.me/userinfobot)) for `TELEGRAM_ALLOWED_USERS`.

### Codex auth

On a trusted machine with the `codex` CLI installed:

```sh
codex login
```

Copy the full contents of the resulting `~/.codex/auth.json` -- that JSON is
the value for the `hermes/codex-auth.json` secret below.

### Populate the shard

```sh
just sops-edit
```

Pick `secrets.hermes.yaml` from the `fzf` prompt (`sops-edit` keys new
secrets automatically -- `sops-updatekeys` is only needed after a `.sops.yaml`
recipient change). Fill in:

| Secret | Value |
| --- | --- |
| `hermes/env` | Env-file-shaped: `TELEGRAM_BOT_TOKEN=...`, `TELEGRAM_ALLOWED_USERS=...`, `GITHUB_TOKEN=...` (the knowledge-base-scoped PAT above), one per line. |
| `hermes/codex-auth.json` | The full `~/.codex/auth.json` contents from above. |

## Knowledge-base fresh start

One-time, before the first deploy. Clears `jeiang/knowledge-base` with a
normal commit -- history stays, so this is reversible.

```sh
git clone https://github.com/jeiang/knowledge-base.git /tmp/kb-fresh-start
cd /tmp/kb-fresh-start
git rm -r --ignore-unmatch .
git commit -m "kb: fresh start for the new hermes"
git push
cd - && rm -rf /tmp/kb-fresh-start
```

## Deploy

Standard deploy-rs flow for the node (`justfile`):

```sh
just deploy legion-node3
```

## First-boot, one-time codex adoption

The module seeds Codex-CLI-shaped OAuth tokens at
`${stateDir}/.codex/auth.json` (`stateDir` defaults to `/var/lib/hermes`),
but Hermes does not auto-import that file into its own auth store on a cold
start -- see the long comment in `modules/nixos/hermes/default.nix` above
`sops.secrets`. After the first deploy, adopt it manually:

```sh
ssh node3.jeiang.dev
sudo -u hermes HOME=/var/lib/hermes \
  "$(systemctl cat hermes-agent | grep -o '/nix/store/[^ ]*/bin/hermes' | head -1)" \
  auth openai-codex
```

The store-path dance is because the `hermes` CLI is not on any system PATH
-- it lives only inside the service's own package
(`services.hermes-agent.addToSystemPackages` stays off), so it is extracted
from the unit's `ExecStart` here. `HOME` must be set explicitly too: the
unit sets `HOME=/var/lib/hermes` for the service, but `sudo` does not.

Accept the "Import these credentials?" prompt. This is one-time only: once
Hermes' own auth store holds a token pair, its self-heal path takes over for
future refreshes.

## Verify

```sh
ssh node3.jeiang.dev -- systemctl status hermes-agent
ssh node3.jeiang.dev -- journalctl -u hermes-agent -e -f
```

- Message the Telegram bot and confirm it replies.
- Check the Knowledge Base sync timer is scheduled:
  ```sh
  ssh node3.jeiang.dev -- systemctl list-timers hermes-kb-sync
  ```
- Ask the agent to write something to its knowledge base, then confirm a
  test file lands in `jeiang/knowledge-base` on GitHub within about 15
  minutes (`OnUnitActiveSec = "15m"` on `hermes-kb-sync.timer`) -- sooner if
  the agent pushes itself instead of waiting for the timer.

## Rollback

Standard deploy-rs magic rollback applies: if the new activation doesn't
confirm, deploy-rs reverts to the previous generation on its own.

To disable Hermes entirely: remove the `hermes` entry from
`modules/hosts/legion/_service-inventory.nix` and redeploy `legion-node3`
(the module only imports when the inventory places it -- the same
optional-import pattern `modules/hosts/legion/default.nix` uses for
`attic.nix`/`actual-budget.nix`).

The state directory on `legion-node3`'s root disk (agent sessions, the
Knowledge Base clone) is Disposable State and can be deleted freely -- no
Hetzner Volume, no Backup Set. The durable copies are the
`jeiang/knowledge-base` remote and the `secrets.hermes.yaml` sops shard;
neither is affected by deleting node-local state.
