# Runbook: Pocket ID Migration

Operator runbook for [`docs/MIGRATION.md`](../MIGRATION.md) piece 4.2: moving
Pocket ID from the Experimental Cluster (`k8s-manifests/idp` chart) to
`legion-node2` (`modules/nixos/pocket-id.nix`, piece 4.1). Review
[`AGENTS.md`](../../AGENTS.md) before running any command here, and
[`docs/runbooks/restore.md`](restore.md) for the Restic mechanics this
runbook's Safety Rule 1 step depends on.

This runbook assumes [`docs/runbooks/edge-cutover.md`](edge-cutover.md) has
already landed the Edge Node (the `auth.jeiang.dev` Caddy route exists and is
verified up to the point where it 502s because piece 4.1 isn't deployed yet —
expected, not a regression). It does not cut DNS for any other Edge Node
host, and does not touch the Hetzner Load Balancer, Traefik, or K3s (Cutover
Safety Rule 3, Phase 7 only).

## Prerequisites

### sops secrets

Create both with `just sops-edit` before deploying `legion-node2` with
`pocket-id` enabled:

| Secret | Consumed by | Value |
| --- | --- | --- |
| `pocket-id/encryption-key` | `modules/nixos/pocket-id.nix` | **Copy the exact value from Bitwarden Secrets Manager** (`pocket-id-encryption-key`, `k8s-manifests/idp/README.md` "Generate Bitwarden Secrets"). Not a fresh secret: it decrypts fields already written to the retained SQLite DB by the live cluster deployment. A different value makes the copied database's encrypted columns unreadable. |
| `pocket-id/static-api-key` | same | Copy from Bitwarden (`pocket-id-static-api-key`). Only used for the static/bootstrap API, not for decrypting existing data, but copy it anyway for continuity of any existing automation that depends on it. |

`restic/password` and `restic/s4-env` are prerequisites of piece 2.1, not
this runbook — see `docs/runbooks/restore.md` if they don't already exist.

### Hetzner Volume

Attach, format, and mount a Hetzner Volume at `/mnt/pocket-id` on
`legion-node2` (inventory entry `legion-node2-pocket-id`,
`modules/hosts/legion/_service-inventory.nix`) before the first deploy with
`pocket-id` enabled. Neither this flake nor `modules/nixos/pocket-id.nix`
declares a `fileSystems` entry for it (Hetzner Volume mounting is an
external prerequisite per `DESIGN.md`) — add a durable mount (e.g. an
`/etc/fstab` line by device UUID/ID) so it survives a reboot. Confirm it's
mounted (`ssh node2.jeiang.dev -- findmnt /mnt/pocket-id`) before proceeding;
otherwise `services.pocket-id`'s own `systemd.tmpfiles.rules` creates an
empty `/mnt/pocket-id` directory on the root disk instead, and Pocket ID's
state silently lands on disposable storage.

### Deploy

```sh
just deploy legion-node2
```

This brings up `pocket-id` with an empty state (no PVC content copied yet) —
intentional, so you can confirm the unit starts cleanly before trusting it
with the copied database in the next section. Confirm before proceeding:

```sh
ssh node2.jeiang.dev -- sudo systemctl status pocket-id
ssh node2.jeiang.dev -- sudo journalctl -u pocket-id --since -5m
```

Expect Pocket ID to come up with a **fresh, empty** database at this point.

## Values migration from Bitwarden Secrets Manager

Per the table above: copy `pocket-id-encryption-key` and
`pocket-id-static-api-key` from Bitwarden Secrets Manager into the matching
sops secrets — both must keep their exact live values for the retained
database to stay readable.

## State copy (Safety Rules 1 and 2)

### Quiesce the Kubernetes deployment

```sh
kubectl -n idp scale deployment/idp-pocket-id --replicas=0
kubectl -n idp get pods   # confirm it has terminated
```

### Copy PVC content to the Volume

