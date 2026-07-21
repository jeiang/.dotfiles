# Runbook: NetBird Migration

Operator runbook for [`docs/MIGRATION.md`](../MIGRATION.md) piece 3.3: moving
the NetBird management/signal server, relay, and reverse proxy from the
Experimental Cluster (`k8s-manifests/netbird` chart) to `legion-node2`
(`modules/nixos/netbird-server/`, pieces 3.1/3.2). Review
[`AGENTS.md`](../../AGENTS.md) before running any command here, and
[`docs/runbooks/restore.md`](restore.md) for the Restic mechanics this
runbook's Safety Rule 1 step depends on, and
[`docs/runbooks/secrets-preflight.md`](secrets-preflight.md) before your
first deploy of `legion-node2` with these services enabled.

This runbook assumes [`docs/runbooks/edge-cutover.md`](edge-cutover.md) has
already landed the Edge Node (Caddy routes for `netbird.jeiang.dev` and the
layer-4 passthrough for `proxy.jeiang.dev`/`*.proxy.jeiang.dev` exist and are
verified up to the point where they 502/hang because pieces 3.1/3.2 aren't
deployed yet — that is expected, not a regression). It does **not** cut DNS
for any other Edge Node host, and does not touch the Hetzner Load Balancer,
Traefik, or K3s (Cutover Safety Rule 3, Phase 7 only).

## Prerequisites

### sops secrets

Create these with `just sops-edit` before deploying `legion-node2` with
`netbird-server`/`netbird-proxy` enabled:

| Secret | Consumed by | Value |
| --- | --- | --- |
| `netbird/store-encryption-key` | `modules/nixos/netbird-server/default.nix` | **Copy the exact value from Bitwarden Secrets Manager.** This is not a fresh secret: it decrypts fields already written to the retained SQLite DB by the live cluster server. A different value makes the copied database unreadable. |
| `netbird/relay-auth-secret` | same | Copy from Bitwarden (shared secret between server and relay; a new value forces every existing peer to re-fetch relay credentials on next `credentialsTTL` refresh (24h) instead of working immediately). |
| `netbird/idp-session-cookie-encryption-key` | same | Copy from Bitwarden (NetBird's own embedded-IdP session cookie key; a new value only invalidates active dashboard-owner sessions, not peer connectivity, but copy it anyway for continuity). |
| `netbird/setup-key` | `modules/hosts/legion/default.nix` (piece 3.4, fleet peer enrollment) | A NetBird setup key. Reuse an existing reusable setup key from the live server's dashboard (Settings → Setup Keys) if one is already provisioned for the fleet, or create a new one there — this is unrelated to the state copy below and can be generated before or after it. |
| `netbird/proxy-token` | `modules/nixos/netbird-server/proxy.nix` | **Reuse the existing `nbx_...` token from Bitwarden Secrets Manager** (chart secret `proxyToken`, Bitwarden ID `dacb7eb2-4cdf-45de-9541-b47300025e5d` per `k8s-manifests/netbird/README.md`). It's a row in the retained SQLite DB, not a value the running server process holds in memory — it moves with the state copy below and keeps working. Only regenerate it if it turns out to have been lost or revoked (see "If the proxy token doesn't work" below). |
| `crowdsec/bouncer-netbird-proxy-key` | `modules/nixos/crowdsec/default.nix` (LAPI registration, node1) and `modules/nixos/netbird-server/proxy.nix` (bouncer client, node2) | Already created per `docs/runbooks/edge-cutover.md`'s CrowdSec enablement step. Grant `legion-node2` access to the existing secret with `just sops-updatekeys` before deploying node2 — do not create a second value. |
| `netbird-proxy/hetzner-dns-token` | `modules/nixos/netbird-server/proxy.nix` (`security.acme` DNS-01) | Same Hetzner DNS API token value as the edge's `caddy/hetzner-dns-token` (`modules/nixos/edge/default.nix`) — one Hetzner API token, stored under a second secret name because sops-nix secrets are keyed per recipient host. |

`restic/password` and `restic/s4-env` are prerequisites of piece 2.1, not
this runbook — see `docs/runbooks/restore.md` if they don't already exist.

### Hetzner Volume

Provision and mount a Hetzner Volume at `/mnt/netbird` on `legion-node2`
before the first deploy with `netbird-server` enabled — follow
[`docs/runbooks/volume-provisioning.md`](volume-provisioning.md) end to
end (create the Volume with `hcloud`, paste its ID into the
`legion-node2-netbird` inventory entry's `hcloudVolumeId` in
`modules/hosts/legion/_service-inventory.nix`, deploy). This replaces the
old "add an `/etc/fstab` line by hand" instruction: the mount is now
declarative (`modules/hosts/legion/default.nix` derives `fileSystems` from
the inventory) and guarded (`netbird-server.service` won't start unless
`/mnt/netbird` is actually mounted). Confirm it's mounted
(`ssh node2.jeiang.dev -- findmnt /mnt/netbird`) before proceeding — until
then the guarded unit simply won't start (`ConditionPathIsMountPoint`
fails), the expected state before this step, not a failure.

