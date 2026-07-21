# Runbook: Destructive Big-Bang Migration (Host-Native Cutover)

**Operator runbook. Read this entire document before touching anything.**
This supersedes the staged/coexistence approach in
[`docs/MIGRATION.md`](docs/MIGRATION.md) and `docs/runbooks/{edge-cutover,
netbird-migration,pocket-id-migration,apps-migration,monitoring-cutover}.md`
for this cutover window. Coexistence is not possible: `flake.lock` and the
kernel have moved forward (every node needs a reboot to pick up the new
kernel), and the live K3s cluster runs fleet-wide daemonsets (Kyverno,
the NetBird Kubernetes operator) that would block a partial/rolling deploy
against a mixed old/new fleet. Instead, this is a **single maintenance
window, total-downtime, in-place cutover**: every retained-data volume
moves by physical `hcloud volume detach`/`attach`, not by copying files;
K3s is torn down fleet-wide; every node is rebuilt in place and rebooted;
then DNS and the Hetzner Load Balancer cut over together.

Review [`AGENTS.md`](AGENTS.md) before running any command here. This
runbook does not replace `docs/runbooks/secrets-preflight.md` — its
"Confirm sops secrets are committed" prerequisite still applies (see
Section 0.3 below).

## 0. Overview

### 0.1 Why in-place `deploy-rs`, not a reinstall

Every node keeps its **existing root disk** and is rebuilt with `deploy-rs`
activation, then rebooted for the new kernel — it is **not** reinstalled via
`nixos-anywhere`/`clean-deploy`/disko. This is deliberate: each node's
`/etc/ssh/ssh_host_ed25519_key` must survive, because sops-nix derives its
age decryption recipient from that host key
(`modules/nixos/sops/default.nix`'s per-host key list keys off the host's
SSH key). A reinstall generates a fresh host key, which would make every
sops secret on that node undecryptable at the next activation — including
the very secrets (`netbird/store-encryption-key`, `pocket-id/encryption-key`,
etc.) this migration depends on to keep the retained databases readable. A
reboot after an in-place `deploy-rs` activation does not touch the host key
at all.

### 0.2 Downtime warning

Every public service (`jeiang.dev`, `auth.jeiang.dev`, `netbird.jeiang.dev`,
`attic.jeiang.dev`, `budget.jeiang.dev`, H@H, etc.) goes down for the
duration of this window, from Section 3 (quiesce K3s) until each service is
verified live again in Section 11. There is no partial/rolling path — this
is accepted (operator-approved).

### 0.3 Prerequisites

- `hcloud` CLI configured against the Hetzner Cloud project (`hcloud
  context list` shows an active context).
- `kubectl` still works against the live K3s cluster (this stops being true
  partway through Section 3).
- `modules/nixos/sops/secrets.yaml` is committed on this branch with real
  values for every key `docs/runbooks/secrets-preflight.md` lists — this
  runbook does not create any new secret, so if a key from that table is
  still a placeholder, deploys in Section 7 will fail activation partway
  through. Confirm before starting:
  ```sh
  git log -1 --format=%H -- modules/nixos/sops/secrets.yaml
  git status --porcelain modules/nixos/sops/secrets.yaml   # expect empty
  ```
- You are on the branch/commit intended for this deploy, and `nix flake
  check --impure --keep-going` passes before you begin.
- `just` is available (repo dev shell — see `AGENTS.md` Development
  Environment).

### 0.4 Assumption flagged for operator confirmation

**`legion-node5` is rebuilt into the new serviceless config in Section 7 for
fleet consistency (same kernel, same K3s-disabled state as every other
node) — its actual decommission (server deletion, removal from the flake's
node inventory and `deploy.nodes`) is Phase 7.3 work, deferred to a later
session, not this window.** See Section 12. Confirm this is still the
intent before running Section 7's node5 step; if node5 should instead be
left untouched this window, skip its rebuild and treat it as out of scope
until Phase 7.3.

### 0.5 Superseded inventory state: `hcloudVolumeId` values are stale for this plan

`modules/hosts/legion/_service-inventory.nix` already has `hcloudVolumeId`
values committed for all four retained-data services (`106426277`
netbird-server, `106426282` pocket-id, `106426288` actual-budget,
`106426290` hath). **These are not the volumes this runbook reuses.**
`docs/MIGRATION.md`'s "Storage: Hetzner Volumes" section and
`docs/runbooks/volume-provisioning.md` describe a different, superseded
plan: provision a **brand-new**, empty Hetzner Volume per service and copy
PVC data into it via `tar`/`kubectl cp`. `docs/MIGRATION.md`'s own status
line confirms "No service has cut over yet" — those four volume IDs are new
and still empty. This runbook's confirmed strategy instead **detaches the
existing K3s CSI volumes** (the ones already holding the live PVC data) and
reattaches them directly to the target host node — no new volume, no file
copy. Section 5 overwrites those four `hcloudVolumeId` values with the CSI
volume IDs discovered in Section 1. Do not reuse the currently-committed
IDs; they point at empty disks. They stay attached-or-idle as a mid-flight
fallback and are only deleted once Section 11's verification is stable —
see Section 14.

---

## 1. Precursor discovery (while K3s is still up)

Do all of this before touching anything destructive. Capture the output —
you need it in later sections and in a rollback.

### 1.1 Node inventory

Already fixed in the repo (`modules/hosts/legion/default.nix`
`legionNodes`); record it for reference during the window:

| Node | Private IPv4 | Public IPv4 | Public IPv6 | Hostname |
| --- | --- | --- | --- | --- |
| legion-node1 (edge, bootstrap) | 172.17.0.1 | 178.156.226.145 | 2a01:4ff:f0:6b8e::1 | node1.jeiang.dev |
| legion-node2 (NetBird/identity) | 172.17.0.2 | 178.156.201.35 | 2a01:4ff:f0:a1ff::1 | node2.jeiang.dev |
| legion-node3 (monitoring) | 172.17.0.3 | 178.156.186.147 | 2a01:4ff:f0:c52a::1 | node3.jeiang.dev |
| legion-node4 (apps) | 172.17.0.4 | 178.156.191.180 | 2a01:4ff:f0:ca96::1 | node4.jeiang.dev |
| legion-node5 (empty) | 172.17.0.6 | 178.156.253.100 | 2a01:4ff:f4:13f7::1 | node5.jeiang.dev |

