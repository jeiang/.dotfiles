# Runbook: Applications Migration

Operator runbook for [`docs/MIGRATION.md`](../MIGRATION.md) piece 5.6: moving
Attic, Actual Budget, Stirling PDF, and H@H from the Experimental Cluster to
`legion-node4` (`modules/nixos/attic.nix`, `modules/nixos/actual-budget.nix`,
`modules/nixos/stirling-pdf.nix`, `modules/nixos/hath.nix`, pieces 5.1-5.4).
Also covers piece 5.7 (NetBird DNS repoint for Blocky) as its own section
below, per `docs/MIGRATION.md`'s "may fold into 5.6". Review
[`AGENTS.md`](../../AGENTS.md) before running any command here, and
[`docs/runbooks/restore.md`](restore.md) for the Restic mechanics that Actual
Budget's and Stirling PDF's Safety Rule 1 steps depend on.

This runbook assumes [`docs/runbooks/edge-cutover.md`](edge-cutover.md) has
already landed the Edge Node (the `attic.jeiang.dev`, `budget.jeiang.dev`, and
`pdf.plyrex.dev` Caddy routes exist and are verified up to the point where
they `502` because pieces 5.1-5.3 aren't deployed yet — expected, not a
regression). H@H has no edge route (Caddy doesn't proxy its binary protocol);
it is reached directly at `legion-node4`'s public IP. This runbook does not
cut DNS for any other Edge Node host, and does not touch the Hetzner Load
Balancer, Traefik, or K3s (Cutover Safety Rule 3, Phase 7 only).

Each service section is independent — deploy, verify, and cut one over at a
time rather than all four together, so a problem with one doesn't block or
mask a problem with another.

## Prerequisites

### sops secrets (Attic only)

Actual Budget, Stirling PDF, and H@H need no sops secrets of their own
(`modules/nixos/actual-budget.nix`, `modules/nixos/stirling-pdf.nix`,
`modules/nixos/hath.nix` declare none). Create these four with
`just sops-edit` before deploying `legion-node4` with `attic` enabled
(`modules/nixos/attic.nix` `sops.secrets`/`templates."attic.env"`):

| Secret | Value |
| --- | --- |
| `attic/database-url` | The live external managed PostgreSQL connection string. Per `docs/MIGRATION.md` Confirmed Decisions, this is **not** one of the Bitwarden Secrets Manager entries `k8s-manifests/attic/README.md` documents (that README only lists the S3 key pair and the RS256 key) — obtain it from wherever the operator currently records it. |
| `attic/s3-access-key-id` | Copy from Bitwarden Secrets Manager (`k8s-manifests/attic/README.md` "Create credentials", Bitwarden ID `4665f391-c3ec-45ef-8aab-b48500717b56` per `k8s-manifests/attic/values.yaml` `bitwardenSecrets.secretIds.s3AccessKeyId`). Must keep its exact live value — this is the existing Mega S4 cache, not a fresh one. |
| `attic/s3-secret-access-key` | Copy from Bitwarden (ID `e9ff9778-0c28-42fd-a318-b48500719679`), same reasoning. |
| `attic/token-rs256-secret-base64` | Copy from Bitwarden (ID `296c5301-9dda-4ab7-a472-b4850071559e`). **Must** keep its exact live value: it's the OIDC token-signing key. A different value invalidates every previously issued client token and breaks the existing GitHub Actions/Pocket ID OIDC trust configured in `modules/nixos/attic.nix`. |

`restic/password` and `restic/s4-env` are prerequisites of piece 2.1, not
this runbook — see `docs/runbooks/restore.md` if they don't already exist.
They're relevant to Actual Budget, Stirling PDF, and H@H below; Attic alone
does not declare a `backupSet` (it has no local state).

### Hetzner Volumes

Attach, format, and mount these on `legion-node4` before the first deploy
with the corresponding service enabled (inventory entries,
`modules/hosts/legion/_service-inventory.nix`). Attic needs none (stateless):

| Service | Mountpoint | Inventory Volume name |
| --- | --- | --- |
| Actual Budget | `/mnt/actual-budget` | `legion-node4-actual-budget` |
| Stirling PDF | `/var/lib/stirling-pdf` | `legion-node4-stirling-pdf` (mounts directly here, not under `/mnt` — `modules/nixos/stirling-pdf.nix` comment: the pinned nixpkgs module hardcodes `StateDirectory`/`WorkingDirectory`) |
| H@H | `/mnt/hath` | `legion-node4-hath` |

Neither this flake nor the individual modules declare a `fileSystems` entry
for any of these (Hetzner Volume mounting is an external prerequisite per
`DESIGN.md`) — add a durable mount (e.g. an `/etc/fstab` line by device
UUID/ID) for each so it survives a reboot. Confirm each is mounted before
proceeding (`ssh node4.jeiang.dev -- findmnt /mnt/actual-budget
/var/lib/stirling-pdf /mnt/hath`); otherwise the service's own
`systemd.tmpfiles.rules`/`StateDirectory` creates an empty directory on the
root disk instead, and the copied-in data below silently lands on disposable
storage.

### Deploy

```sh
just deploy legion-node4
```

This brings up all four services at once: Attic connects to the live
external Postgres immediately (nothing to quiesce or copy for it — see its
section below), while Actual Budget, Stirling PDF, and H@H start against
**empty** Volumes — intentional, so you can confirm each unit starts cleanly
before trusting it with copied data. Confirm before proceeding:

```sh
ssh node4.jeiang.dev -- sudo systemctl status atticd actual stirling-pdf hath
ssh node4.jeiang.dev -- sudo journalctl -u atticd -u actual -u stirling-pdf -u hath --since -5m
```

## Attic (stateless)

No data copy — Attic carries no local state (external managed PostgreSQL +
Mega S4, `docs/MIGRATION.md` Confirmed Decisions). This section is
deploy-and-verify only.

### Verify via the edge (pre-DNS)

`attic` (the CLI, `perSystem.packages.attic-client`) doesn't support a
`curl`-style `--resolve` override, so use a temporary `/etc/hosts` entry
pointing `attic.jeiang.dev` at the Edge Node instead — the edge's
`attic.jeiang.dev` route (`modules/nixos/edge/default.nix`) already forwards
to `legion-node4:8080`, and the TLS cert served there is the existing
`*.jeiang.dev` wildcard, so the override is transparent to the client:

```sh
echo "178.156.226.145 attic.jeiang.dev" | sudo tee -a /etc/hosts   # legion-node1
```

Replace `178.156.226.145` if `legion-node1`'s address has changed
(`modules/hosts/legion/default.nix`). With an existing `attic` client already
logged in against the live cache (same signing key, same `default` cache —
nothing new to configure), push and pull a throwaway path to confirm the
host-native backend serves the existing cache correctly:

```sh
echo "attic migration smoke test $(date -u +%s)" > /tmp/attic-smoke-test
nix-store --add /tmp/attic-smoke-test   # or: nix build any small derivation
attic push default /nix/store/<the-path-just-added>
attic use default   # if not already configured as a substituter
nix-store --realize /nix/store/<the-path-just-added> --option substituters "https://attic.jeiang.dev/default" 2>&1 | grep -i "copying\|already"
```

Confirm the push succeeds against the retained cache (no "unauthorized"
errors — proves the RS256 key value matches) and the pull round-trips.
Remove the `/etc/hosts` line once done:

```sh
sudo sed -i '' '/attic\.jeiang\.dev/d' /etc/hosts   # macOS; drop the '' arg on Linux
```

### CrowdSec exception

Confirm the edge's Attic route still carries the traffic exception noted in
`modules/nixos/edge/default.nix` (`crowdsec` handler present, `appsec`
deliberately absent on `attic.jeiang.dev`) — nothing to change here, just
confirm the route wasn't altered.

### DNS cutover

`attic.jeiang.dev` is in the same `docs/runbooks/edge-cutover.md` staged
group as `auth.jeiang.dev`/`budget.jeiang.dev`/`grafana.jeiang.dev` — move it
only once the verification above passes, following that runbook's ordering
and per-host verification (repeat the same push/pull check without
`--resolve`/`/etc/hosts`, from outside the Hetzner private network).

Rollback: point the `attic.jeiang.dev` A/AAAA record back at the Hetzner
Load Balancer. Both backends read the same external Postgres and Mega S4
bucket, so there's no state divergence risk on rollback (unlike the
retained-data services below) — either backend serves the same cache.

