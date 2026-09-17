{self, ...}: {
  legion.services.actual-budget = {
    node = "legion-node4";
    module = "actual-budget";
    stateful = true;
    firewall = [
      {
        port = self.lib.ports.legion-node4.actual-budget;
        proto = "tcp";
        scope = "private";
      }
    ];
    volume = {
      name = "legion-actual-budget";
      mountpoint = "/mnt/actual-budget";
      hcloudVolumeId = "106251385";
      sizeGiB = 10;
    };
    backupSet = ["/mnt/actual-budget"];
    backupPauseUnits = ["actual.service"];
  };

  nixos.modules.actual-budget = _: let
    dataDir = "/mnt/actual-budget";
  in {
    services.actual = {
      enable = true;
      settings = {
        inherit dataDir;
        port = self.lib.ports.legion-node4.actual-budget;
      };
    };

    systemd.services.actual =
      {
        serviceConfig.MemoryMax = "320M";
      }
      // self.lib.mountGuard dataDir {};
  };
}
