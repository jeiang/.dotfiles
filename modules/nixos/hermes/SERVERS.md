# SERVERS.md

> **This file is Nix-managed**, same as `SOUL.md` -- installed fresh on
> every deploy from `modules/nixos/hermes/SERVERS.md`. Don't edit it in
> place; changes go through the `cornn-flaek` repo.

Reference for the Legion fleet you run on and how to query and operate it.
`SOUL.md` has the tier *policy* (when to ask first); this file has the
mechanics.

## Fleet map

Private network `172.17.0.0/24` -- node N is `172.17.0.N`. All nodes are
Hetzner Cloud VPSes running NixOS, deployed from the `cornn-flaek` repo.

- **legion-node1** -- edge (Caddy reverse proxy, CrowdSec)
- **legion-node2** -- NetBird server/proxy, Pocket ID, Blocky DNS
- **legion-node3** -- monitoring (VictoriaMetrics, VictoriaLogs, Grafana,
  vmalert, Alertmanager) + you (Hermes)
- **legion-node4** -- Attic (Nix binary cache), Actual Budget, H@H

Grafana dashboards live at `grafana.jeiang.dev` -- that's for Aidan's
browser, not for you to query.

## The operations tiers -- exact mechanics

Every unit below is start/restart-able mechanically identically (a doas
rule per verb-unit pair, no wildcards) -- the tier-1/tier-2 split is
`SOUL.md`'s confirm-first policy, not something doas enforces. `stop` is
tier 2 for every unit on every node, tier 1 or 2. Anything not listed here
is tier 3: no doas rule permits it, so it will fail no matter what.

| Node | Tier 1 (start/restart free) | Tier 2 (confirm first) |
|---|---|---|
| legion-node1 | `crowdsec.service`, `prometheus-node-exporter.service` | `caddy.service` |
| legion-node2 | `prometheus-node-exporter.service`, `restic-backups-netbird-server.service`, `restic-backups-pocket-id.service` | `netbird-server.service`, `netbird-relay.service`, `netbird-proxy.service`, `pocket-id.service`, `blocky.service` |
| legion-node3 (you) | `hermes-kb-sync.service`, `prometheus-node-exporter.service`, `prometheus-blackbox-exporter.service` | `victoriametrics.service`, `victorialogs.service`, `grafana.service`, `vmalert-default.service`, `alertmanager.service` |
| legion-node4 | `actual.service`, `hath.service`, `atticd.service`, `restic-backups-actual-budget.service`, `restic-backups-hath.service`, `prometheus-node-exporter.service` | *(none)* |

Plus, every node: `netbird status` is tier 1 (read-only); `netbird
expose ...` (via the wrapper below) is tier 2.

## How to run fleet commands

**Nodes 1, 2, 4** (over SSH, from legion-node3 only):

```sh
ssh legion-node1 -- doas systemctl restart caddy.service
```

Your SSH config (`~/.ssh/config`, Nix-managed) makes `legion-node1` /
`legion-node2` / `legion-node4` resolve to `hermes-ops@172.17.0.N` with
your key already selected -- just use the short host alias.

**legion-node3 (yourself)** -- no SSH, run doas directly:

```sh
doas systemctl restart hermes-kb-sync.service
```

**doas invocation caveat**: the doas rules on every node pin the allowed
command to the absolute path `/run/current-system/sw/bin/systemctl`. A
bare `doas systemctl ...` normally resolves to that same path via PATH,
so it's the form to reach for first. If a bare call is ever denied where
you'd expect it to succeed (a shell with a different PATH, for instance),
fall back to the absolute form explicitly:

```sh
doas /run/current-system/sw/bin/systemctl restart caddy.service
```

Both forms are otherwise equivalent.

## Logs: VictoriaLogs

`http://127.0.0.1:9428` on this node (legion-node3). LogsQL via
`/select/logsql/query`. Journald from every node in the fleet ships here
via `systemd-journal-upload`, so you never need to SSH anywhere just to
read logs -- query from here regardless of which node the unit runs on.

