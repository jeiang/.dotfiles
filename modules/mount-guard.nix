{lib, ...}: {
  # Refuses to start a stateful unit unless dataDir is mounted, so a missing
  # Volume never initializes fresh state on the root disk. The optional
  # {pkgs, owner, mode} also emits the ExecStartPre that reasserts ownership,
  # since tmpfiles is not ordered after a late Volume mount and ExecStartPre
  # inherits RequiresMountsFor; `+` runs it as root despite User=.
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