`netbird-proxy` needs no Volume of its own — piece 3.2 determined the proxy
consumes an externally-provisioned static wildcard certificate instead of
its own ACME state, so it carries no required persistent data
(`modules/hosts/legion/_service-inventory.nix`'s `netbird-proxy` entry
declares `stateful = false` and no `volume`).

### Hetzner Cloud Firewall

Confirm inbound UDP `3478` (STUN) is allowed to `legion-node2`'s public IPs
(`178.156.201.35` / `2a01:4ff:f0:a1ff::1`,
`modules/hosts/legion/default.nix` `legionNodes.legion-node2`) — this is
already fleet-wide per piece 0.2's interim STUN allowance, so likely no
change is needed, but confirm rather than assume. `legion-node2`'s port 443
(server/relay backends, `netbird-proxy`) only needs to be reachable from
`legion-node1` over the private network (`enp7s0`, already trusted) — do not
open it publicly; DNS points `proxy.jeiang.dev` at the edge, not directly at
node2.

### Deploy

```sh
just deploy legion-node2
```

This brings up `netbird-server`, `netbird-relay`, and `netbird-proxy` with
empty state (no PVC content copied yet) — intentional, so you can confirm
the units start cleanly before trusting them with the copied database in the
next section. Confirm before proceeding:

```sh
ssh node2.jeiang.dev -- sudo systemctl status netbird-server netbird-relay netbird-proxy
ssh node2.jeiang.dev -- sudo journalctl -u netbird-server -u netbird-relay -u netbird-proxy --since -5m
```

