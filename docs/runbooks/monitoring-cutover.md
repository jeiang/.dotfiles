# Runbook: Monitoring Cutover

Operator runbook for [`docs/MIGRATION.md`](../MIGRATION.md) piece 6.2:
deploying the monitoring composition module
(`modules/nixos/monitoring/default.nix`, piece 6.1) to `legion-node3`,
verifying it, and retiring the Experimental Cluster's `vm/victoria-metrics-k8s-stack`
Helm release. Review [`AGENTS.md`](../../AGENTS.md) before running any
command here.

This runbook assumes [`docs/runbooks/edge-cutover.md`](edge-cutover.md) has
already landed the Edge Node (the `grafana.jeiang.dev` Caddy route exists and
is verified up to the point where it `502`s because piece 6.1 isn't deployed
yet -- expected, not a regression), and that piece 3.4 (Legion nodes as
NetBird peers) has landed on every node, since fleet-wide log shipping and
the raw VictoriaMetrics/VictoriaLogs NetBird exposure both depend on it.

**No Volume moves, no PVC copy.** Per `docs/MIGRATION.md` Confirmed
Decisions, the monitoring stack's state is explicitly reset-allowed --
`legion-node3`'s VictoriaMetrics/VictoriaLogs start with fresh, empty
storage. Nothing here quiesces the Kubernetes deployment before deploying
the host-native one (unlike every other `*-migration.md` runbook); both run
in parallel until this runbook's verification passes, then the old stack is
torn down.

## Prerequisites

### sops secrets

Create all three with `just sops-edit` before deploying `legion-node3` with
`monitoring` enabled (`modules/nixos/monitoring/default.nix` `sops.secrets`):

| Secret | Consumed by | Value |
| --- | --- | --- |
| `grafana/oauth-client-secret` | Grafana's `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` env override | The Pocket ID OIDC client secret for client ID `a70e6d0d-360c-415f-b154-85ec7a6bc352` (`k8s-manifests/monitoring/README.md` "Pocket ID Authentication"). Copy the existing value from Bitwarden Secrets Manager / the live `grafana-oauth` Kubernetes Secret if reusing the same Pocket ID client registration, or generate a fresh one if creating a new client. |
| `grafana/secret-key` | Grafana's `security.secret_key` (file-provider) | A freshly generated random value (e.g. `openssl rand -base64 32`). This is a **new** secret, not carried from the cluster: the pinned nixpkgs Grafana version dropped its built-in default and now requires an explicit key (see "Grafana version note" below). |
| `alertmanager/discord-webhook` | Alertmanager's `DISCORD_WEBHOOK_URL` env override | **Copy the exact live Discord webhook URL** from Bitwarden Secrets Manager / the cluster's `alertmanager-discord` Secret (`k8s-manifests/monitoring/README.md` "Bitwarden Secret") -- this must point at the same Discord channel the operator already monitors, not a fresh webhook. |

No Hetzner Volume prerequisite: monitoring state is node-local disposable
storage (`docs/MIGRATION.md` Confirmed Decisions), not a mounted Volume.

### Grafana version note (nixpkgs 26.05)

The pinned nixpkgs Grafana module asserts `services.grafana.settings.security.secret_key`
has an explicit value -- upstream dropped the old built-in default. This is
unrelated to any value the cluster's Grafana used; a fresh key is correct
here (Grafana uses it only to encrypt secrets it stores in its own database
going forward, and that database starts empty per the reset-allowed
decision above).

### Deploy

```sh
just deploy legion-node3
```

This brings up VictoriaMetrics, VictoriaLogs, Grafana, vmalert, and
Alertmanager together, plus Blocky if piece 5.5 already landed on this node.
Confirm before proceeding:

```sh
ssh node3.jeiang.dev -- sudo systemctl status victoriametrics victorialogs grafana vmalert-default alertmanager
ssh node3.jeiang.dev -- sudo journalctl -u victoriametrics -u victorialogs -u grafana -u vmalert-default -u alertmanager --since -5m
```

### Deploy the fleet (node_exporter + journald upload)

`services.prometheus.exporters.node` and `services.journald.upload` are
fleet-wide (`modules/hosts/legion/default.nix`), not part of the
`monitoring` module itself -- deploy every node so they start shipping to
`legion-node3`:

```sh
just deploy legion-node1
just deploy legion-node2
just deploy legion-node3
just deploy legion-node4
just deploy legion-node5
```

