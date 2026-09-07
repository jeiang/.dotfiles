# Runbook: wger (workout manager)

Operator runbook for wger on artemis behind the edge at `wger.jeiang.dev`
([ADR 0015](../adr/0015-run-unpackaged-applications-as-oci-containers.md)).
Review [`AGENTS.md`](../../AGENTS.md) before running any command here.

| Unit (artemis) | Listens | Role |
| --- | --- | --- |
| `nginx.service` | 0.0.0.0:8880 (mesh only) | Static/media files, `/ps/` stream proxy, front for gunicorn |
| `podman-wger-web.service` | 127.0.0.1:8000 | Django + gunicorn |
| `podman-wger-worker.service`, `podman-wger-beat.service` | none | Celery |
| `podman-wger-powersync.service` | 127.0.0.1:8090 | Mobile offline sync |
| `postgresql.service`, `redis-wger.service` | loopback | State and cache |
| `wger-powersync-compact.timer` | daily 03:00 | PowerSync op-log compaction |

On legion-node1, `oauth2-proxy.service` (127.0.0.1:4180) turns Pocket ID
into a Caddy `forward_auth` backend. Browser paths go through it; `/api`,
`/allauth` (the app's login API), `/ps`, `/static`, and `/media` do not,
because the mobile app authenticates with a wger username and password and
never sees the OIDC flow.

## Mobile app

The app logs in with a wger password, not Pocket ID. Set one for the
proxy-created user in the web UI (profile, change password), then in the
app use server `https://wger.jeiang.dev` with that username and password.
Offline sync goes through `/ps/` automatically.

## Exercise and ingredient data

Celery syncs exercises, images, and videos weekly from wger.de. The
ingredient database is large and is only synced on demand:

```bash
ssh artemis.jeiang.vpn 'bash -c "doas podman exec wger-web python3 manage.py sync-ingredients"'
```

## Upgrades

Bump the `image` and `powersyncImage` tags in `modules/nixos/wger/default.nix`
and deploy. Migrations run on container start. Check the PowerSync release
notes for storage migrations; the service runs them itself on start.

## Backups

None. `/var/lib/wger` (media, beat state) and `/var/lib/postgresql` are
persisted across the artemis root rollback but are not in any off-node
Backup Set.
