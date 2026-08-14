# artemis always-on setup: one-time operator steps

Delete this file after all four steps are done and verified.

The always-on config (backup tunnel, setup-key enrollment, watchdog,
monitoring — see `modules/hosts/artemis/default.nix` and
`modules/nixos/backup-tunnel/`) deploys safely before these steps, but each
listed capability stays dormant until its step is done.

## 1. NetBird setup key (unattended re-enrollment)

The artemis shard ships a placeholder. Create a real key and fill it in:

- NetBird dashboard → Setup Keys → create a **reusable** key, no expiry
  (or long), auto-assign artemis's usual groups.
- `just sops-edit`, pick `modules/hosts/artemis/secrets.yaml`, replace
  `netbird.setup-key` with the key. Commit, deploy artemis.
- While in the dashboard: confirm **login expiration is disabled** for the
  artemis peer (or its group) — the current SSO login is what keeps the
  existing peer alive; the setup key only covers re-enrollment after state
  loss. Also confirm the access policies allow legion-node3 → artemis
  (the node-exporter scrape) and zakkart → artemis (Moonlight).

Note: if artemis ever re-enrolls via the setup key it gets a new peer IP;
update the artemis target in `modules/nixos/monitoring/default.nix`.

## 2. GitHub push key for gopass autosync

The public half of the key in the artemis shard:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOX0+7WspfbrRkoPBGInu6uEjj8O1wblcJlCuJJ4ukDw artemis-gopass-autosync
```

(Read the canonical value with `ssh-keygen -y -f /home/aidanp/.ssh/id_ed25519`
on artemis after deploy — do not trust this file if they differ.)

Add it at github.com → jeiang/pass → Settings → Deploy keys → **Allow write
access**. Verify on artemis: `gopass sync`.

## 3. Hetzner Cloud Firewall: UDP 51821 on legion-node1

The host firewall opens it via the inventory entry, but the Hetzner Cloud
Firewall is a manual per-port gate (see
`modules/hosts/legion/_service-inventory.nix` header): allow inbound
UDP 51821 from any source on legion-node1.

Verify after deploying node1 + artemis: `ssh node1.jeiang.dev`, then
`ssh 10.100.0.2` — that hop must work with netbird stopped on artemis
(`doas systemctl stop netbird` briefly) to prove independence from the mesh.

## 4. BIOS: restore power after loss

MSI X670E GAMING PLUS WIFI → Settings → Advanced → Power Management Setup →
**Restore after AC Power Loss: Power On**. While in there, confirm the
watchdog isn't disabled (sp5100_tco is active by default).