### 1.2 PV → PVC → Hetzner Volume ID mapping for the four retained services

```sh
kubectl get pv -o custom-columns='NAME:.metadata.name,NS:.spec.claimRef.namespace,PVC:.spec.claimRef.name,VOLUME_ID:.spec.csi.volumeHandle,RECLAIM:.spec.persistentVolumeReclaimPolicy,SIZE:.spec.capacity.storage' \
  | grep -E 'NAME|netbird-server|idp-pocket-id|actual-budget|hath'
```

Confirm the PVC names match what the existing runbooks already documented
(`netbird` ns / `netbird-server` PVC, `idp` ns / `idp-pocket-id` PVC,
`actual-budget` ns / `actual-budget` PVC, `hath` ns / `hath` PVC) — if any
differ, use the actual name from this output for the rest of this runbook,
not the assumed one. Record each `VOLUME_ID` (the hcloud-csi driver's
`volumeHandle` is the numeric Hetzner Volume ID as a string) — these four
numbers are what Section 5 writes into `hcloudVolumeId`.

**Patch each retained PV's reclaim policy to `Retain` now**, before doing
anything else, so tearing down K3s or releasing the PVC can never trigger
`hcloud-volumes`' default `Delete` reclaim policy against a volume you're
about to reuse:

```sh
kubectl patch pv <netbird-server-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl patch pv <idp-pocket-id-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl patch pv <actual-budget-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl patch pv <hath-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

(`<...-pv-name>` is the `NAME` column from the `kubectl get pv` output
above, not the PVC name.)

### 1.3 Which node each volume is currently attached to

```sh
hcloud volume list -o columns=id,name,size,server,linux_device
```

Cross-reference the four `VOLUME_ID`s from 1.2 against the `server` column.
Do not assume any of the four sit on their eventual target node today — the
K8s scheduler can (and, per `modules/hosts/legion/default.nix`'s comment on
the NetBird relay, has) placed workloads on nodes other than the target
placement.

### 1.4 On-disk layout of each volume, before any move

Confirm what's actually on each PVC today, matching it against the module
expectations detailed in Section 8 (data layout verification + reshape):

```sh
kubectl -n netbird exec deploy/netbird-server -- ls -la /var/lib/netbird
kubectl -n idp exec deploy/idp-pocket-id -- ls -la /app/data
kubectl -n actual-budget exec deploy/actual-budget -- ls -la /data
kubectl -n hath exec deploy/hath -- ls -la /hath
```

### 1.5 Current DNS records

Record the current A/AAAA target (the Hetzner Load Balancer's IP) for every
host in `modules/hosts/legion/_service-inventory.nix`'s `legion-node1`
`publicHostnames` list, plus `stun.netbird.jeiang.dev`, from the Hetzner DNS
Console (self-serve zones: `jeiang.dev`, `aidanpinard.co`, `pinard.co.tt`)
— `noelejoshua.com` and the `plyrex.dev` hosts are third-party zones, note
who owns them (per `docs/runbooks/edge-cutover.md`'s "Third-party DNS"
section) since they need separate coordination in Section 10.

### 1.6 Hetzner Load Balancer configuration

```sh
hcloud load-balancer list -o columns=id,name,ipv4,ipv6
hcloud load-balancer describe legion-lb1
```

Record its target ports (currently the Traefik NodePorts, e.g.
`30693/tcp`/`30297/tcp` per `modules/hosts/legion/default.nix`'s firewall
comment — reconfirm the live NodePort numbers, they are not stable across
Service recreation) for reference; you delete this LB in Section 10.

### 1.7 Current Hetzner Cloud Firewall rules

```sh
hcloud firewall list
hcloud firewall describe <firewall-name-from-above>
```

Record the current rule set — Section 10 updates it, so you need the
before-state to write an accurate rollback.

---

## 2. Pre-flight safety (point of no return starts here)

### 2.1 Hetzner server snapshots (root disk only)

Take one snapshot per node **before any other step below** — this is your
root-disk rollback anchor, taken while every node is still on its current,
working generation:

```sh
hcloud server create-image --type snapshot --description "pre-migration-$(date -u +%Y%m%dT%H%M%SZ)" legion-node1
hcloud server create-image --type snapshot --description "pre-migration-$(date -u +%Y%m%dT%H%M%SZ)" legion-node2
hcloud server create-image --type snapshot --description "pre-migration-$(date -u +%Y%m%dT%H%M%SZ)" legion-node3
hcloud server create-image --type snapshot --description "pre-migration-$(date -u +%Y%m%dT%H%M%SZ)" legion-node4
hcloud server create-image --type snapshot --description "pre-migration-$(date -u +%Y%m%dT%H%M%SZ)" legion-node5
```

Record each image ID:

```sh
hcloud image list -o columns=id,description,created,type | grep pre-migration
```

**These snapshots cover only the root disk.** They do not protect the four
retained-data Hetzner Volumes — that's the next step.

### 2.2 Data-volume rollback anchor (before detaching anything)

Copy each of the four volumes' live content out to Mega S4, independent of
the physical volume itself, so a bad reshape/chown/reattach in Section 8
has a restorable copy that doesn't depend on the volume surviving intact.
Use the same Mega S4 application key already provisioned for
`restic/s4-env` (Bitwarden) — configure it locally as `AWS_ACCESS_KEY_ID`/
`AWS_SECRET_ACCESS_KEY` for this step; these are raw archives, not Restic
snapshots, kept in a separate prefix from the `legion-restic-backups`
Restic repositories:

```sh
export AWS_ACCESS_KEY_ID=<from Bitwarden, same key as restic/s4-env>
export AWS_SECRET_ACCESS_KEY=<from Bitwarden, same key as restic/s4-env>
S4_ENDPOINT=https://s3.eu-central-1.s4.mega.io
S4_BUCKET=legion-restic-backups
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
```

NetBird server, Pocket ID, Actual Budget (small enough to round-trip
through the operator machine):

```sh
kubectl -n netbird run netbird-preflight-copy --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"netbird-preflight-copy","image":"alpine:3.20","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/var/lib/netbird"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"netbird-server"}}]}}'
kubectl -n netbird wait --for=condition=Ready pod/netbird-preflight-copy --timeout=60s
kubectl -n netbird exec netbird-preflight-copy -- tar czf /tmp/netbird-preflight.tar.gz -C /var/lib/netbird .
kubectl -n netbird cp netbird/netbird-preflight-copy:/tmp/netbird-preflight.tar.gz ./netbird-preflight-$STAMP.tar.gz
kubectl -n netbird delete pod netbird-preflight-copy
aws s3 cp ./netbird-preflight-$STAMP.tar.gz "s3://$S4_BUCKET/preflight-rollback/legion-node2/netbird-server/" --endpoint-url $S4_ENDPOINT

