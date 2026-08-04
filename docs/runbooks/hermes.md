# Runbook: Hermes Agent

Operator runbook for the Hermes Agent (`modules/nixos/hermes/default.nix`,
placed on `legion-node3` per
`modules/hosts/legion/_service-inventory.nix`). Review
[`AGENTS.md`](../../AGENTS.md) before running any command here. See
[`docs/adr/0007-hold-scoped-credentials-in-the-agent.md`](../adr/0007-hold-scoped-credentials-in-the-agent.md)
for why the agent holds its own credentials instead of a broker, and
[`docs/adr/0011-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md`](../adr/0011-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md)
for the tiered fleet-operator model and the credential inventory below.

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

## Credential inventory and rotation

See
[`docs/adr/0011-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md`](../adr/0011-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md)
for why each of these exists and what it is scoped to. Every credential
here lives in `modules/nixos/hermes/secrets.yaml`, edited with `just
sops-edit` (it keys new secrets automatically -- `just sops-updatekeys` is
only needed after a `.sops.yaml` recipient change, e.g. adding a Legion
node as a `hermes-ops` recipient).

> The mechanism wiring each secret into its module (which `sops.secrets`
> entry, which unit reads it) lands with the feature part that introduces
> that integration. This section is the operator-facing inventory; fill in
> the mint/rotate steps below as each integration ships.

- **`hermes-ops` SSH private key** -- an ed25519 keypair, private half in
  the sops shard, public half deployed to every Legion node's
  `hermes-ops` `authorized_keys`. Rotate by generating a new pair,
  redeploying the public half to all four nodes, then updating the sops
  secret -- both keys work during that window, so there is no
  connectivity gap.
- **Actual Budget session token** -- minted by authenticating against the
  Actual server at `172.17.0.4:5006` (never the server's own login
  password, see the ADR). If Aidan runs Actual's "log out all sessions"
  action, this token is invalidated immediately and must be re-minted the
  same way before Hermes can reach the budget again.
- **iCloud app-specific password (CalDAV/CardDAV)** -- generated from
  Aidan's Apple ID account page (App-Specific Passwords), stored in the
  shard, consumed by khal/vdirsyncer. Revoke from the same Apple ID page;
  revocation is independent of every other credential in this inventory,
  so it never needs a coordinated rotation.
- **`hermes-repos` GitHub PAT** -- a second fine-grained PAT (distinct
  from the Knowledge Base PAT ADR 0007 already covers), scoped to
  contents and pull-requests read/write on the enumerated repo list
  (`.dotfiles`, agent skills, `attic`, website). Mint from
  <https://github.com/settings/personal-access-tokens> the same way as
  the Knowledge Base PAT, with that repo list as "Only select
  repositories". Rotate by generating a replacement with the same scope
  and repo list, then overwriting the sops secret.
- **Grafana service-account token** -- created from Grafana's own
  Service Accounts admin page, scoped to annotation writes only. Rotate
  by revoking the old token there and minting a replacement.
- **`artemis` LLM provider** -- no credential to manage; unauthenticated
  over the NetBird mesh.

## Verifying the operations tiers

> Skeleton: these are the acceptance checks for the tiered fleet-operator
> model (ADR 0011). Fill in exact commands once the `hermes-ops` doas
> rules and SSH transport land.

- **Tier 1**: a `systemctl restart` on an allowlisted low-blast-radius
  unit (e.g. `hermes-kb-sync`) succeeds as `hermes-ops` with no
  confirmation prompt.
- **Tier 3**: `doas systemctl stop sshd` run as `hermes-ops` is denied --
  no doas rule permits it, so this must fail the same way whether or not
  Hermes itself asks for it.
- **Journalctl fallback**: with VictoriaLogs unreachable from a node,
  `hermes-ops` can still read that node's own journal directly via
  `systemd-journal` group membership.

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
