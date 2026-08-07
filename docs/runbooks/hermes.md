# Runbook: Hermes Agent

Operator runbook for the Hermes Agent (`modules/nixos/hermes/default.nix`,
placed on `legion-node3` per
`modules/hosts/legion/_service-inventory.nix`). Review
[`AGENTS.md`](../../AGENTS.md) before running any command here. See
[`docs/adr/0007-hold-scoped-credentials-in-the-agent.md`](../adr/0007-hold-scoped-credentials-in-the-agent.md)
for why the agent holds its own credentials instead of a broker, and
[`docs/adr/0012-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md`](../adr/0012-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md)
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
[`docs/adr/0012-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md`](../adr/0012-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md)
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
- **Actual Budget session token** -- `ACTUAL_SESSION_TOKEN`, an
  additional line inside the existing `hermes/env` sops secret (`just
  sops-edit`, then edit the `env:` block -- no new sops entry, see
  `modules/nixos/hermes/default.nix`'s `hermes/env` comment for the full
  list of what belongs in that block). Mint by authenticating against the
  Actual server at `172.17.0.4:5006` (never the server's own login
  password, see the ADR) -- Actual's own API/UI issues a session token on
  login, not the account password itself. Consumed by the `actual` CLI
  (`modules/packages/actual-cli.nix`) via `extraPackages`, together with
  `ACTUAL_SYNC_ID` (also `hermes/env` -- Actual's Settings -> Advanced ->
  Sync ID, not itself a credential but operator-specific) and
  `ACTUAL_SERVER_URL` (`http://172.17.0.4:5006`, non-secret, set directly
  in the module, not sops-managed). If Aidan runs Actual's "log out all
  sessions" action, `ACTUAL_SESSION_TOKEN` is invalidated immediately and
  must be re-minted the same way before Hermes can reach the budget
  again.