kubectl -n idp run pocket-id-preflight-copy --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"pocket-id-preflight-copy","image":"alpine:3.20","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/app/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"idp-pocket-id"}}]}}'
kubectl -n idp wait --for=condition=Ready pod/pocket-id-preflight-copy --timeout=60s
kubectl -n idp exec pocket-id-preflight-copy -- tar czf /tmp/pocket-id-preflight.tar.gz -C /app/data .
kubectl -n idp cp idp/pocket-id-preflight-copy:/tmp/pocket-id-preflight.tar.gz ./pocket-id-preflight-$STAMP.tar.gz
kubectl -n idp delete pod pocket-id-preflight-copy
aws s3 cp ./pocket-id-preflight-$STAMP.tar.gz "s3://$S4_BUCKET/preflight-rollback/legion-node2/pocket-id/" --endpoint-url $S4_ENDPOINT

kubectl -n actual-budget run actual-preflight-copy --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"actual-preflight-copy","image":"alpine:3.20","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"actual-budget"}}]}}'
kubectl -n actual-budget wait --for=condition=Ready pod/actual-preflight-copy --timeout=60s
kubectl -n actual-budget exec actual-preflight-copy -- tar czf /tmp/actual-preflight.tar.gz -C /data .
kubectl -n actual-budget cp actual-budget/actual-preflight-copy:/tmp/actual-preflight.tar.gz ./actual-preflight-$STAMP.tar.gz
kubectl -n actual-budget delete pod actual-preflight-copy
aws s3 cp ./actual-preflight-$STAMP.tar.gz "s3://$S4_BUCKET/preflight-rollback/legion-node4/actual-budget/" --endpoint-url $S4_ENDPOINT
```

H@H (40 GiB — stream straight to S4 instead of double-storing locally,
same reasoning `docs/runbooks/apps-migration.md` gives for preferring a
resume-safe transfer over the plain tar/scp pair on this one service):

```sh
kubectl -n hath run hath-preflight-copy --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"hath-preflight-copy","image":"alpine:3.20","command":["sleep","7200"],"volumeMounts":[{"name":"data","mountPath":"/hath"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"hath"}}]}}'
kubectl -n hath wait --for=condition=Ready pod/hath-preflight-copy --timeout=60s
kubectl -n hath exec hath-preflight-copy -- tar czf - -C /hath . \
  | aws s3 cp - "s3://$S4_BUCKET/preflight-rollback/legion-node4/hath/hath-preflight-$STAMP.tar.gz" --endpoint-url $S4_ENDPOINT