### Release removal (no PVC concerns)

Safety Rule 1/2 don't apply the usual way here (no local state to back up or
retain a Volume for), but the release still needs the same gating on a
settled DNS cutover:

```sh
kubectl -n attic scale deployment/attic --replicas=0   # quiesce first
# ... confirm the host-native attic.jeiang.dev has served real traffic for a
# reasonable window post-cutover ...
helm -n attic uninstall attic
```

## Actual Budget (retain data)

### Quiesce the Kubernetes deployment

```sh
kubectl -n actual-budget scale deployment/actual-budget --replicas=0
kubectl -n actual-budget get pods   # confirm it has terminated
```

### Copy PVC content to the Volume

The chart mounts its PVC at `/data` with `server-files/`/`user-files/`
subdirectories created by an initContainer
(`k8s-manifests/actual-budget/values.yaml` `persistence`/`initContainers`).
`services.actual` derives the same `server-files`/`user-files` layout from
`dataDir` by default (`modules/nixos/actual-budget.nix`) — a straight copy,
no reshaping:

```sh
kubectl -n actual-budget run actual-pvc-copy --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"actual-pvc-copy","image":"alpine:3.20","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"actual-budget"}}]}}'
kubectl -n actual-budget wait --for=condition=Ready pod/actual-pvc-copy --timeout=60s
kubectl -n actual-budget exec actual-pvc-copy -- tar czf /tmp/actual-data.tar.gz -C /data .
kubectl -n actual-budget cp actual-budget/actual-pvc-copy:/tmp/actual-data.tar.gz ./actual-data.tar.gz
kubectl -n actual-budget delete pod actual-pvc-copy
```

