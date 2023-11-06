{ pkgs
, lib
, config
, ...
}:
let
  isSystemdPhase1 = config.boot.initrd.systemd.enable;
  hostname = config.networking.hostName;
  # TODO: use builtins.mapAttrs users.user to generate home wipers dynamically for users
  wipe-script = ''
    # Mount
    mkdir -p /mnt
    mount -t btrfs -o subvol=/ /dev/mapper/${hostname} /mnt

    # Wiping root
    btrfs subvolume list -o /mnt/root |
      cut -f9 -d' ' |
      while read subvolume; do
        btrfs subvolume delete "/mnt/$subvolume"
      done &&
      btrfs subvolume delete /mnt/root

    btrfs subvolume snapshot /mnt/@blank /mnt/root

    # Wiping home
    btrfs subvolume list -o /mnt/home |
      cut -f9 -d' ' |
      while read subvolume; do
        btrfs subvolume delete "/mnt/$subvolume"
      done &&
      btrfs subvolume delete /mnt/home

    btrfs subvolume snapshot /mnt/@blank /mnt/home

    # HACK: TEMP: change to impermanence or something else
    ln -s /persist/etc/shadow /etc/shadow

    # Unmount
    umount /mnt
  '';
in
{
  boot.initrd.postDeviceCommands = lib.mkBefore (lib.optionalString (!isSystemdPhase1) wipe-script);
  # https://discourse.nixos.org/t/impermanence-vs-systemd-initrd-w-tpm-unlocking/25167/2
  boot.initrd.systemd = lib.mkIf isSystemdPhase1 {
    initrdBin = with pkgs; [ coreutils btrfs-progs ];
    services.btrfs-rollback = {
      description = "Rollback BTRFS root subvolume to a pristine state";
      wantedBy = [ "initrd.target" ];
      # LUKS/TPM process
      after = [ "systemd-cryptsetup@${hostname}.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = wipe-script;
    };
  };

  # for user mode impermanence
  programs.fuse.userAllowOther = true;

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/bluetooth"
      "/etc/NetworkManager/system-connections"
      {
        directory = "/var/lib/colord";
        user = "colord";
        group = "colord";
        mode = "u=rwx,g=rx,o=";
      }
    ];
    files = [
      "/etc/machine-id"
      "/etc/adjtime"
      "/var/lib/NetworkManager/secret_key"
      "/var/lib/NetworkManager/seen-bssids"
      "/var/lib/NetworkManager/timestamps"
      {
        file = "/etc/ssh/ssh_host_ed25519_key";
        parentDirectory = { mode = "u=rw,g=,o="; };
      }
      {
        file = "/etc/ssh/ssh_host_ed25519_key.pub";
        parentDirectory = { mode = "u=rw,g=r,o=r"; };
      }
      {
        file = "/etc/ssh/ssh_host_rsa_key";
        parentDirectory = { mode = "u=rw,g=,o="; };
      }
      {
        file = "/etc/ssh/ssh_host_rsa_key.pub";
        parentDirectory = { mode = "u=rw,g=r,o=r"; };
      }
    ];
  };
}
