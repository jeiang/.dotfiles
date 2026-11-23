{
  # Refuses to start a stateful unit unless dataDir is mounted, and reasserts its
  # ownership in ExecStartPre, because tmpfiles runs before a late Volume mount.
  flake.lib.mountGuard = dataDir: {
    pkgs,
    owner,
    mode,
  }: {
    unitConfig = {
      RequiresMountsFor = [dataDir];
      ConditionPathIsMountPoint = dataDir;
    };
    serviceConfig.ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o ${owner} -g ${owner} -m ${mode} ${dataDir}";
  };
}