The chart mounts its PVC straight at `/app/data` and points
`DB_CONNECTION_STRING` directly at `/app/data/pocket-id.db`
(`k8s-manifests/idp/templates/pocket-id.yaml`) — a **flat** layout, the PVC
content sits at the mount root with no extra nesting.
`modules/nixos/pocket-id.nix` sets `WorkingDirectory=dataDir` (`/mnt/pocket-id`)
and leaves the app's relative defaults (`DB_CONNECTION_STRING`
`data/pocket-id.db`, `UPLOAD_PATH` `data/uploads`) untouched, so they resolve
to `${dataDir}/data/*` — a **nested** layout. The copy below must land the
chart's flat PVC content under `/mnt/pocket-id/data/`, not directly in
`/mnt/pocket-id/`, to match the module's defaults.

With the deployment scaled to zero, nothing else holds the PVC open, so
mount it into a disposable pod to copy out:

```sh
kubectl -n idp run pocket-id-pvc-copy --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"pocket-id-pvc-copy","image":"alpine:3.20","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/app/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"idp-pocket-id"}}]}}'
kubectl -n idp wait --for=condition=Ready pod/pocket-id-pvc-copy --timeout=60s
kubectl -n idp exec pocket-id-pvc-copy -- tar czf /tmp/pocket-id-data.tar.gz -C /app/data .
kubectl -n idp cp idp/pocket-id-pvc-copy:/tmp/pocket-id-data.tar.gz ./pocket-id-data.tar.gz
kubectl -n idp delete pod pocket-id-pvc-copy
```

Confirm the actual PVC name first if unsure:
`kubectl -n idp get pvc` (chart default is `<release>-pocket-id`, i.e.
`idp-pocket-id` for a release named `idp`; adjust the `claimName` above if
different).

Transfer to `legion-node2` and extract under the module's `data/` subdir,
with the module's expected ownership (the chart's pod runs without an
explicit non-default `securityContext` UID note beyond the general chart
defaults, so the archive's UID/GID are not meaningful here — always chown to
the module's user by name, not by preserving the source UID):

```sh
scp ./pocket-id-data.tar.gz deploy@node2.jeiang.dev:/tmp/
ssh node2.jeiang.dev -- sudo mkdir -p /mnt/pocket-id/data
ssh node2.jeiang.dev -- sudo tar xzf /tmp/pocket-id-data.tar.gz -C /mnt/pocket-id/data
ssh node2.jeiang.dev -- sudo chown -R pocket-id:pocket-id /mnt/pocket-id
ssh node2.jeiang.dev -- sudo rm /tmp/pocket-id-data.tar.gz
rm ./pocket-id-data.tar.gz
```