(`legion-node3` is included even though it was just deployed above, so its
own `node_exporter`/`journald.upload` config picks up alongside every other
node's.)

## Verification

### Grafana loads via the edge (pre-DNS)

```sh
curl -sSI --resolve grafana.jeiang.dev:443:178.156.226.145 https://grafana.jeiang.dev/
```

Replace `178.156.226.145` if `legion-node1`'s address has changed
(`modules/hosts/legion/default.nix`). Expect a real response instead of the
pre-piece-6.1 `502` noted in `docs/runbooks/edge-cutover.md`.

### OAuth login via Pocket ID

Log in through the Grafana login page (via the `curl --resolve` host
override above, or a temporary `/etc/hosts` entry, until DNS actually
moves): confirm the Pocket ID SSO button appears (`disable_login_form =
true` hides the local form entirely) and that a test user in each of
`monitoring_admin`, `monitoring_editor`, and `monitoring_reader` receives
the matching Grafana role (`role_attribute_strict = true` --
`modules/nixos/monitoring/default.nix`). A user without one of those groups
should be denied.

### VM targets up

Every scrape target should read `up` in VictoriaMetrics' own target status
page:

```sh
curl -s --resolve grafana.jeiang.dev:443:178.156.226.145 \
  'https://grafana.jeiang.dev/api/datasources/proxy/uid/<victoriametrics-uid>/api/v1/targets' | jq
```

Simpler: SSH in and query VictoriaMetrics directly (loopback, no auth):

```sh
ssh node3.jeiang.dev -- curl -s http://127.0.0.1:8428/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.labels.instance)\t\(.health)"'
```

Expect `up` for every row except `crowdsec` on `legion-node1` if
`edge.crowdsec.enable` hasn't flipped true yet
(`docs/runbooks/edge-cutover.md` "CrowdSec enablement") -- that target
legitimately reads `down` until then, same as the edge's own routes that
`502` pre-cutover elsewhere in this repo. If any *other* target is down,
check the corresponding service's own runbook/module before proceeding
(`caddy` needs the edge's `admin` API reachable at
`172.17.0.1:2019`, `netbird-server` needs piece 3.1 deployed, `blocky`
needs piece 5.5 deployed, `node` needs the fleet deploy above to have
landed on every node).

### VL receiving journald from all nodes

```sh
ssh node3.jeiang.dev -- curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=* | stats by (hostname) count()' | jq
```

Expect one row per Legion node (`legion-node1` through `legion-node5`,
however each ships its `hostname` field). If a node is missing, check its
own `systemd-journal-upload.service` status:

```sh
ssh node<N>.jeiang.dev -- sudo systemctl status systemd-journal-upload
ssh node<N>.jeiang.dev -- sudo journalctl -u systemd-journal-upload --since -5m
```

### vmalert rules loaded

```sh
ssh node3.jeiang.dev -- curl -s http://127.0.0.1:8428/api/v1/rules | jq '.data.groups[].rules[].name'
```

Expect `TargetDown`, `HighDiskUsage`, `HighMemoryUsage`
(`modules/nixos/monitoring/default.nix` `vmalert.instances.default.rules`).

### A test alert reaches Discord

Post a synthetic alert directly to Alertmanager's API (mirrors
`k8s-manifests/monitoring/README.md` "Verify" -- `TestAlert` is not a real
alert name, safe to run any time):

```sh
ssh node3.jeiang.dev -- curl -s -XPOST http://127.0.0.1:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"TestAlert","severity":"info"}}]'
```

Or, if `amtool` is available locally against a forwarded port
(`ssh -L 9093:127.0.0.1:9093 node3.jeiang.dev`):

```sh
amtool alert add alertname=TestAlert severity=info --alertmanager.url=http://127.0.0.1:9093
```

A message should appear in the configured Discord channel within a few
seconds. If nothing arrives, confirm the webhook secret mounted correctly:

```sh
ssh node3.jeiang.dev -- sudo systemctl show alertmanager -p EnvironmentFiles
ssh node3.jeiang.dev -- sudo journalctl -u alertmanager --since -10m | grep -i discord
```

## DNS cutover

`grafana.jeiang.dev` is covered by the `*.jeiang.dev` wildcard certificate
the edge already manages (`modules/nixos/edge/default.nix`), but its A/AAAA
record moves individually, not automatically with the wildcard. It rides
the same `jeiang.dev` zone `docs/runbooks/edge-cutover.md`'s "Staged DNS
cutover" already covers -- that runbook explicitly places
`grafana.jeiang.dev` in the group of hosts "only once each service's own
migration piece ... has actually deployed and been verified per its own
runbook" (piece 6.1): this runbook is that verification. Move
`grafana.jeiang.dev` only after every check above passes, then repeat the
edge-cutover.md per-host verification (same `curl` check, without
`--resolve`, from outside the Hetzner private network; check
`ssh node1.jeiang.dev -- tail -f /var/log/caddy/access.log` for the new
traffic).

Rollback: point the `grafana.jeiang.dev` A/AAAA record back at the Hetzner
Load Balancer. The Kubernetes deployment (kept running throughout this
runbook, see "Old-stack teardown" below) resumes serving immediately -- no
service-side action needed.

## NetBird exposure verification

