# Runbook: Hetzner Volume Provisioning

Operator runbook for attaching a Hetzner Volume to a Legion node and wiring
it into the flake declaratively. Covers every retained-data service's
Volume (`modules/hosts/legion/_service-inventory.nix`): NetBird server,
Pocket ID, Actual Budget, and H@H. Review [`AGENTS.md`](../../AGENTS.md)
before running any command here.

**This replaces the old "add an `/etc/fstab` line by hand" instruction.**
The mount is now declarative: `modules/hosts/legion/default.nix` derives a
`fileSystems` entry for every inventory service whose `volume` has an
`hcloudVolumeId` set, by Hetzner Volume ID path
(`/dev/disk/by-id/scsi-0HC_Volume_<id>`), with `nofail` so a missing Volume
never blocks boot. The corresponding service's systemd unit is guarded
(`unitConfig.ConditionPathIsMountPoint`/`RequiresMountsFor`) so it refuses
to start unless the Volume is actually mounted — no more editing `fstab` by
hand, and no more risk of a service silently initializing state on the root
disk.

**New Volumes, not the old K3s PVCs**: per the operator's decision, each
service gets a *new* Hetzner Volume, not the existing `hcloud-volumes` PVC
backing it in the cluster. Data still moves from the old PVC to the new
Volume — that's each service's own migration runbook (`apps-migration.md`,
`netbird-migration.md`, `pocket-id-migration.md`), not this one.

**Not through disko**: `modules/hosts/legion/disko.nix` manages only the
node's root disk (`/dev/sda`). These Volumes are attached and mounted
separately, following the precedent in
`modules/hosts/artemis/disko.nix` (its own `fileSystems` entries outside
`disko.devices`) — never through disko's destroy/format flow.

## Per-service Volumes

| Service | Node | Mountpoint | Inventory Volume name | Size |
| --- | --- | --- | --- | --- |
| NetBird server | `legion-node2` | `/mnt/netbird` | `legion-node2-netbird` | 10 GiB |
| Pocket ID | `legion-node2` | `/mnt/pocket-id` | `legion-node2-pocket-id` | 10 GiB |
| Actual Budget | `legion-node4` | `/mnt/actual-budget` | `legion-node4-actual-budget` | 10 GiB |
| H@H | `legion-node4` | `/mnt/hath` | `legion-node4-hath` | 40 GiB |

Sizes match each service's `volume.sizeGiB` in
`modules/hosts/legion/_service-inventory.nix`.

## Procedure (per service)

Repeat for each row above. `--server` attaches the Volume to the named
server in one step; `--format ext4` creates the filesystem in the same
call. Do **not** pass `--automount` — NixOS owns the mount via the
declarative `fileSystems` entry (below), not `hcloud`/cloud-init.

1. **Create, attach, and format the Volume:**

    ```sh
    hcloud volume create --name legion-node4-hath --size 40 --server legion-node4 --format ext4
    ```

    Substitute the name, size, and `--server` for the row you're
    provisioning.

2. **Get its numeric ID:**

    ```sh
    hcloud volume describe legion-node4-hath -o format='{{.ID}}'
    ```

3. **Paste the ID into the inventory:** set that service's
    `volume.hcloudVolumeId` in `modules/hosts/legion/_service-inventory.nix`
    to the printed ID (a string), commit the change.

4. **Deploy the owning node:**

    ```sh
    just deploy legion-node4
    ```

    This activates the flake's `fileSystems` mount (Part 1c) and — once
    mounted — lets the service's own mount guard (Part 2) allow it to
    start. Repeat steps 1-4 independently for each of the four services;
    they don't need to land together.

5. **Verify the mount:**

    ```sh
    ssh node4.jeiang.dev -- findmnt /mnt/hath
    ```

    Expect the `by-id` device path from step 1, not `/dev/sdb` or similar —
    confirms the Volume was matched by its stable ID, not attachment order.
    Then confirm the guarded service actually started:

    ```sh
    ssh node4.jeiang.dev -- sudo systemctl status hath
    ```

## Redeploying later

`just deploy` never reformats an already-provisioned Volume — the
`fileSystems` entry only *mounts* the device (`fsType = "ext4"` describes
the existing filesystem to mount, it does not create one); reformatting
only happens if you explicitly run `hcloud volume create --format` again
against a *different* Volume. A routine redeploy of a node with its
Volume(s) already mounted is safe to run repeatedly.

## If a Volume is detached or missing

`nofail` on the `fileSystems` entry means the node still boots and stays
reachable over SSH/deploy-rs even if the Volume is unattached or slow to
appear. The dependent service simply won't start
(`ConditionPathIsMountPoint` fails) until the Volume is mounted again —
check `findmnt <mountpoint>` first, then `hcloud volume describe
<name>` to confirm it's still attached to the right server.