Confirm the actual PVC name first if unsure (`kubectl -n actual-budget get
pvc`; chart `fullnameOverride: actual-budget`, so the default claim name is
`actual-budget` unless overridden).

### UID note: DynamicUser, not a fixed UID

The chart runs its pod as UID/GID `1000` (`persistence`/`podSecurityContext`
`runAsUser`/`fsGroup: 1000`). `services.actual` does **not** run as a fixed
UID — it uses `DynamicUser = true` with a stable name (`User = "actual"`,
nixpkgs `services.actual`), so there's no `actual` entry in `/etc/passwd` to
`chown` against by name while the service is stopped (`getent passwd actual`
only resolves while the unit is active). Because the earlier "empty deploy"
step already started `actual` once, systemd has already chowned its
`StateDirectory` (`/var/lib/actual`) to the dynamically assigned UID/GID, and
that ownership is stable across restarts as long as `/var/lib/actual`
persists — read it back to get the numeric ID to `chown` the copied data to:

```sh
ssh node4.jeiang.dev -- sudo systemctl stop actual
ssh node4.jeiang.dev -- stat -c '%u:%g' /var/lib/actual   # e.g. "61234:61234"
scp ./actual-data.tar.gz deploy@node4.jeiang.dev:/tmp/
ssh node4.jeiang.dev -- sudo tar xzf /tmp/actual-data.tar.gz -C /mnt/actual-budget
ssh node4.jeiang.dev -- sudo chown -R <uid>:<gid> /mnt/actual-budget   # the pair stat printed above
ssh node4.jeiang.dev -- sudo rm /tmp/actual-data.tar.gz
rm ./actual-data.tar.gz
```

### Start the copied state and back it up

```sh
ssh node4.jeiang.dev -- sudo systemctl start actual
ssh node4.jeiang.dev -- sudo journalctl -u actual --since -2m
```

Confirm it started against the copied database (budgets visible once you log
in via DNS cutover below, or inspect the SQLite file directly:
`sudo sqlite3 /mnt/actual-budget/server-files/account.sqlite "PRAGMA
integrity_check;"` — filename per `modules/hosts/legion/_service-inventory.nix`'s
comment on the `actual-budget` `backupPauseUnits` entry).

Now exercise Safety Rule 1 for real, against the copied-in state:

```sh
ssh node4.jeiang.dev -- sudo systemctl start restic-backups-actual-budget.service
ssh node4.jeiang.dev -- sudo systemctl status restic-backups-actual-budget.service
```

