{lib, ...}: {
  # Refuses to start a stateful unit unless dataDir is mounted. With owner, it also reasserts
  # ownership in ExecStartPre, because tmpfiles runs before a late Volume mount.
  flake.lib.mountGuard = dataDir: {
    pkgs ? null,
    owner ? null,
    mode ? null,
  }:
    lib.recursiveUpdate
    {
      unitConfig = {
        RequiresMountsFor = [dataDir];
        ConditionPathIsMountPoint = dataDir;
      };
    }
    (lib.optionalAttrs (owner != null) {
      serviceConfig.ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o ${owner} -g ${owner} -m ${mode} ${dataDir}";
    });
}
