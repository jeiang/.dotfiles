{ config, ... }:
{

  config = {
    # TODO: mkif the opt is enabled
    # boot.initrd = lib.mkIf (false) {
    #   postDeviceCommands = lib.mkBefore (lib.optionalString (!isSystemdPhase1) wipe-script);
    #   # https://discourse.nixos.org/t/impermanence-vs-systemd-initrd-w-tpm-unlocking/25167/2
    #   systemd = lib.mkIf isSystemdPhase1 {
    #     initrdBin = with pkgs; [ coreutils btrfs-progs ];
    #     services.btrfs-rollback = {
    #       description = "Rollback BTRFS root subvolume to a pristine state";
    #       wantedBy = [ "initrd.target" ];
    #       # LUKS/TPM process
    #       after = [ "systemd-cryptsetup@${hostname}.service" ];
    #       before = [ "sysroot.mount" ];
    #       unitConfig.DefaultDependencies = "no";
    #       serviceConfig.Type = "oneshot";
    #       script = wipe-script;
    #     };
    #   };
    # };
  };
}