Then follow `docs/runbooks/restore.md` "List snapshots" → "Restore to a
scratch directory" → "Verify content" against
`s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/legion-node4/actual-budget`.
Record the verification (date, snapshot ID) here once done — this clears
Safety Rule 1 for Actual Budget's eventual Kubernetes release removal below.

Safety Rule 2: **do not** delete the `actual-budget` PVC or flip its reclaim
policy yet — that's part of "Post-verify" below.

### DNS cutover and verification

```sh
curl -sSI --resolve budget.jeiang.dev:443:178.156.226.145 https://budget.jeiang.dev/
```

Log in and confirm existing budget data is intact. Then move
`budget.jeiang.dev` per `docs/runbooks/edge-cutover.md`'s staged group and
per-host verification.

### Rollback

```sh
kubectl -n actual-budget scale deployment/actual-budget --replicas=1
```

Then revert `budget.jeiang.dev` DNS. **State divergence warning**: any
transaction entered after cutover exists only in `/mnt/actual-budget`, not
the PVC — only roll back if you catch a problem quickly; past that window,
fix forward instead (same convention as `docs/runbooks/pocket-id-migration.md`).

### Post-verify (gated on Safety Rules)

Only after the Restic restore is verified and the two-week rollback window
has elapsed:

```sh
kubectl -n actual-budget patch pv <actual-budget-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
helm -n actual-budget uninstall actual-budget
```

## Stirling PDF (retain data)

### Quiesce the Kubernetes deployment

Stirling PDF is a cluster-only workload (`docs/IMPROVEMENTS.md` §4) absent
from `k8s-manifests` — confirm its live namespace/deployment/PVC names
directly rather than assuming a chart-documented default:

```sh
kubectl get deploy,pvc -A | grep -i stirling
kubectl -n <namespace> scale deployment/<deployment> --replicas=0
kubectl -n <namespace> get pods   # confirm it has terminated
```

### Copy PVC content, matching the module's ownership

`modules/nixos/stirling-pdf.nix` mounts the Volume directly at
`/var/lib/stirling-pdf` (the pinned nixpkgs `services.stirling-pdf` module
hardcodes both `WorkingDirectory` and `StateDirectory` there with no
override option). Same `DynamicUser`/stable-name situation as Actual Budget
above (nixpkgs module: `User = "stirling-pdf"`, `DynamicUser = true`) —
start the service once against the empty, freshly mounted Volume first (this
also lets it generate its own default login DB, which the copy below then
overwrites with the retained one) to establish ownership, then copy in:

```sh
ssh node4.jeiang.dev -- sudo systemctl start stirling-pdf   # if not already running from the earlier empty-deploy check
ssh node4.jeiang.dev -- stat -c '%u:%g' /var/lib/stirling-pdf
ssh node4.jeiang.dev -- sudo systemctl stop stirling-pdf
```

```sh
kubectl -n <namespace> run stirling-pvc-copy --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"stirling-pvc-copy","image":"alpine:3.20","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"<pvc-name>"}}]}}'
kubectl -n <namespace> wait --for=condition=Ready pod/stirling-pvc-copy --timeout=60s
kubectl -n <namespace> exec stirling-pvc-copy -- tar czf /tmp/stirling-data.tar.gz -C /data .
kubectl -n <namespace> cp <namespace>/stirling-pvc-copy:/tmp/stirling-data.tar.gz ./stirling-data.tar.gz
kubectl -n <namespace> delete pod stirling-pvc-copy
```

```sh
scp ./stirling-data.tar.gz deploy@node4.jeiang.dev:/tmp/
ssh node4.jeiang.dev -- sudo tar xzf /tmp/stirling-data.tar.gz -C /var/lib/stirling-pdf
ssh node4.jeiang.dev -- sudo chown -R <uid>:<gid> /var/lib/stirling-pdf   # from the stat above
ssh node4.jeiang.dev -- sudo rm /tmp/stirling-data.tar.gz
rm ./stirling-data.tar.gz
```

### Start the copied state and back it up