kubectl -n hath delete pod hath-preflight-copy
```

Confirm every upload landed before proceeding:

```sh
aws s3 ls "s3://$S4_BUCKET/preflight-rollback/" --recursive --endpoint-url $S4_ENDPOINT
```

**This is the gate.** Do not proceed to Section 3 until all four uploads
are confirmed present in S4 — past this point, the plan assumes a working
data-volume rollback anchor exists.

---

## 3. Quiesce K3s (fleet-wide)

Stop every workload so nothing holds the four volumes open before
detaching them, and so no writer races the reused volumes once they land on
their target node:

```sh
kubectl -n netbird scale deployment/netbird-server --replicas=0
kubectl -n netbird scale deployment/netbird-relay --replicas=0
kubectl -n netbird scale deployment/netbird-proxy --replicas=0
kubectl -n idp scale deployment/idp-pocket-id --replicas=0
kubectl -n actual-budget scale deployment/actual-budget --replicas=0
kubectl -n hath scale deployment/hath --replicas=0
kubectl get pods -A | grep -E 'netbird|idp|actual-budget|hath'   # confirm all terminated
```

Confirm the four volumes are no longer mounted anywhere in the cluster
(no pod holding them, which the scale-to-zero above already guarantees —
`hcloud volume detach` below will otherwise fail or, worse, force-detach
from a live writer):

```sh
hcloud volume list -o columns=id,name,server
```

The rest of K3s (every other daemonset/deployment, Kyverno, the NetBird
operator, Traefik, etc.) stays running for now — `kubectl` access is only
needed up through Section 4's detach step; the fleet's actual teardown
happens per-node in Section 7 when `services.k3s.enable = false` activates.

---

## 4. Detach the four data volumes

```sh
hcloud volume detach <netbird-server-volume-id>
hcloud volume detach <pocket-id-volume-id>
hcloud volume detach <actual-budget-volume-id>
hcloud volume detach <hath-volume-id>
```

(Volume IDs from Section 1.2's `kubectl get pv` output.) Confirm all four
show no `server` column:

```sh
hcloud volume list -o columns=id,name,server
```

---

## 5. Repo edits (commit before deploying)

### 5a. Disable K3s fleet-wide

`modules/nixos/k3s.nix` is the only file that sets `services.k3s.enable`,
and `self.nixosModules.k3s` is imported nowhere except
`modules/hosts/legion/default.nix`'s `legionConfiguration` (confirmed:
`grep -rn "nixosModules.k3s"` matches only that one import site) — so
flipping the module's own default is a fleet-wide, one-line change with no
other host affected:

`modules/nixos/k3s.nix`, inside `flake.nixosModules.k3s`'s
`services.k3s` block:

```diff
-        enable = true;
+        enable = false;
```

The per-node `nodeIP`/`role`/`extraFlags` set in
`modules/hosts/legion/default.nix`'s `mkLegionSystem` still evaluate (they
aren't removed), they just become inert — `services.k3s.enable = false`
means the module never starts the k3s unit, so those settings have nothing
to configure. This intentionally leaves the module's own
`networking.firewall` ports (6443/10250 tcp, 8472 udp) and
`persistence.directories` declarations in place — harmless when unused, and
removing them is Phase 7.2 (full K3s module removal), not this window.

### 5b. Point the inventory at the real (CSI) volume IDs

Overwrite the four stale `hcloudVolumeId` values (see the callout above)
with the volume IDs discovered in Section 1.2:

`modules/hosts/legion/_service-inventory.nix`, each service's `volume`
block:

```diff
-            hcloudVolumeId = "106426277";
+            hcloudVolumeId = "<netbird-server-volume-id-from-1.2>";
```

(`legion-node2`'s `netbird-server` entry)

```diff
-            hcloudVolumeId = "106426282";
+            hcloudVolumeId = "<pocket-id-volume-id-from-1.2>";
```

(`legion-node2`'s `pocket-id` entry)

```diff
-            hcloudVolumeId = "106426288";
+            hcloudVolumeId = "<actual-budget-volume-id-from-1.2>";
```

(`legion-node4`'s `actual-budget` entry)

```diff
-            hcloudVolumeId = "106426290";
+            hcloudVolumeId = "<hath-volume-id-from-1.2>";
```

(`legion-node4`'s `hath` entry)

The `sizeGiB` fields are documentation-only (per the file's own header
comment) and don't need to match the CSI volume's actual size — leave them.

### 5c. Validate and commit

```sh
nix flake check --impure --keep-going
git add modules/nixos/k3s.nix modules/hosts/legion/_service-inventory.nix
git commit -m "chore(legion): disable k3s fleet-wide, point inventory at reused CSI volumes"
```

Deploy in Section 7 targets this commit.

---

## 6. Attach volumes to target nodes

Target placement matches the inventory's already-declared placement
(`modules/hosts/legion/_service-inventory.nix`) — NetBird server + Pocket
ID go to `legion-node2`, Actual Budget + H@H go to `legion-node4`,
regardless of which node the K8s scheduler had them on before:

```sh
hcloud volume attach --server legion-node2 <netbird-server-volume-id>
hcloud volume attach --server legion-node2 <pocket-id-volume-id>
hcloud volume attach --server legion-node4 <actual-budget-volume-id>
hcloud volume attach --server legion-node4 <hath-volume-id>
```

Confirm each landed at a stable by-id path (this is what Section 5b's
`fileSystems` derivation in `modules/hosts/legion/default.nix` mounts by):

```sh
hcloud volume list -o columns=id,name,server,linux_device
ssh node2.jeiang.dev -- ls -la /dev/disk/by-id/ | grep -E "$(printf '%s\|%s' <netbird-server-volume-id> <pocket-id-volume-id>)"
ssh node4.jeiang.dev -- ls -la /dev/disk/by-id/ | grep -E "$(printf '%s\|%s' <actual-budget-volume-id> <hath-volume-id>)"
```

Nothing mounts yet — the `fileSystems` entry only takes effect once
Section 7 deploys the commit from Section 5c.

---

## 7. Rebuild the fleet (bootstrap deploy + reboot)

Every node's first deploy of this generation needs the bootstrap flags
noted in `modules/hosts/legion/default.nix`'s `deploy.nodes` comment: the
live nodes predate this config's `deploy` user, so the first activation
must run as the existing admin account over `doas`, with magic-rollback
disabled because that same first activation is what removes the doas-based
rollback waiter.

**Order: node2 → node3 → node4 → node1 → node5.** Management/identity
first (NetBird server + Pocket ID come up with their reused data, and
every other node's future OIDC/federation dependency on Pocket ID exists
from the start); monitoring next (fresh state, safe to bring up early,
gives you observability for the rest of the window); apps next (Attic/
Actual Budget/H@H, reused data, reachable over the private network from
node2 without needing DNS or the edge); edge last among the service nodes
(Caddy's routes should only start fronting real traffic once every backend
it proxies to already has data and is verified — bringing it up last means
the shortest possible window between "edge answers HTTP" and "backends are
actually ready", once DNS moves in Section 10); node5 last since it has no
service dependencies either way.

For each node:

```sh
just deploy legion-node2 --ssh-user aidanp --sudo='doas -u' --magic-rollback=false
ssh node2.jeiang.dev -- sudo reboot
# wait for it to come back
ssh node2.jeiang.dev -- uname -r   # confirm the new kernel
ssh node2.jeiang.dev -- sudo systemctl status netbird-server netbird-relay netbird-proxy pocket-id blocky
ssh node2.jeiang.dev -- findmnt /mnt/netbird /mnt/pocket-id
```

```sh
just deploy legion-node3 --ssh-user aidanp --sudo='doas -u' --magic-rollback=false
ssh node3.jeiang.dev -- sudo reboot
ssh node3.jeiang.dev -- uname -r
ssh node3.jeiang.dev -- sudo systemctl status victoriametrics victorialogs grafana vmalert-default alertmanager
```

```sh
just deploy legion-node4 --ssh-user aidanp --sudo='doas -u' --magic-rollback=false
ssh node4.jeiang.dev -- sudo reboot
ssh node4.jeiang.dev -- uname -r
ssh node4.jeiang.dev -- sudo systemctl status atticd actual hath
ssh node4.jeiang.dev -- findmnt /mnt/actual-budget /mnt/hath
```

```sh
just deploy legion-node1 --ssh-user aidanp --sudo='doas -u' --magic-rollback=false
ssh node1.jeiang.dev -- sudo reboot
ssh node1.jeiang.dev -- uname -r
ssh node1.jeiang.dev -- sudo systemctl status caddy crowdsec
```

```sh
just deploy legion-node5 --ssh-user aidanp --sudo='doas -u' --magic-rollback=false
ssh node5.jeiang.dev -- sudo reboot
ssh node5.jeiang.dev -- uname -r
```

Confirm the host firewall on each node reflects the new, K3s-free port set
(6443/10250/8472 stop mattering once `k3s.service` no longer runs, even
though the module's `networking.firewall` entries for them are still
technically declared — see 5a):

```sh
ssh node2.jeiang.dev -- sudo systemctl status k3s   # expect: not found / inactive, not "enable=false but still running"
```

At this point expect Actual Budget on node4 to be crash-looping — that's
the DynamicUser ownership mismatch handled in Section 8, not a failure of
this step.

---

## 8. Data layout verification + reshape

Per-service: confirm the reused volume's on-disk layout matches what the
module expects at its mountpoint, reshape/chown as needed, then (re)start.

### 8.1 NetBird server (`legion-node2`, `/mnt/netbird`) — no reshape

`modules/nixos/netbird-server/default.nix`'s `dataDir` is `/mnt/netbird`,
the exact same relative structure the chart wrote to `/var/lib/netbird`
(`server.dataDir`) — since Section 6 reattached the *same physical volume*
rather than copying its content elsewhere, the data is already in the
right place with no path translation needed:

```sh
ssh node2.jeiang.dev -- sudo chown -R netbird:netbird /mnt/netbird
ssh node2.jeiang.dev -- sudo systemctl restart netbird-server netbird-relay
ssh node2.jeiang.dev -- sudo journalctl -u netbird-server --since -2m
ssh node2.jeiang.dev -- ls /mnt/netbird   # note the actual store filename
ssh node2.jeiang.dev -- sudo sqlite3 /mnt/netbird/<store-file-from-ls> "PRAGMA integrity_check;"
```

### 8.2 Pocket ID (`legion-node2`, `/mnt/pocket-id`) — RESHAPE REQUIRED

`modules/nixos/pocket-id.nix` sets `WorkingDirectory=dataDir`
(`/mnt/pocket-id`) and leaves the app's relative defaults
(`DB_CONNECTION_STRING` `data/pocket-id.db`, `UPLOAD_PATH` `data/uploads`)
untouched, so it expects its files under `${dataDir}/data/`. The chart
mounted its PVC flat at `/app/data` with no nesting
(`docs/runbooks/pocket-id-migration.md` already documents this exact gap).
Since the reused volume presents that chart's flat layout directly at
`/mnt/pocket-id`, move everything down one level before first start:

```sh
ssh node2.jeiang.dev -- sudo systemctl stop pocket-id   # if the guarded unit auto-started against the flat layout
ssh node2.jeiang.dev -- sudo bash -c '
  set -euo pipefail
  cd /mnt/pocket-id
  mkdir -p data
  find . -mindepth 1 -maxdepth 1 ! -name data -exec mv -t data -- {} +
