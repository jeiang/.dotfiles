{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.color-hunt = {pkgs, ...}: let
    # dataDir is the mountpoint itself, not a subdirectory: ReadWritePaths is
    # built before ExecStartPre runs, and a not-yet-existing path fails the
    # unit 226/NAMESPACE.
    dataDir = "/mnt/color-hunt";
    mountpoint = "/mnt/color-hunt";

    listenPort = self.lib.ports.legion-node2.color-hunt;
  in {
    imports = [inputs.color-hunt.nixosModules.server];

    services.color-hunt = {
      enable = true;
      port = listenPort;
      inherit dataDir;
    };

    systemd.services.color-hunt =
      {
        serviceConfig = {
          MemoryMax = "256M";
          # Fresh ext4 Volume root is root:root 0755; tmpfiles is not ordered
          # after the mount, ExecStartPre inherits RequiresMountsFor
          # (mountGuard). `+` runs it as root.
          ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o color-hunt -g color-hunt -m 0750 ${dataDir}";
        };
      }
      // self.lib.mountGuard mountpoint;
  };
}