```sh
ssh node4.jeiang.dev -- sudo systemctl start stirling-pdf
ssh node4.jeiang.dev -- sudo journalctl -u stirling-pdf --since -2m
ssh node4.jeiang.dev -- sudo systemctl start restic-backups-stirling-pdf.service
ssh node4.jeiang.dev -- sudo systemctl status restic-backups-stirling-pdf.service
```

Follow `docs/runbooks/restore.md` against
`s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/legion-node4/stirling-pdf`,
record the verification, then hold PVC deletion per Safety Rule 2.

### Verification

```sh
curl -sSI --resolve pdf.plyrex.dev:443:178.156.191.180 https://pdf.plyrex.dev/
```

Log in with an existing account (`SECURITY_ENABLELOGIN = true`,
`modules/nixos/stirling-pdf.nix` — the retained DB already has real users)
and run one PDF operation (e.g. merge or convert a small test file) to
confirm the app is fully functional, not just serving the login page.

### DNS cutover: third-party zone, HTTP-01 gap

`pdf.plyrex.dev` is **not** in Hetzner DNS (`plyrex.dev` is a third-party
zone, `docs/MIGRATION.md` TLS strategy). Coordinate the record change
directly with the zone owner — this flake has no automation for it. The same
HTTP-01 cert-issuance gap `docs/runbooks/edge-cutover.md` documents for
`noelejoshua.com`/the other `plyrex.dev` hosts applies here: between the DNS
record moving to `legion-node1` and the first successful ACME challenge,
clients see a certificate warning. Warn the zone owner before flipping the
record. `docs/runbooks/edge-cutover.md` explicitly calls out that
`pdf.plyrex.dev`'s cutover happens here, not in that runbook.

### Rollback

```sh
kubectl -n <namespace> scale deployment/<deployment> --replicas=1
```

Then revert `pdf.plyrex.dev` with the third-party zone owner. **State
divergence warning**: same as Actual Budget — a login/document created after
cutover exists only in `/var/lib/stirling-pdf`, not the PVC.

### Post-verify (gated on Safety Rules)

```sh
kubectl -n <namespace> patch pv <stirling-pdf-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
helm -n <namespace> uninstall <release>   # or kubectl delete -f, if it isn't Helm-managed
```

## H@H (retain client login + cache)

### Quiesce the Kubernetes deployment

```sh
kubectl -n hath scale deployment/hath --replicas=0
kubectl -n hath get pods   # confirm it has terminated
```

### Copy PVC content to the Volume

The chart's PVC mounts at `/hath` with `cache/`, `data/`, `download/`,
`log/` subdirectories directly underneath (`k8s-manifests/hath/values.yaml`
`persistence.mountPath: /hath`, `hath.cacheDir`/`dataDir`/`downloadDir`/
`logDir`) — `modules/nixos/hath.nix` uses the identical layout under
`/mnt/hath` (its `dataDir` variable), so this is a straight copy with no
reshaping:

```sh
kubectl -n hath run hath-pvc-copy --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"hath-pvc-copy","image":"alpine:3.20","command":["sleep","7200"],"volumeMounts":[{"name":"data","mountPath":"/hath"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"hath"}}]}}'
kubectl -n hath wait --for=condition=Ready pod/hath-pvc-copy --timeout=60s
kubectl -n hath exec hath-pvc-copy -- tar czf /tmp/hath-data.tar.gz -C /hath .
kubectl -n hath cp hath/hath-pvc-copy:/tmp/hath-data.tar.gz ./hath-data.tar.gz
kubectl -n hath delete pod hath-pvc-copy
```

Confirm the actual PVC name first if unsure (`kubectl -n hath get pvc`).
30 GiB of cache makes this copy slow — resume-safe transfer is worth it over
a single `tar`/`scp` if the link is unreliable; e.g. `rsync` directly from a
copy pod instead of the tar/cp/extract round-trip above, or split the
`cache/` subdirectory out and copy it separately/last so a `data/` (login)
copy failure doesn't also cost the cache transfer time:

```sh
# Alternative to the tar/scp pair above, run from the copy pod's perspective
# via `kubectl exec -i` piping straight to node4, or port-forward + rsync;
# either way, prioritize copying `data/` (login, small, critical) before
# `cache/` (large, slow). Both are retained AND in the Backup Set (operator
# decision, docs/MIGRATION.md H@H inventory entry): a cold cache degrades
# the client's hourly quota until it refills, so the copy is worth the time
# rather than letting the client re-download 30 GiB from the H@H network.
```

