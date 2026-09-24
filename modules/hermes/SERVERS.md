# SERVERS.md

> **This file is Nix-managed**, same as SOUL.md — installed fresh into your
> working directory on every activation from `modules/hermes/SERVERS.md`.
> Don't edit it in place; changes go through the `cornn-flaek` repo. The
> unit lists below mirror the sudoers allowlist in `modules/hermes-ops.nix`;
> if a command the table allows is denied, the sudoers file is the truth.

Reference for the Legion fleet you operate. SOUL.md has the tier policy
(when you may act versus when you print the command); this file has the
mechanics and the per-node allowlists.

## Fleet map

NetBird mesh addresses (`modules/netbird-peers.nix`); Hetzner's own
private network (`172.17.0.0/24`) is not reachable from artemis, so all
fleet SSH rides the mesh.

- **legion-node1** — edge (Caddy reverse proxy), CrowdSec, Anubis, tinyauth
- **legion-node2** — NetBird server/relay/proxy, Pocket ID, Blocky DNS
- **legion-node3** — monitoring (VictoriaMetrics, VictoriaLogs, Grafana,
  vmalert, Alertmanager)
- **legion-node4** — garret (Nix binary cache), Actual Budget, atuin, hath,
  glance, Gatus

## Tier mechanics

Tier 0 (`journalctl`, `systemctl status/show`) needs no sudo: you're in
the `systemd-journal` group on every node. Tier 1 is a `systemctl
start`/`restart` sudoers entry per (verb, unit) pair — no wildcards, so a
unit not listed below has no rule and the command fails regardless of
what you try. Every unit is tier 2 for `stop`; print the command, don't
run it.

| Node | Tier 1 — start/restart free | Tier 2 — print, don't run |
|---|---|---|
| legion-node1 | `crowdsec`, `crowdsec-bouncers`, `prometheus-node-exporter` | `caddy`, `rivals-heroes-sync`, `anubis-content`, `tinyauth` |
| legion-node2 | `prometheus-node-exporter`, `restic-backups-netbird-server`, `restic-backups-pocket-id` | `netbird-server`, `netbird-relay`, `pocket-id`, `netbird-proxy`, `crowdsec-firewall-bouncer`, `blocky` |
| legion-node3 | `prometheus-node-exporter`, `prometheus-blackbox-exporter` | `grafana`, `victoriametrics`, `victorialogs`, `vmalert-default`, `alertmanager` |
| legion-node4 | `prometheus-node-exporter`, `garret-pusher`, `garret-puller`, `hath`, `glance`, `gatus`, `restic-backups-actual-budget`, `restic-backups-garret`, `restic-backups-hath` | `actual`, `atuin` |

Anything not named in either column for a node — `sshd`, `netbird`
itself, `nixos-rebuild`, disk or secret operations — is tier 3: no sudo
rule exists anywhere in the fleet for it.

## How to run a fleet command

Your SSH config (`~/.ssh/config`, Nix-managed) resolves `legion-node1`
through `legion-node4` to `hermes-ops@<mesh IP>` with your key already
selected:

```sh
ssh legion-node1 -- sudo systemctl restart crowdsec.service
```

The sudoers rule pins the absolute path
`/run/current-system/sw/bin/systemctl`; a bare `sudo systemctl ...`
resolves there via the invoking user's PATH on every node, so it's the
form to reach for first.

## Logs and metrics

Query `legion-node3` directly rather than SSHing to the node that owns a
unit — its journal collects every node's via `systemd-journal-upload`. Its
mesh IP is the `HostName` of the `legion-node3` entry in `~/.ssh/config`:

```sh
curl -s 'http://<legion-node3 mesh IP>:9428/select/logsql/query' \
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