`pocket-id:pocket-id` is `services.pocket-id.user`/`.group`
(`modules/nixos/pocket-id.nix` inherits the nixpkgs module's defaults) — both
default to `pocket-id`; confirm with
`ssh node2.jeiang.dev -- sudo systemctl show pocket-id -p User -p Group`
if the module config ever overrides them.

### Start the copied state and back it up

```sh
ssh node2.jeiang.dev -- sudo systemctl restart pocket-id
ssh node2.jeiang.dev -- sudo journalctl -u pocket-id --since -2m
```

Confirm the service started against the copied database (existing users,
clients, and settings visible — check via the admin UI once DNS moves below,
or query the SQLite file directly:
`sudo sqlite3 /mnt/pocket-id/data/pocket-id.db "PRAGMA integrity_check;"` if
you need to check before DNS cutover).

Now exercise Safety Rule 1 for real, against the copied-in state (not empty
state from the earlier deploy check): confirm a backup runs and restore it
to a scratch directory per `docs/runbooks/restore.md`'s full procedure.

```sh
ssh node2.jeiang.dev -- sudo systemctl start restic-backups-pocket-id.service
ssh node2.jeiang.dev -- sudo systemctl status restic-backups-pocket-id.service
```

Then follow `docs/runbooks/restore.md` "List snapshots" → "Restore to a
scratch directory" → "Verify content" against
`s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/legion-node2/pocket-id`.
Record the verification (date, snapshot ID) here once done — this clears
Safety Rule 1 for Pocket ID's eventual Kubernetes release removal below.

Safety Rule 2 (retain the PVC/Volume for the rollback window): **do not**
delete the `idp-pocket-id` PVC or flip its reclaim policy yet. That's part
of "Post-verify" below, after the rollback window has passed.

## Cutover

### Start-order verification

```sh
ssh node2.jeiang.dev -- sudo systemctl status pocket-id
ssh node2.jeiang.dev -- sudo journalctl -u pocket-id --since -5m
```

### Verification via the edge (pre-DNS)

```sh
curl -sSI --resolve auth.jeiang.dev:443:178.156.226.145 https://auth.jeiang.dev/
```

Replace `178.156.226.145` if `legion-node1`'s address has changed
(`modules/hosts/legion/default.nix`). Expect a real response now instead of
the pre-piece-4.1 `502` noted in `docs/runbooks/edge-cutover.md`.

### OIDC logins

Log in through the admin UI (via the `curl --resolve` host override above,
or a `/etc/hosts` entry, until DNS actually moves) and confirm every
existing OIDC client still authenticates against the copied database:

- **Grafana**: sign in via the Pocket ID SSO option on the Grafana login
  page (`grafana.jeiang.dev` — still cluster-hosted until piece 6.1 lands;
  this only checks that Pocket ID's side of the existing client
  registration survived the copy).
- **Attic**: `attic login --set-default pocketid https://attic.jeiang.dev/ --oidc pocketid`
  (client ID `0304a563-8b46-4731-9eb0-224e8f0d1c7b`,
  `modules/nixos/attic.nix` `oidc.providers` pocketid entry) — confirm the
  login succeeds and `attic_role` claim-based permissions apply as expected.
  Attic itself may not be deployed yet depending on piece ordering; if not,
  this check can wait until piece 5.1/5.6.
- **NetBird federation**: from the NetBird dashboard's login screen, use the
  Pocket ID SSO option (configured at runtime in NetBird's GUI settings, per
  `docs/MIGRATION.md` piece 3.1's auth note — the federation config lives in
  NetBird's own retained database, not Pocket ID's, so this checks that
  NetBird's stored client ID/secret still resolve against the moved Pocket
  ID issuer).
- **kubectl**: confirm `kubectl` OIDC login still works against the K3s
  apiserver (`--oidc-issuer-url=https://auth.jeiang.dev`, client ID
  `44213aa3-11eb-401d-922c-c7f81c3a9e37`,
  `modules/hosts/legion/default.nix` `apiTlsSans`/k3s `extraFlags`) — this
  stays relevant until K3s retires in Phase 7.

### Email delivery check (v2.9.0 → v2.10.0 SMTP migration)

**Required, not optional.** The deployed chart runs Pocket ID v2.9.0 with
env-var SMTP config (`k8s-manifests/idp/values.yaml` `pocketId.smtp.*`,
consumed by the app as `SMTP_HOST`/`SMTP_PORT`/`SMTP_FROM`/`SMTP_USER`/
`SMTP_PASSWORD_FILE`/`SMTP_TLS`). The pinned nixpkgs v2.10.0 binary moved
SMTP configuration into DB-backed app-config rows with no `SMTP_*` env
support at all (`modules/nixos/pocket-id.nix`'s comment on the version jump,
confirmed against the fork's own `backend/internal/common/env_config.go` /
`backend/internal/service/email_service.go` / `backend/internal/model/app_config.go`
source at piece 4.1). Because the DB is retained end-to-end (copied above),
whatever SMTP config existed in the source deployment's DB rows travels with
it automatically — but confirm this actually happened rather than assuming
it:

1. From the admin UI (Settings → Email, or wherever v2.10.0 exposes it), check whether SMTP settings are already populated after the state copy.
2. Trigger a real send to confirm delivery, not just presence of the settings: send a one-time access email to a test user, or trigger an email-verification email.
3. **If SMTP rows are missing or empty** (the copied DB predates any DB-backed SMTP config, or the v1→v2 app migration didn't carry the old env-var values into rows), re-enter the iCloud SMTP settings in the admin UI manually, per the table below.
4. Re-send the test email from step 2 and confirm delivery before considering this step complete.

iCloud SMTP settings (source: `k8s-manifests/idp/values.yaml` `pocketId.smtp`):

| Field | Value |
| --- | --- |
| Host | `smtp.mail.me.com` |
| Port | `587` |
| From | `noreply@jeiang.dev` |
| User | `jeiang` |
| TLS | STARTTLS |
| Password | The iCloud app-specific password from Bitwarden Secrets Manager (`pocket-id-smtp-password`, `k8s-manifests/idp/README.md` "Generate Bitwarden Secrets") — copy it into the admin UI form directly; there is nothing for this flake's sops secrets to hold since v2.10.0 has no env-var SMTP path. |

### DNS cutover

`auth.jeiang.dev` is covered by the `*.jeiang.dev` wildcard certificate the
edge already manages (`modules/nixos/edge/default.nix`), but its A/AAAA
record moves individually, not automatically with the wildcard. Follow
`docs/runbooks/edge-cutover.md`'s "Staged DNS cutover" list and ordering —
that runbook explicitly places `auth.jeiang.dev` in the group of hosts
"only once each service's own migration piece ... has actually deployed and
been verified per its own runbook": this runbook is that verification. Move
`auth.jeiang.dev` only after every check above (edge reachability, OIDC
logins, email delivery) passes, then repeat the edge-cutover.md per-host
verification (same `curl` check, without `--resolve`, from outside the
Hetzner private network; check
`ssh node1.jeiang.dev -- tail -f /var/log/caddy/access.log` for the new
traffic).

Rollback: point the `auth.jeiang.dev` A/AAAA record back at the Hetzner
Load Balancer. The low TTL from `edge-cutover.md`'s "lower TTLs first" step
means this propagates quickly; the Kubernetes deployment (scaled back up,
below) resumes serving immediately.

## Rollback

```sh
kubectl -n idp scale deployment/idp-pocket-id --replicas=1
```

Then revert the `auth.jeiang.dev` DNS record per "DNS cutover" above.

**State divergence warning**: any user, client, or setting created or
changed *after* cutover (while `legion-node2`'s Pocket ID was live) exists
only in `/mnt/pocket-id`'s database, not in the Kubernetes PVC. Scaling the
Kubernetes deployment back up resumes it from the state as of the copy
above — a rollback after real usage discards everything that happened on
the new instance in between. Only roll back if you catch a problem quickly;
past that window, fix forward instead.

## Post-verify (gated on Safety Rules)

Only after:

- Safety Rule 1: the Restic backup + scratch-directory restore above is
  recorded as verified.
- Safety Rule 2's rollback window (default two weeks per
  `docs/MIGRATION.md`) has elapsed with the host-native instance stable.

Retain or detach the PVC's backing Hetzner Volume (flip the PV reclaim
policy to `Retain`, or manually detach after deletion — `hcloud-volumes`
defaults to `Delete`) **before** removing the release:

```sh
kubectl -n idp patch pv <idp-pocket-id-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

Then remove the release and its operator-managed dependents (dropped per
`docs/MIGRATION.md` Confirmed Decisions — Kubernetes-only concerns, not
migrated):

```sh
helm -n idp uninstall idp
```

## Explicit non-steps

- **Hetzner Load Balancer deletion, Traefik removal, and K3s teardown** are
  Phase 7 only (Cutover Safety Rule 3). Nothing in this runbook touches any
  of them — `kubectl` OIDC login against the K3s apiserver (above) still
  needs Pocket ID reachable regardless of where it runs.
- **Bitwarden Secrets Manager / operator-managed dependents removal**: only
  `idp`'s own Helm release is uninstalled above; the Bitwarden Secrets
  Manager operator itself is shared infrastructure removed with the rest of
  K3s in Phase 7, not per-service here.
