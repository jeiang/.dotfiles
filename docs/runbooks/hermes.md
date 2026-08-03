# Runbook: Hermes Agent

Operator runbook for the Hermes Agent (`modules/nixos/hermes/default.nix`,
placed on `legion-node3` per
`modules/hosts/legion/_service-inventory.nix`). Review
[`AGENTS.md`](../../AGENTS.md) before running any command here. See
[`docs/adr/0007-hold-scoped-credentials-in-the-agent.md`](../adr/0007-hold-scoped-credentials-in-the-agent.md)
for why the agent holds its own credentials instead of a broker.

## Deploy

Standard deploy-rs flow for the node (`justfile`):

```sh
just deploy legion-node3
```

## Codex auth after a deploy or rebuild

Codex auth needs an interactive OAuth device-code flow on the node after
the first deploy, and again after any node rebuild, since Hermes' auth
store is Disposable State on the root disk. Verified against the
pinned rev: a cold start with an empty auth store raises
`codex_auth_missing`, which is excluded from the self-heal import in
`resolve_codex_runtime_credentials` (`hermes_cli/auth.py`), and the
`auth add openai-codex` path goes straight to a fresh device-code login --
it never imports the module's seeded `~/.codex/auth.json` on an empty
store (that seed only feeds self-heal when the store holds a *malformed*
token pair). The flow prints a URL plus a code, so it works fine over SSH:

```sh
ssh node3.jeiang.dev
sudo -u hermes HOME=/var/lib/hermes \
  "$(systemctl cat hermes-agent | grep -o '/nix/store/[^ ]*/bin/hermes' | head -1)" \
  auth add openai-codex
```

The store-path dance is because the `hermes` CLI is not on any system PATH
-- it lives only inside the service's own package
(`services.hermes-agent.addToSystemPackages` stays off), so it is extracted
from the unit's `ExecStart` here. `HOME` must be set explicitly too: the
unit sets `HOME=/var/lib/hermes` for the service, but `sudo` does not.

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
`attic/default.nix`/`actual-budget.nix`).

The state directory on `legion-node3`'s root disk (agent sessions, the
Knowledge Base clone) is Disposable State and can be deleted freely -- no
Hetzner Volume, no Backup Set. The durable copies are the
`jeiang/knowledge-base` remote and the `modules/nixos/hermes/secrets.yaml`
sops shard; neither is affected by deleting node-local state.
