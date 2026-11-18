# Runbook: deploying

How systems reach the hosts, and what a manual deploy must do. The
guardrails in [`AGENTS.md`](../../AGENTS.md) still apply: a deploy needs the
user's approval for that action and target.

## Deploying

- Deploy only after the pull request is merged and CI has pushed the
  closures to garret, so targets substitute instead of building.
- Every NixOS host upgrades itself (`modules/auto-upgrade.nix`). A `main`
  run reports each host's system as the commit status `system/<host>` once
  garret holds it. `auto-upgrade.service` runs hourly, ten minutes apart
  per host. When the status differs from the running system, it evaluates
  that commit of `main`, substitutes the system and switches. It arms a
  timer that switches back after 10 minutes, and disarms it only when sshd
  is active and NetBird reports its management server connected within 2
  minutes. A system that was rolled back is not tried again. It never
  reboots a host, so a new kernel waits for the operator. On artemis it
  fails instead of switching when the kernel, the initrd or a persistence
  entry differs from the booted system, and its timer stops while a game
  runs. A failed run raises `SystemdUnitFailed`. `just status` compares
  each host with `main`.
- A manual deploy is for what the upgrade cannot do: artemis with `--boot`,
  a host whose upgrade failed, and zakkart. The next run puts a host that
  runs anything else back on `main`; stop `auto-upgrade.timer` on the host
  to keep a test deploy.
- zakkart activates itself: `just nh darwin switch`. Give the operator that
  command, not `darwin-rebuild`.
- From the Mac: `just deploy <host> --skip-checks --remote-build`. The fleet
  form is `just deploy-legion --remote-build`: it passes `--skip-checks`
  itself, so do not pass it again. Check each node after its deploy; `just
  deploy-legion` does not replace that.
- deploy-rs magic rollback protects only a live switch. On artemis,
  removing a service that owns an impermanence bind mount cannot switch
  live: deploy with `--boot`, then reboot. Kernel and initrd changes also
  need `--boot` and a reboot.
- artemis boots a new generation with 2 tries. `boot-health.service`
  blesses it once sshd is active and NetBird reports its management server
  connected, within 5 minutes; otherwise the host reboots, and the second
  failure falls back to the previous generation. After a reboot, confirm
  `readlink /run/current-system` is the deployed closure. A redeploy of the
  same closure reuses the spent entry: to retry it, the operator renames
  `/boot/loader/entries/nixos-<hash>+0-2.conf` to `nixos-<hash>+2.conf`.

## artemis persistence

- The root subvolume is rolled back to empty on every boot. Only
  `persistence.*` paths survive, and impermanence never copies existing
  data into `/persist`.
- Before deploying any change to `persistence.*` (an added entry, or an
  entry moved between system, data, and cache), run
  `just migrate-persist <checkout>` on artemis as root from a checkout of
  the new revision, then deploy with `--boot` and reboot. After the reboot
  the old data is only in `old_roots`.
- Persisting a path does not back it up. A backup set is an explicit
  allowlist, and every path in it must also be a `persistence.*` path: each
  module adds its own paths, excludes and snapshot-stop units to
  `backups.persist` next to its persistence entries. artemis backs them up
  from a read-only btrfs snapshot of `/persist`, so the paths in its snapshots
  carry a `/persist/.backup-snapshot` prefix. A btrfs snapshot is not
  recursive: a backup path that is, or contains, a nested subvolume would
  back up as an empty directory.