'
ssh node2.jeiang.dev -- sudo chown -R pocket-id:pocket-id /mnt/pocket-id
ssh node2.jeiang.dev -- sudo systemctl restart pocket-id
ssh node2.jeiang.dev -- sudo journalctl -u pocket-id --since -2m
ssh node2.jeiang.dev -- sudo sqlite3 /mnt/pocket-id/data/pocket-id.db "PRAGMA integrity_check;"
```

Confirm `pocket-id:pocket-id` is actually the unit's configured user before
relying on the name (`services.pocket-id.user`/`.group`, both default to
`pocket-id`, per `docs/runbooks/pocket-id-migration.md`):

```sh
ssh node2.jeiang.dev -- sudo systemctl show pocket-id -p User -p Group
```

### 8.3 Actual Budget (`legion-node4`, `/mnt/actual-budget`) — no reshape, DynamicUser chown required

`services.actual` derives `server-files`/`user-files` from `dataDir` by
default, matching the chart's initContainer-created layout exactly — no
path reshaping. But `services.actual` runs as `DynamicUser = true` (stable
name `actual`, no fixed UID), and DynamicUser only manages ownership of
systemd's own `StateDirectory` (`/var/lib/actual`), not an externally
mounted directory like `/mnt/actual-budget`. Because the volume already
held live chart data (owned by whatever UID the chart's pod used) *before*
`actual.service` ever ran here, its first start in Section 7 fails
permission checks against files it doesn't own — expect it crash-looping
(`Restart=on-failure`) at this point, not a working service. Systemd still
creates and chowns `/var/lib/actual` to the freshly assigned DynamicUser
UID on every attempt, even a failing one, so that UID is discoverable
without a clean start:

```sh
ssh node4.jeiang.dev -- sudo systemctl stop actual
ssh node4.jeiang.dev -- stat -c '%u:%g' /var/lib/actual   # e.g. "61234:61234"
ssh node4.jeiang.dev -- sudo chown -R <uid>:<gid> /mnt/actual-budget   # the pair stat just printed
ssh node4.jeiang.dev -- sudo systemctl start actual
ssh node4.jeiang.dev -- sudo journalctl -u actual --since -2m
ssh node4.jeiang.dev -- sudo sqlite3 /mnt/actual-budget/server-files/account.sqlite "PRAGMA integrity_check;"
```

If `/var/lib/actual` doesn't exist yet (the crash happened before systemd
created it), start the service once, let it crash, then retry the `stat`.

### 8.4 H@H (`legion-node4`, `/mnt/hath`) — no reshape

`modules/nixos/hath.nix` uses `cache`/`data`/`download`/`log` subdirs
directly under `dataDir` (`/mnt/hath`), identical to the chart's layout
under its `/hath` mount — a fixed system user (`isSystemUser`, not
`DynamicUser`), so chown by name works immediately, no UID discovery
dance:

```sh
ssh node4.jeiang.dev -- sudo chown -R hath:hath /mnt/hath
ssh node4.jeiang.dev -- sudo systemctl restart hath
ssh node4.jeiang.dev -- sudo journalctl -u hath --since -2m
```

---

## 9. NetBird re-enrollment / reconnection

Every Legion node runs the NetBird client (`modules/hosts/legion/default.nix`
`services.netbird.clients.default.login`), pointed at `netbird.jeiang.dev`.
Two different things happen here, on two different timelines:

- **Existing peers** (`artemis`, already enrolled before this migration):
  the retained server database (Section 8.1) means their peer registration
  already exists — no `netbird up` needed, they just need the server
  reachable again at the same management URL.
- **Legion nodes** (all five, via the fleet-wide `login.setupKeyFile`
  wiring): these enroll as **new** peers using the committed
  `netbird/setup-key` secret, since the K8s-side NetBird operator that
  used to provide the dropped Kubernetes routing peer is gone.

**Both are blocked until DNS actually moves in Section 10.** Every Legion
node resolves `netbird.jeiang.dev` via normal public DNS/upstream
resolvers, never via Blocky-over-NetBird (`modules/hosts/legion/default.nix`'s
bootstrap-circularity comment, enforced by `hardware.nix` keeping
`systemd-networkd`'s DHCP resolvers as-is) — this is intentional and
correct, but it means that until Section 10 repoints the DNS record,
`netbird.jeiang.dev` still resolves to the old Hetzner Load Balancer, whose
backend (the K8s NetBird server) was scaled to zero in Section 3. So:

- Right after Section 7, expect every node's NetBird client — **including
  `legion-node2` itself**, which also enrolls as a peer of the server it
  hosts, same as the live K8s server is reached today — to be unable to
  reach the management server. `systemd`'s `Restart=on-failure` /
  nixpkgs' netbird login service retries; this is expected, not a bug:
  ```sh
  ssh node2.jeiang.dev -- sudo netbird status   # expect "Management: Disconnected" or similar
  ```
- Correct sequence, matching the confirmed strategy: server up (node2,
  Section 7) → edge up (node1, Section 7) → DNS cut (Section 10) → clients
  finish enrolling. Don't chase reconnection failures here; come back to
  this once Section 10 lands, and verify from there.

---

## 10. DNS cutover + LB deletion + Cloud Firewall update

Only after Section 8's per-service verification passes and every node in
Section 7 is up on the new generation.

### 10.1 Repoint DNS

Every host currently served by Caddy on `legion-node1`
(`modules/hosts/legion/_service-inventory.nix` `legion-node1` `caddy`
`publicHostnames`) moves its A/AAAA record from the Hetzner Load Balancer
to `legion-node1`'s public IPs (`178.156.226.145` / `2a01:4ff:f0:6b8e::1`):

- `jeiang.dev` (apex), `aidanpinard.co`, `pinard.co.tt`, `auth.jeiang.dev`,
  `attic.jeiang.dev`, `budget.jeiang.dev`, `grafana.jeiang.dev`,
  `netbird.jeiang.dev`, `proxy.jeiang.dev`, `*.proxy.jeiang.dev`,
  `bill-split.jeiang.dev`, `github.jeiang.dev` — all self-serve in Hetzner
  DNS.
- `noelejoshua.com`, `pdf.plyrex.dev`, `jellyfin.plyrex.dev`,
  `seerr.plyrex.dev` — third-party zones (`docs/runbooks/edge-cutover.md`
  "Third-party DNS"), coordinate the record change directly with each
  zone owner; the same HTTP-01 cert-issuance gap that runbook documents
  applies (brief certificate warning between the DNS change landing and
  Caddy's first successful on-demand TLS challenge).

`stun.netbird.jeiang.dev` moves separately, directly to `legion-node2`'s
public IPs (`178.156.201.35` / `2a01:4ff:f0:a1ff::1`) — **not** through the
edge, Caddy/the LB can't proxy UDP STUN.

H@H has no DNS record — it's reached by public IP:port directly, already
`legion-node4`'s address; nothing to move there (see Section 10.4 instead).

Verify each host once its record has propagated:

```sh
curl -sSI https://jeiang.dev/
curl -sSI https://auth.jeiang.dev/
curl -sSI https://attic.jeiang.dev/
curl -sSI https://budget.jeiang.dev/
curl -sSI https://grafana.jeiang.dev/
curl -sSI https://netbird.jeiang.dev/
turnutils_stunclient stun.netbird.jeiang.dev
```

### 10.2 Confirm NetBird reconnection now completes

Now that `netbird.jeiang.dev` resolves to the live edge (which proxies to
node2's server), the clients blocked in Section 9 should finish enrolling/
reconnecting on their own within a few retry cycles:

```sh
ssh node1.jeiang.dev -- sudo netbird status
ssh node2.jeiang.dev -- sudo netbird status
ssh node3.jeiang.dev -- sudo netbird status
ssh node4.jeiang.dev -- sudo netbird status
ssh node5.jeiang.dev -- sudo netbird status
```

If any node still shows disconnected after a few minutes:
`sudo netbird down && sudo netbird up` to force a fresh handshake. On
`artemis`, confirm the pre-existing peer reconnects the same way (no
`netbird up` needed there — same management URL, only the backend serving
it changed).

### 10.3 Delete the Hetzner Load Balancer

Only after 10.1's verification passes for every host — the LB is the last
piece still capable of serving old (now-torn-down) backends, so leave it up
until you're confident DNS has actually cut over, not just that the record
was changed:

```sh
hcloud load-balancer delete legion-lb1
```

### 10.4 Update the Hetzner Cloud Firewall

Keep the Cloud Firewall as defense-in-depth (it stays enabled, this is not
a removal) — update its rules to allow the final public port set so it
doesn't silently drop traffic to the new topology. Cross-checked against
the inventory's `firewall = [... scope = "public" ...]` entries: `80`/`443`
tcp → `legion-node1` (caddy), `3478` udp → `legion-node2`
(netbird-relay), `8888` tcp → `legion-node4` (hath):

```sh
FIREWALL=<firewall-name-from-1.7>
hcloud firewall add-rule "$FIREWALL" --direction in --protocol tcp --port 80 \
  --source-ips 0.0.0.0/0 --source-ips ::/0 --description "caddy http (legion-node1)"
