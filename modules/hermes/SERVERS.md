# SERVERS.md

> **This file is Nix-managed**, same as SOUL.md — installed fresh into your
> working directory on every activation from `modules/hermes/SERVERS.md`.
> Don't edit it in place; changes go through the `cornn-flaek` repo. The
> unit lists below mirror the sudoers allowlists in `modules/hermes-ops.nix`;
> if a command the table allows is denied, the sudoers file is the truth.

Reference for the Legion fleet you operate. SOUL.md has the tier policy
(when you may act versus when you ask for approval); this file has the
mechanics and the per-node allowlists.

## Fleet map

NetBird mesh addresses (`modules/netbird-peers.nix`); Hetzner's own
private network (`172.17.0.0/24`) is not reachable from artemis, so all
fleet SSH rides the mesh.

- **alda** — edge (Caddy reverse proxy), CrowdSec, Anubis, tinyauth
- **vida** — NetBird server/relay/proxy, Pocket ID, Blocky DNS, portfolio
- **zantark** — monitoring (VictoriaMetrics, VictoriaLogs, Grafana,
  vmalert, Alertmanager)
- **peria** — garret (Nix binary cache), Actual Budget, atuin, hath,
  glance, Gatus
- **ricklent** — CrowdSec agent and firewall bouncer, Factorio,
  buildbot-nix master/worker (postgres, garret push timer), Gatus London
  watchdog, EU NetBird relay, second Blocky

## Tier mechanics

Tier 0 (`journalctl`, `systemctl status/show`) needs no sudo: you're in
the `systemd-journal` group on every node. Tier 1 is a `systemctl
start`/`restart` sudoers entry per (verb, unit) pair — no wildcards, so a
unit not listed below has no rule and the command fails regardless of
what you try.

Tier 2 is `stop` on every tier-1 unit, and `start`, `stop` or `restart`
on every unit in the tier-2 column. You never hold that capability: the
`hermes-approver` service on this host does. Ask it with `hermes-tier2`
(below); it runs the command only after Aidan approves it in Telegram.

| Node | Tier 1 — start/restart free | Tier 2 — start/stop/restart after approval |
|---|---|---|
| alda | `crowdsec`, `crowdsec-bouncers`, `prometheus-node-exporter` | `caddy`, `rivals-heroes-sync`, `anubis-content`, `tinyauth` |
| vida | `prometheus-node-exporter`, `restic-backups-netbird-server`, `restic-backups-pocket-id` | `netbird-server`, `netbird-relay`, `pocket-id`, `netbird-proxy`, `crowdsec-firewall-bouncer`, `blocky`, `portfolio` |
| zantark | `prometheus-node-exporter`, `prometheus-blackbox-exporter` | `grafana`, `victoriametrics`, `victorialogs`, `vmalert-default`, `alertmanager` |
| peria | `prometheus-node-exporter`, `garret-pusher`, `garret-puller`, `hath`, `glance`, `gatus`, `restic-backups-actual-budget`, `restic-backups-garret`, `restic-backups-hath` | `actual`, `atuin` |
| ricklent | `prometheus-node-exporter`, `gatus` | `blocky`, `buildbot-master`, `buildbot-worker`, `buildbot-garret-push`, `postgresql`, `crowdsec`, `crowdsec-firewall-bouncer`, `factorio`, `netbird-relay-eu` |

Anything not named in either column for a node — `sshd`, `netbird`
itself, the `acme-*` certificate units, `nixos-rebuild`, disk or secret
operations — is tier 3: no sudo rule exists anywhere in the fleet for it.

## How to run a fleet command

Your SSH config (`~/.ssh/config`, Nix-managed) resolves `alda`
through `ricklent` to `hermes-ops@<mesh IP>` with your key already
selected:

```sh
ssh alda -- sudo systemctl restart crowdsec.service
```

The sudoers rule pins the absolute path
`/run/current-system/sw/bin/systemctl`; a bare `sudo systemctl ...`
resolves there via the invoking user's PATH on every node, so it's the
form to reach for first.

## How to request a tier-2 command

```sh
hermes-tier2 alda restart caddy "caddy returns 502 for every host since 09:14; journal shows ..."
```

Arguments are node, verb (`start`, `stop` or `restart`), unit (without
`.service`), then the reason. Aidan sees the node, verb, unit and your
reason, labeled as written by you, so make the reason the evidence he
needs to decide. The command blocks until he answers or 2 minutes pass,
then prints the remote output and exits with the remote `systemctl`
status. A non-zero exit with no remote output means nothing ran: the
request was denied, expired, not a tier-2 command, or the approver was
busy or unavailable; the message on stderr says which. Run it in the
foreground with the terminal's default timeout or longer, never in the
background.

## Logs and metrics

Query `zantark` directly rather than SSHing to the node that owns a
unit — its journal collects every node's via `systemd-journal-upload`. Its
mesh IP is the `HostName` of the `zantark` entry in `~/.ssh/config`:

```sh
curl -s 'http://<zantark mesh IP>:9428/select/logsql/query' \
  --data-urlencode 'query=_SYSTEMD_UNIT:caddy.service' \
  --data-urlencode 'limit=50'
```

Metrics (PromQL) are on the same node at `:8428/api/v1/query`. Both are
plain HTTP, private-network only — reach them over the mesh, never
through the public edge (probing through it gets you banned by CrowdSec).

## Model

Your own model runs on this host: `llm-server.service`, loopback-only,
OpenAI-compatible. `systemctl status llm-server.service` here (no SSH,
no sudo) if a response looks wrong; gamemode stops and restarts it
automatically around a game session on this box.