### Extract with the module's ownership

`modules/nixos/hath.nix` declares a real, fixed `hath` user (`isSystemUser`,
not `DynamicUser`) — unlike Actual Budget/Stirling PDF above, `chown` by
name works immediately, no `stat`-derived numeric ID needed. The chart's UID
`1000` is not meaningful here (always chown to the module's user by name,
not by preserving the source UID, same convention as every other runbook in
this repo):

```sh
scp ./hath-data.tar.gz deploy@node4.jeiang.dev:/tmp/
ssh node4.jeiang.dev -- sudo tar xzf /tmp/hath-data.tar.gz -C /mnt/hath
ssh node4.jeiang.dev -- sudo chown -R hath:hath /mnt/hath
ssh node4.jeiang.dev -- sudo rm /tmp/hath-data.tar.gz
rm ./hath-data.tar.gz
```

### Start the copied state and back it up

```sh
ssh node4.jeiang.dev -- sudo systemctl start hath
ssh node4.jeiang.dev -- sudo journalctl -u hath --since -2m
ssh node4.jeiang.dev -- sudo systemctl start restic-backups-hath.service
ssh node4.jeiang.dev -- sudo systemctl status restic-backups-hath.service
```

`modules/hosts/legion/_service-inventory.nix`'s `hath` entry backs up both
`/mnt/hath/data` (login data) and `/mnt/hath/cache` (the 30 GiB download
cache) — `download/` and `log/` stay out. Expect this first Restic run to be
large and slow (comparable to the PVC copy above); subsequent daily runs are
incremental. Follow `docs/runbooks/restore.md` against
`s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/legion-node4/hath`,
record the verification.

### Port cutover: no DNS, direct-IP client registration

H@H has no hostname of its own — the client connects **out** to the H@H
network and the central server records whichever public IP:8888 it observes
the connection coming from (`k8s-manifests/hath/values.yaml` `hostPort`
exposes `8888` on whichever node the pod is scheduled to; `docs/MIGRATION.md`
placement moves this to `legion-node4`'s public IP directly, permanently).
There is no A/AAAA record to move — "cutover" here means: confirm
`legion-node4`'s Hetzner Cloud Firewall allows inbound TCP `8888`
(`legion-node4-hath` inventory entry, `scope = "public"`), start the
host-native `hath` unit, and confirm the H@H network sees the new endpoint:

```sh
ssh node4.jeiang.dev -- sudo journalctl -u hath -f
```

Watch for incoming connection log lines once traffic starts arriving (the
client itself reports connectivity health in its own logs on a periodic
interval). Cross-check via the H@H client dashboard on the E-Hentai/ExHentai
site the client's login data authenticates against — it shows the client as
"Online" with the currently observed IP once the K8s-side pod is scaled to
zero (below) and the host-native one is the only thing answering `8888`.

### Narrow the fleet-wide interim firewall opening

`modules/hosts/legion/default.nix` currently opens TCP `8888` on **every**
Legion node (`allowedTCPPorts = ... ++ [8888]`), documented there as an
interim measure "for now" because the K3s scheduler could place the hath pod
on any node — "Narrow this during their cutover runbooks." Now that H@H is
confirmed live and stable on `legion-node4` (per the verification above),
remove the blanket exception so only `legion-node4`'s own inventory-derived
opening (already present, `_service-inventory.nix` `hath.firewall`) allows
`8888`:

```diff
-        allowedTCPPorts = firewallPortsFor config.networking.hostName "tcp" "public" ++ [8888];
+        allowedTCPPorts = firewallPortsFor config.networking.hostName "tcp" "public";
```

Then deploy every node (not just `legion-node4`) so the other four stop
allowing `8888`:

```sh
just deploy legion-node1
just deploy legion-node2
just deploy legion-node3
just deploy legion-node5
just deploy legion-node4
```

Verify `8888` is closed on a non-node4 node and still open on node4:

```sh
nc -zv -w3 node1.jeiang.dev 8888   # expect refused/timeout
nc -zv -w3 node4.jeiang.dev 8888   # expect open
```

### Rollback

```sh
kubectl -n hath scale deployment/hath --replicas=1
```

Point Hetzner Cloud Firewall/traffic back to whichever node the K8s pod
lands on (its `hostPort` follows the scheduler). **State divergence
warning**: any cache/download activity after cutover exists only in
`/mnt/hath`, not the PVC — cache loss on rollback is tolerable per the
Workload Inventory (re-fills from the network), but login-data divergence is
not; only roll back if you catch a problem quickly.

### Post-verify (gated on Safety Rules)

```sh
kubectl -n hath patch pv <hath-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
helm -n hath uninstall hath
```

## NetBird DNS Repoint (piece 5.7)

After `modules/nixos/blocky.nix` (piece 5.5) is deployed and verified on
`legion-node3` (and piece 3.4's NetBird client enrollment has given it a
peer IP), repoint the NetBird Custom DNS Zone that currently resolves
`blocky-dns.dns.k8s.jeiang.vpn` through the Kubernetes operator's
`NetworkRouter`/`NetworkResource` (`k8s-manifests/netbird-resources`,
`k8s-manifests/blocky-dns`) to `legion-node3`'s own NetBird peer address
instead.

### Deploy and get node3's peer address

```sh
just deploy legion-node3
ssh node3.jeiang.dev -- sudo systemctl status blocky
ssh node3.jeiang.dev -- sudo netbird status   # or via the dashboard
```

Note the peer's assigned NetBird IP (not a value this repo can pin — it's
assigned by the NetBird server at enrollment time).