hcloud firewall add-rule "$FIREWALL" --direction in --protocol tcp --port 443 \
  --source-ips 0.0.0.0/0 --source-ips ::/0 --description "caddy https (legion-node1)"
hcloud firewall add-rule "$FIREWALL" --direction in --protocol udp --port 3478 \
  --source-ips 0.0.0.0/0 --source-ips ::/0 --description "netbird stun/relay (legion-node2)"
hcloud firewall add-rule "$FIREWALL" --direction in --protocol tcp --port 8888 \
  --source-ips 0.0.0.0/0 --source-ips ::/0 --description "hath (legion-node4)"
```

Confirm the firewall is (still) applied to every Legion server it needs to
cover, then diff the new rule set against the before-state recorded in
Section 1.7 and remove anything that only existed for the old Traefik
NodePort/LB topology:

```sh
hcloud firewall describe "$FIREWALL"
```

---

## 11. Full verification

Per-service (reusing each retained service's own runbook checks, adapted
to `curl` without `--resolve` now that DNS is live):

- **NetBird**: dashboard loads at `https://netbird.jeiang.dev`, shows the
  pre-existing account/peer list (not empty). Pocket ID-federated login
  from the dashboard succeeds. `turnutils_stunclient stun.netbird.jeiang.dev`
  resolves. A Reverse Proxy service under `*.proxy.jeiang.dev` serves with
  a valid wildcard cert (`curl -vI https://<service>.proxy.jeiang.dev/`).
  `ssh node1.jeiang.dev -- sudo cscli bouncers list` shows `netbird-proxy`
  registered.