- **iCloud app-specific password (CalDAV/CardDAV)** -- `ICLOUD_APP_PASSWORD`,
  another `hermes/env` line, generated from Aidan's Apple ID account page
  (appleid.apple.com -> Sign-In and Security -> App-Specific Passwords).
  `ICLOUD_USERNAME` (Aidan's iCloud email, not itself a credential but
  operator-specific) sits alongside it in the same secret. Both consumed
  by vdirsyncer's `username.fetch`/`password.fetch` (`["command",
  "printenv", "..."]`, `modules/nixos/hermes/default.nix`'s
  `vdirsyncerConfig`) from the `hermes-vdirsyncer-sync` unit's
  environment -- khal itself never touches iCloud directly, it only reads
  the local vdir vdirsyncer maintains. Revoke from the same Apple ID page;
  revocation is independent of every other credential in this inventory,
  so it never needs a coordinated rotation. Rotate by generating a new
  app-specific password and overwriting the `ICLOUD_APP_PASSWORD` line.
- **`hermes-repos` GitHub PAT** -- `HERMES_REPOS_TOKEN`, another
  `hermes/env` line. A second fine-grained PAT (distinct from the
  Knowledge Base PAT ADR 0007 already covers, which stays as
  `GITHUB_TOKEN`), scoped to contents and pull-requests read/write on the
  enumerated repo list (`jeiang/.dotfiles`, `jeiang/garret`,
  `jeiang/website`, and Aidan's Claude Code agent-skills repo -- confirm
  that repo's exact slug with Aidan at mint time, it wasn't pinned down
  more precisely than that here). Mint from
  <https://github.com/settings/personal-access-tokens> the same way as
  the Knowledge Base PAT, with that repo list as "Only select
  repositories". Consumed by the agent's own interactive `gh`/`git`
  (SOUL.md "GitHub access", SERVERS.md "Other Git repos") -- explicitly
  per-command (`GH_TOKEN=$HERMES_REPOS_TOKEN gh ...`), never as the
  default `GITHUB_TOKEN`, so `hermes-kb-sync` and the agent's own KB
  writes are unaffected by this addition. Rotate by generating a
  replacement with the same scope and repo list, then overwriting the
  `HERMES_REPOS_TOKEN` line.
- **Grafana service-account token** -- `GRAFANA_ANNOTATION_TOKEN`,
  another `hermes/env` line. Mint from Grafana's own UI: Administration
  -> Service accounts -> New service account, role scoped to annotation
  writes only (no query or admin permission), then add a token to that
  service account. `GRAFANA_URL` (`http://127.0.0.1:3000`, non-secret,
  Grafana runs on this same node) is set directly in the module.
  Consumed by the agent's own `curl` calls to `POST
  $GRAFANA_URL/api/annotations` (SERVERS.md "Grafana annotations").
  Rotate by revoking the old token from the same Service Accounts page
  and overwriting the `GRAFANA_ANNOTATION_TOKEN` line with a replacement.
- **`artemis` LLM provider** -- no credential to manage; unauthenticated
  over the NetBird mesh (`settings.providers.artemis`,
  `modules/nixos/hermes/default.nix`). If artemis's NetBird peer IP
  (`100.89.148.91`, hardcoded as this provider's `base_url` host) is ever
  reassigned, that literal needs updating and redeploying -- not a
  credential rotation, but the closest thing this entry has to
  maintenance.

**Operator checklist for this part** -- every line above that must be
added to `modules/nixos/hermes/secrets.yaml`'s `env:` block via `just
sops-edit` before deploying Part D's integrations:

```
ACTUAL_SESSION_TOKEN=...
ACTUAL_SYNC_ID=...
ICLOUD_USERNAME=...
ICLOUD_APP_PASSWORD=...
HERMES_REPOS_TOKEN=...
GRAFANA_ANNOTATION_TOKEN=...
```

No new sops secret files or `sops.secrets` entries are needed for this
part -- all six fold into the existing `hermes/env` secret Part A already
declared.

## Verifying the operations tiers

The `hermes-ops` sudo allowlist (`modules/nixos/hermes-ops/default.nix`,
wired onto all four Legion nodes by `modules/hosts/legion/default.nix`) is
live from this part onward -- sudo, not doas: Legion enables
`security.sudo` fleet-wide, and `modules/nixos/security.nix`'s doas module
is imported only by `modules/hosts/artemis/default.nix`, never by Legion.
The checks below don't depend on the `hermes/ssh-key` sops secret having a
real value yet (see the credential-inventory entry above) -- they run over
your own admin SSH session and your `wheel` account's passwordless sudo
(the outer `sudo -u hermes-ops` becomes hermes-ops; the inner `sudo
systemctl ...` is what actually exercises hermes-ops's own allowlist):

```sh
ssh node3.jeiang.dev -- sudo -u hermes-ops sudo systemctl restart hermes-kb-sync.service
```

- **Tier 1 pass**: the command above succeeds AND prints no password
  prompt. "No password prompt" is part of the pass condition, not
  incidental -- the inner `sudo systemctl ...` runs as hermes-ops, which
  has no password of its own, so the only way it succeeds silently is a
  matching `NOPASSWD` rule; if the allowlist were ever wrong, this is the
  step that would hang waiting for a password hermes-ops can't supply.
- **Tier 2 mechanics**: `ssh node1.jeiang.dev -- sudo -u hermes-ops sudo
  systemctl restart caddy.service` also succeeds mechanically, identically
  to the tier-1 case above -- the sudo rule doesn't distinguish tiers.
  What makes it tier 2 is SOUL.md requiring Aidan's Telegram "yes" before
  Hermes runs it; sudo itself does not gate this.
- **Tier 3, must be DENIED**:
  ```sh
  ssh node3.jeiang.dev -- sudo -u hermes-ops sudo systemctl stop sshd
  ```
  is refused outright by sudo (no matching rule, and hermes-ops has no
  password to fall back to, so it fails rather than prompts) -- the same
  denial whether or not Hermes itself asks for it first. Same for `sudo
  systemctl restart hermes-agent` and `sudo netbird up`/`sudo netbird
  down`: none of these commands has a matching rule on any node.
- **netbird read/tier-2**: `sudo netbird status` succeeds on any node
  (tier 1, needs sudo because `services.netbird` runs `hardened = true` --
  the client's control socket isn't otherwise reachable by hermes-ops).
  `sudo hermes-ops-netbird-expose 8080` succeeds too (tier 2 mechanically,
  gated on Aidan's confirmation at the prompt level); bare `sudo netbird
  expose 8080` is denied -- only the single-purpose wrapper is permitted,
  not the raw netbird binary with arbitrary arguments.
- **Journalctl fallback**: with VictoriaLogs unreachable from a node,
  `hermes-ops` can still read that node's own journal directly (no sudo
  needed) via `systemd-journal` group membership, e.g. `journalctl -u
  caddy.service -e`.
- **node3 is uniform now, no local-sudo shortcut**: node3 used to grant the
  `hermes` service user the same sudo rules as `hermes-ops`
  (`hermesOps.extraGrantees`) so it could act on its own node without an
  SSH hop. That grant was removed (ADR 0012, amended): the `hermes-agent`
  unit runs `NoNewPrivileges=yes` (set upstream, not by this repo), which
  blocks any in-process `sudo` from gaining privilege no matter what
  sudoers permits -- a same-node action has to leave the sandboxed process
  tree via sshd, same as a cross-node one. `hermes-ops` is the only sudo
  user on every node now, node3 included; `hermesOps.journalGrantees` is
  what the `hermes` user keeps instead, `systemd-journal` membership only,
  for local journal reads (no privilege escalation involved, so the
  sandbox doesn't touch it).

  Check this specific regression from the agent's own perspective -- as
  the `hermes` user, self-SSH to node3 rather than running sudo directly:

  ```sh
  ssh node3.jeiang.dev
  sudo -u hermes -- ssh legion-node3 -- sudo -n systemctl restart hermes-kb-sync.service
  ```

  This should succeed exactly like the admin-session check above. `sudo
  -n` (non-interactive) is the useful form for this specific check: if the
  regression ever comes back (the local sudo grant re-added, or the SSH
  Host block for node3 dropped again), a tier-3-style denial prints "sudo:
  a password is required" and returns immediately instead of hanging on a
  password prompt `hermes-ops` can never answer -- a hang here, not just a
  failure, is itself the signal that this exact bug is back.
- **PATH fallback**: a non-interactive `ssh ... -- ...` runs a non-login
  shell (fish, this fleet's default), which can affect PATH lookup for the
  bare command names above. In practice both `sudo` and the systemd
  units it invokes should resolve fine -- nixpkgs' `sudo` package has no
  `secure_path` override, so it defers to the invoking user's own PATH,
  and NixOS sets that PATH (including `/run/current-system/sw/bin`) via
  PAM early in every session, SSH included. If a bare call is ever denied
  where you'd expect it to succeed, fall back to absolute paths for both
  halves: `/run/wrappers/bin/sudo` (`security.wrapperDir`, where NixOS'
  sudo module installs the setuid wrapper -- verified against the pinned
  nixpkgs `nixos/modules/security/wrappers/default.nix`) and
  `/run/current-system/sw/bin/systemctl`.

## Verifying the alert webhook

Alertmanager (this same node) POSTs to Hermes' webhook adapter at
`http://127.0.0.1:8644/webhooks/alertmanager`
(`modules/nixos/hermes/default.nix` `platforms.webhook`) -- both ends are
loopback, so this can only be tested from `legion-node3` itself. Fire a
synthetic alert directly at the endpoint with a sample Alertmanager
webhook payload (this is exactly the shape Alertmanager's own
`webhook_configs` POSTs):