### Repoint the zone

In the NetBird dashboard (Settings → DNS → Nameservers/Custom Zones),
find the zone matching `networkRouter.dnsZoneRef.name`
(`k8s-manifests/netbird-resources/values.yaml`: `k8s.jeiang.vpn`) and change
its nameserver from the operator-managed `NetworkRouter`'s address to
`legion-node3`'s peer address noted above.

### Verify peer DNS resolution

From an already-enrolled peer (e.g. `artemis`), resolve a name Blocky itself
would answer for (not the `k8s.jeiang.vpn` zone, which only ever pointed at
the old `blocky-dns` Service — confirm ordinary upstream resolution now
flows through the new peer):

```sh
dig @<node3-peer-ip> jeiang.dev
```

Expect a normal answer, proving `legion-node3`'s Blocky is reachable and
serving DNS over the NetBird interface exactly as
`modules/nixos/blocky.nix`'s firewall-scoping comment describes (bound on
every interface, but only reachable via `trustedInterfaces`).

### Remove the k8s blocky-dns release

```sh
helm -n dns uninstall blocky-dns
```

This removes `blocky-dns`'s own `NetworkResource`. Leave the shared
`NetworkRouter`/`netbird-resources` chart itself alone here if anything else
still depends on it at this point in the migration (e.g. Phase 6's
monitoring `NetworkResource`s, `k8s-manifests/monitoring/README.md` "NetBird
Exposure") — full teardown of the operator-managed NetBird resources is
governed by whichever migration piece is the last consumer, not this one.

### Monitoring counterpart (forward reference)

`docs/MIGRATION.md` piece 5.5 also calls for exposing raw VictoriaMetrics/
VictoriaLogs on `legion-node3`'s NetBird address the same way, replacing
their own dropped `NetworkResource`s
(`k8s-manifests/monitoring/README.md` "NetBird Exposure"). That's Phase 6
(piece 6.1's monitoring module + `docs/runbooks/monitoring-cutover.md`), not
this runbook — noted here only so the eventual removal of the shared
`NetworkRouter`/`netbird-resources` chart isn't attempted before Phase 6
also finishes with it.

## Explicit non-steps

- **Hetzner Load Balancer deletion, Traefik removal, and K3s teardown** are
  Phase 7 only (Cutover Safety Rule 3). Nothing in this runbook touches any
  of them.
- **The shared NetBird `NetworkRouter`/`netbird-resources` chart's full
  removal**: only `blocky-dns`'s own release/`NetworkResource` is removed
  above; the shared chart stays until nothing else depends on it (see
  "Monitoring counterpart" above).
- **Bitwarden Secrets Manager operator removal**: shared infrastructure
  removed with the rest of K3s in Phase 7, not per-service here.