- **Pocket ID**: OIDC login against `auth.jeiang.dev` succeeds for Grafana
  and Attic's existing client registrations. SMTP: check the admin UI
  (Settings → Email) for populated settings after the retained-DB start in
  8.2; if empty (the v2.9.0 → v2.10.0 SMTP-to-DB-rows migration didn't
  carry over), re-enter the iCloud SMTP settings per
  `docs/runbooks/pocket-id-migration.md`'s table and send a real test
  email to confirm delivery.
- **Attic**: with an existing `attic` client already logged in against the
  live cache, push and pull a throwaway path:
  ```sh
  echo "post-migration smoke test $(date -u +%s)" > /tmp/attic-smoke-test
  nix-store --add /tmp/attic-smoke-test
  attic push default /nix/store/<the-path-just-added>
  nix-store --realize /nix/store/<the-path-just-added> --option substituters "https://attic.jeiang.dev/default" 2>&1 | grep -i "copying\|already"
  ```
- **Actual Budget**: log in at `https://budget.jeiang.dev`, confirm
  existing budget/transaction data is intact (not a fresh empty instance).
- **H@H**: `ssh node4.jeiang.dev -- sudo journalctl -u hath -f`, watch for
  incoming connections; cross-check the H@H client dashboard shows the
  client "Online" at the new IP.
- **Monitoring**: Grafana loads at `https://grafana.jeiang.dev`, Pocket ID
  OAuth login works, dashboards render, `vmalert`/Alertmanager routes are
  live (fresh state is expected and accepted — no data continuity check
  needed here).
- **Edge static content**: repeat `docs/runbooks/edge-cutover.md`'s
  pre-cutover `curl --resolve` battery, without `--resolve` now:
  `jeiang.dev`, `aidanpinard.co`, `pinard.co.tt`, `noelejoshua.com`,
  `bill-split.jeiang.dev` (200), `github.jeiang.dev` (301), stray
  `*.jeiang.dev` subdomain (404).
- **CrowdSec fail-open**: `ssh node1.jeiang.dev -- sudo systemctl stop
  crowdsec`, confirm `curl -sSI https://jeiang.dev/` still succeeds, then
  `sudo systemctl start crowdsec`.

Fleet health pass:

```sh
for n in 1 2 3 4 5; do
  ssh node$n.jeiang.dev -- "uname -r; systemctl --failed; systemctl is-active k3s 2>&1"
done
```

Expect no `k3s` unit at all (module still declares the token secret/
firewall ports, but with `enable = false` no `k3s.service` unit is
generated) and no unexpected `systemctl --failed` entries. Confirm each
retained service's Restic backup timer is scheduled and will run on its
normal cadence going forward:

```sh
ssh node2.jeiang.dev -- systemctl list-timers 'restic-backups-*'
ssh node4.jeiang.dev -- systemctl list-timers 'restic-backups-*'
```

---

## 12. `legion-node5` note (deferred decommission)

`legion-node5` is rebuilt in Section 7 into the same serviceless,
K3s-disabled generation as every other node, purely for fleet consistency
(same kernel, same config baseline) — its
`modules/hosts/legion/_service-inventory.nix` entry is already
`services = []` and it owns no Volume, so nothing in this window requires
touching it further. Its actual decommission — deleting the Hetzner
server, removing it from `legionNodes`/`nixosConfigurations`/`deploy.nodes`,
updating `DESIGN.md`'s system-roles table — is Phase 7.3
(`docs/MIGRATION.md`), a separate, later runbook
(`docs/runbooks/decommission.md`, not yet written), gated on every service
being `cut-over` per the Phase 7 ordering rule. **This is flagged as an
assumption above (see "Assumption flagged for operator confirmation") —
confirm node5 should be rebuilt-but-kept this window before running its
Section 7 step**, rather than left untouched until Phase 7.3.

---

## 13. Rollback procedure

