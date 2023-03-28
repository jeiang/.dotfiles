{ pkgs, config, ... }:
let
  encrypted-device = "/dev/disk/by-uuid/5f63dd70-3bb5-4c7d-b592-80ec4c011fb1";
  hostname = config.networking.hostName;
  unencrypted-device = "/dev/mapper/${hostname}";
  boot-partition = "/dev/disk/by-label/boot";

  # See ./rollback.sh for the original w/ comments
  wipe-script = ''
    # Mount
    mkdir -p /mnt
    mount -o subvol=/ /dev/mapper/${hostname} /mnt

    # Wiping root
    btrfs subvolume list -o /mnt/root |
      cut -f9 -d' ' |
      while read subvolume; do
        echo "deleting /$subvolume subvolume..."
        btrfs subvolume delete "/mnt/$subvolume"
      done &&
      echo "deleting /root subvolume..." &&
      btrfs subvolume delete /mnt/root

    echo "restoring blank /root subvolume..."
    btrfs subvolume snapshot /mnt/@blank /mnt/root

    # Wiping home
    btrfs subvolume list -o /mnt/home/aidanp |
      cut -f9 -d' ' |
      while read subvolume; do
        echo "deleting /$subvolume subvolume..."
        btrfs subvolume delete "/mnt/$subvolume"
      done &&
      echo "deleting /home/aidanp subvolume..." &&
      btrfs subvolume delete /mnt/home/aidanp

    echo "restoring blank /home/aidanp subvolume..." &&
      btrfs subvolume snapshot /mnt/home/@blank /mnt/home/aidanp

    # TODO: when generic over users, use uid here
    chown 1000 /mnt/home/aidanp

    # Unmount
    umount /mnt
  '';
in
{
  # There is a very high change of agenix running before etc symlinks get mounted. so am directlinking instead
  # TODO: make dynamic based on users??
  age.identityPaths = [
    "/persist/etc/ssh/ssh_host_ed25519_key"
    "/persist/etc/ssh/ssh_host_rsa_key"
    "/persist/home/aidanp/.ssh/id_ed25519"
    "/persist/home/aidanp/.ssh/id_rsa"
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_rsa_key"
    "/home/aidanp/.ssh/id_ed25519"
    "/home/aidanp/.ssh/id_rsa"
  ];

  boot.initrd.postDeviceCommands = pkgs.lib.mkBefore wipe-script;

  # Filesystems
  boot.initrd.luks.devices.${hostname}.device = encrypted-device;

  fileSystems = {
    "/" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=root" "compress=zstd" "noatime" ];
    };

    "/home" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=home" "compress=zstd" "noatime" ];
      neededForBoot = true;
    };

    "/nix" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=nix" "compress=zstd" "noatime" ];
    };

    "/persist" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=persist" "compress=zstd" "noatime" ];
      neededForBoot = true;
    };

    "/var/log" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=log" "compress=zstd" "noatime" ];
      neededForBoot = true;
    };

    "/boot" = {
      device = boot-partition;
      fsType = "vfat";
    };
  };
}
