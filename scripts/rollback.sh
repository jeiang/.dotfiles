mkdir -p /mnt

# We first mount the btrfs root to /mnt
# so we can manipulate btrfs subvolumes.
mount -o subvol=/ /dev/mapper/enc /mnt

# While we're tempted to just delete /root and create
# a new snapshot from /@root, /root is already
# populated at this point with a number of subvolumes,
# which makes `btrfs subvolume delete` fail.
# So, we remove them first.
#
# /root contains subvolumes:
# - /root/var/lib/portables
# - /root/var/lib/machines
#
# I suspect these are related to systemd-nspawn, but
# since I don't use it I'm not 100% sure.
# Anyhow, deleting these subvolumes hasn't resulted
# in any issues so far, except for fairly
# benign-looking errors from systemd-tmpfiles.
btrfs subvolume list -o /mnt/root |
cut -f9 -d' ' |
while read subvolume; do
  echo "deleting /$subvolume subvolume..."
  btrfs subvolume delete "/mnt/$subvolume"
done &&
echo "deleting /root subvolume..." &&
btrfs subvolume delete /mnt/root

echo "restoring blank /root subvolume..."
btrfs subvolume snapshot /mnt/@root /mnt/root

# Assuming no subvolumes inside user home
echo "deleting /home/aidanp subvolume..." &&
btrfs subvolume delete /mnt/home/aidanp

echo "restoring blank /home/aidanp subvolume..." &&
btrfs subvolume snapshot /mnt/home/@aidanp /mnt/home/aidanp

# Because the image is restored by root, we don't have permissions
# for the home folder, which makes home manager act weird. So make
# aidanp own the folder like they should. aidanp uid = 1000.
chown 1000 /mnt/home/aidanp

# Once we're done rolling back to a blank snapshot,
# we can unmount /mnt and continue on the boot process.
umount /mnt