**Point of no return**: once any host-native service (Section 7 onward)
writes to a reused volume — NetBird accepting a new peer/session, Pocket
ID issuing a token, Actual Budget recording a transaction, H@H completing
a download — rolling back to the Kubernetes deployment means losing
everything written since Section 2.2's data-volume copy, because the K8s
side resumes from that copy, not from the live state of the reused volume.
Roll back only if you catch a problem before real usage; past that,
fix forward instead (same convention as every existing per-service
runbook's "State divergence warning").

### 13.1 Root disk: restore server snapshots

```sh
hcloud server rebuild --image <legion-node1-snapshot-image-id> legion-node1
hcloud server rebuild --image <legion-node2-snapshot-image-id> legion-node2
hcloud server rebuild --image <legion-node3-snapshot-image-id> legion-node3
hcloud server rebuild --image <legion-node4-snapshot-image-id> legion-node4
hcloud server rebuild --image <legion-node5-snapshot-image-id> legion-node5
```

This destroys and reformats each node's root disk from the Section 2.1
snapshot — the last thing before this runbook started. It restores each
node's original `/etc/ssh/ssh_host_ed25519_key`, so sops-nix decryption
keeps working exactly as it did pre-migration; it does not need any key
re-provisioning.

### 13.2 Restore data-volume copies (if any reused volume was modified before you caught the problem)

Only needed if Section 8's chown/reshape or a live write already touched a
volume in a way you don't trust. Restore from the Section 2.2 S4 archives
to a scratch location, verify, then copy back over the volume (same
pattern as `docs/runbooks/restore.md`'s "Restore to a scratch directory" →
"Verify content" → "Restore to the live path"):

```sh
aws s3 cp "s3://$S4_BUCKET/preflight-rollback/legion-node2/netbird-server/netbird-preflight-$STAMP.tar.gz" . --endpoint-url $S4_ENDPOINT
# extract to a scratch dir, verify, then re-extract over the live mount with the service stopped
```

Repeat per service, substituting the matching S4 prefix from Section 2.2.

### 13.3 Revert the repo commits

```sh
git revert <commit-from-5c>
```

Or, if flake.lock/kernel also need reverting for the rebuilt-from-snapshot
nodes to match: check out the commit that was live before this migration
started and re-deploy from it. Confirm which is correct for your situation
before running either — a snapshot-restored node (13.1) is already back on
the old generation; only revert the repo state if you're rolling back
*without* restoring snapshots (e.g., only Section 5's commit needs undoing
because you caught the problem before Section 7 rebuilt anything).

### 13.4 Reattach volumes to the old K3s nodes

```sh
hcloud volume detach <netbird-server-volume-id>
hcloud volume detach <pocket-id-volume-id>
hcloud volume detach <actual-budget-volume-id>
hcloud volume detach <hath-volume-id>
hcloud volume attach --server <original-node-from-1.3> <netbird-server-volume-id>
hcloud volume attach --server <original-node-from-1.3> <pocket-id-volume-id>
hcloud volume attach --server <original-node-from-1.3> <actual-budget-volume-id>
hcloud volume attach --server <original-node-from-1.3> <hath-volume-id>
```

Scale the K8s deployments back up and let the CSI driver remount them:

```sh
kubectl -n netbird scale deployment/netbird-server --replicas=1
kubectl -n netbird scale deployment/netbird-relay --replicas=1
kubectl -n netbird scale deployment/netbird-proxy --replicas=1
kubectl -n idp scale deployment/idp-pocket-id --replicas=1
kubectl -n actual-budget scale deployment/actual-budget --replicas=1
kubectl -n hath scale deployment/hath --replicas=1
```

### 13.5 Re-point DNS to the Load Balancer

Only if 10.3 already deleted it — if the LB is gone, re-provision one
against Traefik's Service before pointing DNS back at it; if you rolled
back before Section 10, the LB was never touched and DNS never moved, so
there's nothing to revert here. Otherwise, point every A/AAAA record moved
in Section 10.1 back at the Hetzner Load Balancer's IP; the low-TTL
convention from `docs/runbooks/edge-cutover.md` means this propagates
quickly.

---

## 14. Post-migration cleanup

Once Section 11's verification is stable and the operator is confident in
the cutover (no fixed window specified here — this is a full downtime
migration, not a staged one with its own two-week rollback window like the
individual service runbooks; use judgment):

- **Delete the four empty pre-created volumes.** These are the
  superseded-plan disks called out in Section 0.5 — `106426277`,
  `106426282`, `106426288`, `106426290` — **not** the reused CSI volumes
  now recorded in `modules/hosts/legion/_service-inventory.nix`'s
  `hcloudVolumeId` fields (those came from Section 1.2 and hold the live,
  now-in-service data; never delete those). The four empty ones were kept
  attached-or-idle up to this point deliberately, as a mid-flight fallback
  — only delete them once Section 11's verification is stable. Detach
  first if still attached to a node:
  ```sh
  hcloud volume list -o columns=id,name,server
  ```
  If any of the four show a `server` value, detach before deleting:
  ```sh
  hcloud volume detach 106426277
  hcloud volume detach 106426282
  hcloud volume detach 106426288
  hcloud volume detach 106426290
  ```
  Then delete all four so they stop lingering and billing:
  ```sh
  hcloud volume delete 106426277
  hcloud volume delete 106426282
  hcloud volume delete 106426288
  hcloud volume delete 106426290
  ```
- Optionally wipe now-unused K3s state left on each root disk:
  `/var/lib/rancher/k3s`, `/var/lib/kubelet`, `/etc/rancher/k3s` (per
  `modules/nixos/k3s.nix`'s `persistence.directories` list — these paths
  are declared but were never actually persisted, since no Legion host
  imports `self.nixosModules.impermanence`, so this is a plain `rm -rf`
  on each node's root disk, not an impermanence-aware operation).
- The remaining Phase 7 work in `docs/MIGRATION.md` is explicitly **not**
  part of this window: **7.2** full K3s module removal (drop
  `self.nixosModules.k3s` from `legionConfiguration`, the k3s firewall
  ports/sysctls/kernel modules, the `k3s/token` sops secret, the OIDC
  apiserver wiring that's now moot) and **7.3** `legion-node5` decommission
  (Section 12 above). Both are separate, later sessions.