Field names are journald's own verbatim field names as VictoriaLogs
ingests them (no renaming): `_HOSTNAME` (the node), `_SYSTEMD_UNIT` (the
unit, e.g. `caddy.service`), `PRIORITY` (numeric syslog level, 0-7, lower
is more severe), `_msg` (the log line itself, from journald's `MESSAGE`),
`_time` (from journald's `__REALTIME_TIMESTAMP`).

Filter by node and unit:

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=_HOSTNAME:legion-node1 AND _SYSTEMD_UNIT:caddy.service' \
  --data-urlencode 'limit=50'
```

Filter by unit only, across the fleet:

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=_SYSTEMD_UNIT:netbird-server.service' \
  --data-urlencode 'limit=50'
```

Errors only (PRIORITY <= 3 is err/crit/alert/emerg), last 15 minutes:

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=PRIORITY:<=3 AND _time:[15m]' \
  --data-urlencode 'limit=50'
```

A specific time window (RFC3339, half-open range):

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=_SYSTEMD_UNIT:pocket-id.service AND _time:[2026-08-04T00:00:00Z, 2026-08-04T06:00:00Z]' \
  --data-urlencode 'limit=100'
```

If a query comes back with unexpected fields, or you're not sure a field
name still matches what's actually being ingested, discover them live
rather than guessing further -- run a broad, unfiltered query with a
small limit and inspect what comes back:

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=*' \
  --data-urlencode 'limit=5'
```

**Fallback -- VictoriaLogs itself is down or unreachable**: read the
node's own journal directly. You're in the `systemd-journal` group on
every node, so this needs no doas.

```sh
ssh legion-node1 -- journalctl -u caddy.service -e
```

On legion-node3 itself, drop the `ssh` and run `journalctl -u
<unit> -e` locally.

## Metrics: VictoriaMetrics

`http://127.0.0.1:8428` on this node (legion-node3). PromQL via
`/api/v1/query` and `/api/v1/query_range`.

```sh
curl -s 'http://127.0.0.1:8428/api/v1/query' --data-urlencode 'query=up'
```

Per-node metrics are scraped under the `node` job (node_exporter).

## netbird expose

`netbird expose <port> [flags]` publishes a local service through the
netbird-proxy on legion-node2 (ADR 0002). It's tier 2: always confirm the
hostname/port with Aidan before running it, and un-expose it when you're
done.

The mechanism is a single-purpose wrapper doas grants unconstrained
arguments to (so the underlying `netbird` binary itself stays
unreachable for anything but `expose`):

```sh
ssh legion-node2 -- doas hermes-ops-netbird-expose 8080
```

(or locally on whichever node holds the service, without the `ssh`
prefix, if that node itself is in the doas grantee list).

**Critical**: `netbird expose` is foreground and long-running -- it holds
the exposure open only while the process itself is running, printing
"Press Ctrl+C to stop exposing." A plain synchronous call will get killed
when your terminal tool's own timeout fires, tearing the exposure down
with it. Background it explicitly, and capture its PID so you can stop it
later, in the same command:

```sh
ssh legion-node2 -- \
  'setsid doas hermes-ops-netbird-expose 8080 > /tmp/netbird-expose-8080.log 2>&1 < /dev/null & echo $! > /tmp/netbird-expose-8080.pid'
```

`setsid` detaches it from the SSH session's controlling terminal so it
outlives that session too, not just your tool's timeout.

**Stopping / listing an exposure**: verified against the pinned netbird
v0.76.1 `client/cmd/expose.go` source -- there is no separate `netbird
expose list` or `netbird expose stop` subcommand, and no CLI
introspection to list what's currently exposed. The exposure exists for
exactly as long as the `netbird expose` process is alive; sending it
SIGTERM (or Ctrl+C interactively) is what tears it down -- the command's
own signal handler cancels the daemon-side stream cleanly, same as a
normal Ctrl+C would. The PID captured above is the right one to kill even
though the visible process image changes twice after that -- `doas`
(OpenDoas) `execvpe`s straight into the wrapper script, which itself
`exec`s straight into the real `netbird` binary; neither step forks, so
the PID never changes across that chain:

```sh
ssh legion-node2 -- kill "$(cat /tmp/netbird-expose-8080.pid)"
```

Track what you've exposed yourself for the lifetime of the conversation
-- there's nowhere else to look it up.
