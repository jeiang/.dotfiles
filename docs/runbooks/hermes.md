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
  the sops shard as secret `hermes/ssh-key`, installed by `hermes-agent`'s
  preStart to `/var/lib/hermes/.ssh/id_ed25519` (overwritten on every
  service start, so a rotated key takes effect on the next deploy). Public
  half deployed to every Legion node's `hermes-ops` `authorized_keys`
  (`modules/nixos/hermes-ops/default.nix`). Rotate by generating a new
  pair, redeploying the public half to all four nodes, then overwriting
  the `hermes/ssh-key` sops secret -- both keys work during that window,
  so there is no connectivity gap.

  Host key verification uses `StrictHostKeyChecking accept-new` against a
  persistent `known_hosts` under `/var/lib/hermes/.ssh/` (no Legion node's
  SSH host public key is committed anywhere in this repo to pin against
  instead -- see `modules/nixos/hermes/default.nix`'s `sshConfig` comment
  for the full tradeoff). This means the first connection to each node
  after a fresh state directory (first deploy, or any rebuild that wipes
  Disposable State) is trust-on-first-connect. If you'd rather not accept
  that window, pre-seed `/var/lib/hermes/.ssh/known_hosts` yourself with
  each node's real host key before the first fleet command runs; otherwise
  it's populated automatically on first connect and pinned from then on.
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

The `hermes-ops` doas allowlist (`modules/nixos/hermes-ops/default.nix`,
wired onto all four Legion nodes by
`modules/hosts/legion/default.nix`) is live from this part onward. The
`hermes/ssh-key` sops secret is *declared* in
`modules/nixos/hermes/default.nix` from this part onward too, but its
value is only real once you add it via `just sops-edit` (see the
credential-inventory entry above) -- until you do, run these as
`hermes-ops` locally (`ssh <admin>@nodeN.jeiang.dev -- doas -u hermes-ops
sh -c '...'` -- doas, not su/sudo, per `modules/nixos/security.nix`).
Once the key's value is set and deployed, run them as `ssh
hermes-ops@172.17.0.N -- ...` from **legion-node3 only** -- every other
source IP is rejected by the `authorized_keys` `from=` restriction.

- **Tier 1**: `doas systemctl restart hermes-kb-sync.service` on
  legion-node3 succeeds as `hermes-ops` with no confirmation prompt (a
  tier-1, low-blast-radius unit).
- **Tier 2 mechanics**: `doas systemctl restart caddy.service` on
  legion-node1 also succeeds mechanically -- the doas rule is identical
  to a tier-1 restart. What makes it tier 2 is SOUL.md requiring Aidan's
  Telegram "yes" before Hermes runs it; doas itself does not gate this.
- **Tier 3**: `doas systemctl stop sshd` (any node) is denied -- no doas
  rule permits it, so this fails the same way whether or not Hermes
  itself asks for it. Same for `doas systemctl restart hermes-agent`
  and `doas netbird up`/`doas netbird down` on legion-node3: none of
  these commands has a matching rule.
- **netbird read/tier-2**: `doas netbird status` succeeds on any node
  (tier 1, needs doas because `services.netbird` runs
  `hardened = true` -- the client's control socket isn't otherwise
  reachable by hermes-ops). `doas hermes-ops-netbird-expose 8080`
  succeeds too (tier 2 mechanically, gated on Aidan's confirmation at
  the prompt level); bare `doas netbird expose 8080` is denied -- only
  the single-purpose wrapper is permitted, not the raw netbird binary
  with arbitrary arguments.
- **Journalctl fallback**: with VictoriaLogs unreachable from a node,
  `hermes-ops` can still read that node's own journal directly (no doas
  needed) via `systemd-journal` group membership, e.g. `journalctl -u
  caddy.service -e`.
- **node3 locality**: the same three checks above also pass when run as
  the `hermes` user directly on legion-node3 (`doas` invoked locally,
  no SSH-to-self) -- `hermesOps.extraGrantees` grants it identically to
  `hermes-ops`.

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