```sh
ssh node3.jeiang.dev -- curl -s -X POST http://127.0.0.1:8644/webhooks/alertmanager \
  -H 'Content-Type: application/json' \
  -d '{
    "version": "4",
    "status": "firing",
    "receiver": "discord-notifications",
    "groupLabels": {"alertgroup": "fleet-health"},
    "commonLabels": {"severity": "warning"},
    "commonAnnotations": {"summary": "synthetic test alert"},
    "alerts": [{
      "status": "firing",
      "labels": {"alertname": "SyntheticTest", "instance": "legion-node3", "severity": "warning"},
      "annotations": {"summary": "synthetic test alert", "description": "manual runbook verification, not a real condition"},
      "startsAt": "2026-08-04T00:00:00Z"
    }]
  }'
```

Expect an immediate `{"status":"accepted",...}` response (HTTP 202 -- the
agent run happens in the background), then a Telegram message from Hermes
within a turn or two with its investigation of the synthetic alert: a
diagnosis and a recommended action, not an autonomous fix -- this route
is investigate-and-report only (see ADR 0012's amended "Tier 2's soft
enforcement" section for why). If nothing arrives, check the gateway log
for `[webhook]`-prefixed lines:

```sh
ssh node3.jeiang.dev -- journalctl -u hermes-agent -e | grep webhook
```

The same payload also works via `amtool` if you'd rather exercise
Alertmanager's own routing instead of the webhook endpoint directly
(confirms the receiver/route wiring in
`modules/nixos/monitoring/default.nix`, not just Hermes' side). `amtool`
isn't on `legion-node3`'s PATH by default (not added to
`environment.systemPackages`), so pull it ad hoc via nix:

```sh
ssh node3.jeiang.dev -- nix shell nixpkgs#alertmanager -c amtool alert add \
  alertname=SyntheticTest severity=warning \
  --annotation=summary="synthetic test alert" --alertmanager.url=http://127.0.0.1:9093
```

That exercises the full path (Alertmanager groups it, fires both
`discord_configs` and `webhook_configs` on the `discord-notifications`
receiver) -- expect both a Discord notification and, shortly after, a
Telegram message from Hermes.

No new secret for this feature: the webhook is loopback-only and uses the
adapter's own `INSECURE_NO_AUTH` escape hatch (scoped to loopback binds),
so there is nothing to add to the credential inventory above.

## Verifying cron routines

Ask Hermes over Telegram to list what it has scheduled -- it has the
`cronjob` tool available there (`SERVERS.md` "Cron routines"), so "what
cron jobs do you have scheduled?" is enough; no CLI access needed for
day-to-day management. To inspect from the node directly instead (same
store-path extraction as the Codex auth flow above, since `hermes` isn't
on any system PATH):

```sh
ssh node3.jeiang.dev
sudo -u hermes HOME=/var/lib/hermes \
  "$(systemctl cat hermes-agent | grep -o '/nix/store/[^ ]*/bin/hermes' | head -1)" \
  cron list
```

Scheduled jobs fire from the already-running `hermes-agent` process (its
in-process cron ticker) -- no separate timer or service to check.

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
`garret/default.nix`/`actual-budget.nix`).

The state directory on `legion-node3`'s root disk (agent sessions, the
Knowledge Base clone) is Disposable State and can be deleted freely -- no
Hetzner Volume, no Backup Set. The durable copies are the
`jeiang/knowledge-base` remote and the `modules/nixos/hermes/secrets.yaml`
sops shard; neither is affected by deleting node-local state.
