# SERVERS.md

> **This file is Nix-managed**, same as `SOUL.md` -- installed fresh on
> every deploy from `modules/nixos/hermes/SERVERS.md`. Don't edit it in
> place; changes go through the `cornn-flaek` repo.

Reference for the Legion fleet you run on and how to query it.

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

## Metrics: VictoriaMetrics

`http://127.0.0.1:8428` on this node (legion-node3). PromQL via
`/api/v1/query` and `/api/v1/query_range`.

```sh
curl -s 'http://127.0.0.1:8428/api/v1/query' --data-urlencode 'query=up'
```

Per-node metrics are scraped under the `node` job (node_exporter).

## Logs: VictoriaLogs

`http://127.0.0.1:9428` on this node. LogsQL via `/select/logsql/query`.
Journald from every node in the fleet ships here.

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=error' \
  --data-urlencode 'limit=10'
```