Raw VictoriaMetrics (8428) and VictoriaLogs (9428) are reachable from
NetBird peers only (`modules/nixos/monitoring/default.nix`, same mechanism
as `modules/nixos/blocky.nix`). From an already-enrolled peer (e.g.
`artemis`), confirm both are reachable over the tunnel using
`legion-node3`'s NetBird peer address (not its `172.17.0.3` private
address -- that only works from another Legion node over `enp7s0`; from
`artemis` it must be the NetBird-assigned address):

```sh
netbird status   # find legion-node3's peer IP, or check the NetBird dashboard
curl -s http://<node3-peer-ip>:8428/api/v1/status/tsdb | jq
curl -s http://<node3-peer-ip>:9428/select/logsql/query --data-urlencode 'query=* | limit 1' | jq
```

Both should respond (VM's TSDB status endpoint, a single VL log line).

### Blocky nameserver cross-reference (5.7)

`docs/runbooks/apps-migration.md`'s "NetBird DNS Repoint" section (piece
5.7) notes that the shared NetBird `NetworkRouter`/`netbird-resources`
chart's full removal waits on **both** Blocky's own `NetworkResource`
(removed there) and monitoring's own `NetworkResource`s
(`k8s-manifests/monitoring/vmsingle-networkresource.yaml`,
`vlsingle-networkresource.yaml`) being superseded by the exposure verified
above. Only remove the shared chart once **both** pieces 5.5/5.7 and this
runbook have reached this point -- if Blocky (5.5) hasn't cut over yet,
leave the shared `NetworkRouter`/`netbird-resources` chart alone even after
finishing this section.

## Old-stack teardown

Reset-allowed (`docs/MIGRATION.md` Confirmed Decisions: "The monitoring
stack ... state may be reset") -- unlike every other `*-migration.md`
runbook, this teardown does **not** require a Restic backup/restore
verification first (there is no `backupSet` for `monitoring`; old VM/VL
data is deliberately discarded, not migrated). Cutover Safety Rule 1 does
not apply here for that reason.

**Do not tear down early.** Keep the Kubernetes `monitoring` release
running until every check in "Verification" above has passed and DNS has
actually cut over -- alerting must not have a gap between the old stack
going away and the new one being confirmed live (`docs/MIGRATION.md`
Confirmed Decisions: "Alerting is retained"). Once DNS cutover and NetBird
exposure verification are both done:

```sh
kubectl -n monitoring get pods,pvc,ingress   # confirm what exists before deleting
helm -n monitoring uninstall monitoring
kubectl -n monitoring delete pvc --all       # PVC cleanup allowed without restore verification (reset-allowed)
kubectl delete namespace monitoring
```

This also removes the cluster's `vmsingle-monitoring-victoria-metrics-k8s-stack`/
`vlsingle-monitoring-victoria-metrics-k8s-stack` `NetworkResource`s (they're
namespaced objects deleted with the namespace) -- re-check the "Blocky
nameserver cross-reference" note above before assuming the *shared*
`NetworkRouter`/`netbird-resources` chart can also go; that's governed by
whichever migration piece is the last consumer, not this one.

## Explicit non-steps

- **Hetzner Load Balancer deletion, Traefik removal, and K3s teardown** are
  Phase 7 only (Cutover Safety Rule 3). Nothing in this runbook touches any
  of them.
- **The shared NetBird `NetworkRouter`/`netbird-resources` chart's full
  removal**: only the `monitoring` namespace's own release/`NetworkResource`s
  are removed above; the shared chart stays until nothing else depends on it
  (see "Blocky nameserver cross-reference" above).
- **CrowdSec dashboard data backfill**: the carried CrowdSec dashboard
  (`modules/nixos/monitoring/crowdsec-dashboard.json`) shows no historical
  data from the cluster -- VictoriaMetrics starts empty (reset-allowed).
  Panels populate going forward only, once `edge.crowdsec.enable` is on and
  CrowdSec has emitted matching metrics.
- **Node/VM dashboards beyond CrowdSec**: `k8s-manifests/monitoring/values.yaml`
  never pinned specific dashboard IDs for the upstream chart's own
  sidecar-loaded node/VM dashboards, so none are carried here -- a
  documented gap (`modules/nixos/monitoring/default.nix`), not an oversight.
  Add them by hand in Grafana, or via a future declarative dashboard
  provider entry, if needed.
- **Alert rule parity**: the chart relied on the upstream
  `vm/victoria-metrics-k8s-stack`'s bundled Kubernetes-specific default
  rules, none of which apply to a single host-native node. The rule set
  deployed here (`TargetDown`, `HighDiskUsage`, `HighMemoryUsage`) is a
  deliberately minimal starting point (`docs/MIGRATION.md` piece 6.1's
  fallback), not a 1:1 carry-over -- expand it as gaps are found in
  practice.
