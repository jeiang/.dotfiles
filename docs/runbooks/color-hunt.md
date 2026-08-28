# Color Hunt Validator: first-deploy activation

Delete this runbook when every step below is done and
`https://color-hunt.jeiang.dev` serves the app: the steady state needs no
runbook (updates are a `color-hunt` input bump + `just deploy`, and restore
is covered by docs/runbooks/backup-restore.md like every other restic set).

The `legion-color-hunt` Volume (id 106729764) is provisioned and attached
to legion-node2; the inventory entry carries its id.

## 1. Deploy (after CI has pushed closures for the commit)

```sh
just deploy legion-node2
just deploy legion-node1
just deploy artemis
```

On artemis the model fetch unit (`color-hunt-models.service`) downloads
~900MB into `/var/lib/color-hunt-models` before the worker starts. The
directory is new, so there is no pre-existing state to migrate --
`just migrate-persist` on artemis is only needed if a reboot happens
between adding the persistence entry and the fetch completing, and is
harmless to run anyway.

## 2. Netbird ACL (dashboard-side, like all ACLs)

Verified open at first deploy (a TCP probe from artemis to
100.89.86.24:8867 got connection-refused, i.e. reached the host): the
current policy already lets artemis reach legion-node2's ports, so
nothing to do unless the policy is later tightened. The organizer's own
devices need no ACL -- they come in through the edge at
color-hunt.jeiang.dev.

## 3. Verify

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://color-hunt.jeiang.dev
# 401: gate up
curl -su jeiang:<password> https://color-hunt.jeiang.dev/api/hunts
# []: app up
ssh artemis -- systemctl status color-hunt-worker
# active, polling
```

Then upload a photo through the UI and watch it go queued → analyzing →
done with a verdict. The basic_auth credential lives in the operator's
password manager (generated at first deploy; the Caddyfile holds only the
bcrypt hash).