Expect `netbird-server` to come up with a **fresh, empty** database at this
point (it hasn't received the copied state yet) and `netbird-proxy` to fail
its ACME issuance if `proxy.jeiang.dev`/`*.proxy.jeiang.dev` DNS doesn't
point at the edge yet — that's expected pre-cutover; recheck after the DNS
step below. `acme-proxy.jeiang.dev.service` logs the issuance attempt:

```sh
ssh node2.jeiang.dev -- sudo systemctl status acme-proxy.jeiang.dev.service
ssh node2.jeiang.dev -- sudo journalctl -u acme-proxy.jeiang.dev.service --since -10m
```

## Values migration from Bitwarden Secrets Manager

Per the table above: copy `store-encryption-key`, `relay-auth-secret`,
`idp-session-cookie-encryption-key`, and `proxy-token` from Bitwarden
Secrets Manager into the matching sops secrets — these four must keep their
exact live values for the retained database to stay readable and for the
existing proxy token row to keep validating. `crowdsec/bouncer-netbird-proxy-key`
is a **new** value (CrowdSec state resets per `docs/MIGRATION.md` Confirmed
Decisions) already handled by `docs/runbooks/edge-cutover.md`.
`netbird-proxy/hetzner-dns-token` is a copy of an existing operational
secret (the Hetzner DNS API token), not a Bitwarden-sourced NetBird value.

### If the proxy token doesn't work

If `netbird-proxy` logs an authentication failure against the management
server after the state copy below (token invalid/revoked), regenerate one
on `legion-node2` directly instead of via `kubectl exec` (the chart's
equivalent command, `k8s-manifests/netbird/README.md`, adapted to the
systemd deployment):

```sh
ssh node2.jeiang.dev
sudo systemctl show netbird-server -p ExecStart --value   # note the binary path, e.g. /nix/store/...-netbird-server-0.74.3/bin/netbird-server
sudo -u netbird <binary-path> token create \
  --name proxy-jeiang \
  --config /run/secrets/rendered/netbird-server-config.yaml
```

Save the printed `nbx_...` token immediately (shown once), update Bitwarden
Secrets Manager and the `netbird/proxy-token` sops secret with the new
value, then `just deploy legion-node2` again to pick it up.

## State copy (Safety Rules 1 and 2)

### Quiesce the Kubernetes deployment

```sh
kubectl -n netbird scale deployment/netbird-server --replicas=0
kubectl -n netbird scale deployment/netbird-relay --replicas=0
kubectl -n netbird scale deployment/netbird-proxy --replicas=0
kubectl -n netbird get pods   # confirm all three have terminated
```

Leave `netbird-dashboard` running for now — it serves no state and the edge
already serves the dashboard statically (piece 1.2), so it doesn't need to
be part of this cutover at all; scale it down only when convenient.

### Copy PVC content to the Volume

The chart's server state lives at `/var/lib/netbird` inside the PVC
(`k8s-manifests/netbird/values.yaml` `server.dataDir`,
`templates/server.yaml` volume mount); the module's equivalent is
`/mnt/netbird`, owned by the `netbird` user/group
(`modules/nixos/netbird-server/default.nix`). With the deployment scaled to
zero, nothing else holds the PVC open, so mount it into a disposable pod to
copy out:

```sh
kubectl -n netbird run netbird-pvc-copy --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"netbird-pvc-copy","image":"alpine:3.20","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/var/lib/netbird"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"netbird-server"}}]}}'
kubectl -n netbird wait --for=condition=Ready pod/netbird-pvc-copy --timeout=60s
kubectl -n netbird exec netbird-pvc-copy -- tar czf /tmp/netbird-data.tar.gz -C /var/lib/netbird .
kubectl -n netbird cp netbird/netbird-pvc-copy:/tmp/netbird-data.tar.gz ./netbird-data.tar.gz
kubectl -n netbird delete pod netbird-pvc-copy
```

Transfer to `legion-node2` and extract with the module's expected ownership
(the chart's server container runs without an explicit `securityContext`, so
the archive's UID/GID are not meaningful here — always chown to the module's
user by name, not by preserving the source UID):

```sh
scp ./netbird-data.tar.gz deploy@node2.jeiang.dev:/tmp/
ssh node2.jeiang.dev -- sudo tar xzf /tmp/netbird-data.tar.gz -C /mnt/netbird
ssh node2.jeiang.dev -- sudo chown -R netbird:netbird /mnt/netbird
ssh node2.jeiang.dev -- sudo rm /tmp/netbird-data.tar.gz
rm ./netbird-data.tar.gz
```

There is no proxy ACME state to copy (piece 3.2's static-cert decision means
`netbird-proxy` never had its own ACME material to begin with — nothing in
the chart's `proxy.persistence` PVC needs to move here; that PVC held
TLS-ALPN-01 state the module doesn't use).

### Start the copied state and back it up

```sh
ssh node2.jeiang.dev -- sudo systemctl restart netbird-server netbird-relay
ssh node2.jeiang.dev -- sudo journalctl -u netbird-server --since -2m
```

Confirm the server started against the copied database (existing peers,
accounts, and settings visible — check via the dashboard once DNS moves
below, or query the SQLite file directly:
`sudo sqlite3 /mnt/netbird/<store-file> "PRAGMA integrity_check;"` if you
need to check before DNS cutover; the exact filename is whatever the copied
`/var/lib/netbird` contained — `ls /mnt/netbird` after the copy tells you).

Now exercise Safety Rule 1 for real, against the copied-in state (not empty
state from the earlier deploy check): confirm a backup runs and restore it
to a scratch directory per `docs/runbooks/restore.md`'s full procedure.

```sh
ssh node2.jeiang.dev -- sudo systemctl start restic-backups-netbird-server.service
ssh node2.jeiang.dev -- sudo systemctl status restic-backups-netbird-server.service
```

Then follow `docs/runbooks/restore.md` "List snapshots" → "Restore to a
scratch directory" → "Verify content" against
`s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/legion-node2/netbird-server`.
Record the verification (date, snapshot ID) here once done — this clears
Safety Rule 1 for NetBird's eventual Kubernetes release removal below.

Safety Rule 2 (retain the PVC/Volume for the rollback window): **do not**
delete the `netbird-server`/`netbird-relay`/`netbird-proxy` PVCs or flip
their reclaim policy yet. That's part of "Post-verify" below, after the
rollback window has passed.

## Cutover

### Deploy node2 with copied state

```sh
just deploy legion-node2
```

### Start-order verification

```sh
ssh node2.jeiang.dev -- sudo systemctl status netbird-server netbird-relay netbird-proxy
ssh node2.jeiang.dev -- sudo journalctl -u netbird-server -u netbird-relay -u netbird-proxy --since -5m
```

`netbird-proxy` depends on `netbird-server` (`Wants`/`After`, not
`Requires` — `modules/nixos/netbird-server/proxy.nix`) and on
`acme-proxy.jeiang.dev.service` for its first certificate. If the proxy's
DNS-01 challenge is still failing at this point, confirm
`netbird-proxy/hetzner-dns-token` decrypted correctly
(`sudo cat /run/secrets/rendered/netbird-proxy-hetzner-dns.env` — should show
`HETZNER_API_TOKEN=...`, not an error) before assuming it's a DNS-propagation
timing issue.

### DNS cutover

Lower TTLs at least a day ahead, same convention as
`docs/runbooks/edge-cutover.md`. Move only once the corresponding backend
above is verified healthy:

| Host | Target | Notes |
| --- | --- | --- |
| `netbird.jeiang.dev` | `legion-node1` (edge) | A/AAAA record; the edge's existing route (`modules/nixos/edge/default.nix`) now has a live backend at `legion-node2:80`. |
| `stun.netbird.jeiang.dev` | `legion-node2` public IPv4/IPv6 directly | **Not** through the edge — Caddy/Hetzner LBs can't proxy UDP STUN. |
| `proxy.jeiang.dev`, `*.proxy.jeiang.dev` | `legion-node1` (edge) | A/AAAA record(s); the edge's layer-4 SNI passthrough now has a live backend at `legion-node2:443`. |

Per-host verification after each move (repeat outside the Hetzner private
network, without `--resolve`, and check
`ssh node1.jeiang.dev -- tail -f /var/log/caddy/access.log` for the new
traffic on the edge):

```sh
curl -sSI https://netbird.jeiang.dev/
openssl s_client -connect legion-node1-public-ip:443 -servername proxy.jeiang.dev </dev/null
```

Rollback per host: point the A/AAAA record(s) back at the Hetzner Load
Balancer (`netbird.jeiang.dev`, `proxy.jeiang.dev`/`*.proxy.jeiang.dev`) or
the old labeled relay node's public address (`stun.netbird.jeiang.dev`). The
low TTL means this propagates quickly. See "Rollback" below for what
scaling the Kubernetes deployment back up does and doesn't undo.

## Verification

- **Existing peer reconnects.** On `artemis` (already a NetBird client) and
  any already-enrolled Legion node (piece 3.4):
  ```sh
  netbird status
  ```
  Expect the peer to still show connected without re-running `netbird up` —
  the management URL (`netbird.jeiang.dev:443`,
  `modules/nixos/netbird.nix`) didn't change, only what answers it did.
  If a peer shows disconnected, `sudo netbird down && sudo netbird up` to
  force a fresh handshake against the new server.
- **Dashboard loads via the edge**: open `https://netbird.jeiang.dev` in a
  browser; confirm it's the same account/peer list as before the copy (not
  a fresh empty install — that would mean the state copy didn't take).
- **Pocket ID-federated login**: from the dashboard's login screen, use the
  Pocket ID SSO option (configured at runtime in NetBird's GUI settings
  before this migration, per `docs/MIGRATION.md` piece 3.1's auth note —
  the federation config lives in the retained database and moved with the
  copy). Confirm login succeeds against `auth.jeiang.dev`, which is still
  cluster-hosted (Phase 4 hasn't landed) — this checks that both halves of
  the retained-vs-still-clustered split still talk to each other correctly
  after the move.
- **STUN reachable**:
  ```sh
  turnutils_stunclient stun.netbird.jeiang.dev
  ```
  Expect a resolved external mapped address in the output, not a timeout.
- **Relay path works**: force a peer to use the relay (e.g. block direct
  UDP between two test peers, or just inspect an existing relayed
  connection) and confirm via `netbird status --detail` that a connection
  type shows `relayed` through `rels://netbird.jeiang.dev:443`, and check
  `ssh node2.jeiang.dev -- sudo journalctl -u netbird-relay --since -10m`
  for accepted connections.
- **A published `*.proxy.jeiang.dev` resource serves with a valid
  certificate**: create (or use an existing) Reverse Proxy service in the
  NetBird dashboard, then:
  ```sh
  curl -vI https://<service>.proxy.jeiang.dev/ 2>&1 | grep -i "subject\|issuer\|HTTP/"
  ```
  Expect a certificate issued for `*.proxy.jeiang.dev` (the DNS-01 wildcard
  from `security.acme`, not a self-signed/placeholder cert) and a real HTTP
  response from the published backend, proving both the edge's raw SNI
  passthrough and the proxy's static-cert TLS termination work end to end.
- **Proxy's CrowdSec bouncer registered**:
  ```sh
  ssh node1.jeiang.dev -- sudo cscli bouncers list
  ```
  Expect `netbird-proxy` present and not revoked (registered by
  `modules/nixos/crowdsec/default.nix`'s `crowdsec-bouncers` service on
  node1 — the bouncer *client* runs on node2, but it authenticates against
  node1's LAPI, so the registration and the "is it actually being used"
  check both happen from node1). Per-service enforcement is off by default
  (NetBird dashboard → Reverse Proxy → Services → CrowdSec mode); start any
  service you enable it for in `observe` mode before `enforce`, matching
  the chart's prior operational guidance
  (`k8s-manifests/netbird/README.md`).

## Rollback

```sh
kubectl -n netbird scale deployment/netbird-server --replicas=1
kubectl -n netbird scale deployment/netbird-relay --replicas=1
kubectl -n netbird scale deployment/netbird-proxy --replicas=1
```

Then revert the DNS records per host, per "DNS cutover" above.

**State divergence warning**: any peer, setup key, or Reverse Proxy service
created or changed *after* cutover (while `legion-node2`'s server was live)
exists only in `/mnt/netbird`'s database, not in the Kubernetes PVC. Scaling
the Kubernetes deployment back up resumes it from the state as of the copy
above — a rollback after real usage discards everything that happened on
the new server in between. Only roll back if you catch a problem quickly;
past that window, fix forward instead.

## Post-verify (gated on Safety Rules)

Only after:

- Safety Rule 1: the Restic backup + scratch-directory restore above is
  recorded as verified.
- Safety Rule 2's rollback window (default two weeks per
  `docs/MIGRATION.md`) has elapsed with the host-native server stable.

Retain or detach the PVCs' backing Hetzner Volumes (flip the PV reclaim
policy to `Retain`, or manually detach after deletion — `hcloud-volumes`
defaults to `Delete`) **before** removing the release:

```sh
kubectl -n netbird patch pv <netbird-server-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl -n netbird patch pv <netbird-proxy-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

Then remove the release and its operator-managed dependents (dropped per
`docs/MIGRATION.md` Confirmed Decisions — Kubernetes-only concerns, not
migrated):

```sh
helm -n netbird uninstall netbird
# NetBird Kubernetes operator + netbird-resources chart, per the same
# Confirmed Decisions entry:
helm -n <operator-namespace> uninstall netbird-operator
helm -n <operator-namespace> uninstall netbird-resources
```

**`legion-node5`'s relay label**: `k8s-manifests/netbird/values.yaml`
schedules the relay via `nodeSelector: {netbird.io/stun: "true"}`; confirm
which node currently carries it before assuming it's still wherever the
chart's README example (`legion-node1`) suggests —
`modules/hosts/legion/default.nix` notes the relay "has moved nodes before".

```sh
kubectl get nodes -l netbird.io/stun=true
```

If it's `legion-node5`, no action is needed here — the label serves no
further purpose once `stun.netbird.jeiang.dev` points at `legion-node2`
(above) and disappears naturally when the relay `Deployment` is removed by
the `helm uninstall` above. It's called out here only so Phase 7's
`legion-node5` decommission runbook doesn't need to rediscover it: node5
owns no NetBird workload or Volume after this runbook completes, regardless
of which node held the label.
