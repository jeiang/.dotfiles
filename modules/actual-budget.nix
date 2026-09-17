{self, ...}: let
  dataDir = "/mnt/actual-budget";
  port = 5006;
in {
  legion.services.actual-budget = {
    node = "legion-node4";
    module = "actual-budget";
    stateful = true;
    units = ["actual"];
    ports.app = port;
    firewall = [
      {
        inherit port;
        proto = "tcp";
        scope = "private";
      }
    ];
    volume = {
      name = "legion-actual-budget";
      mountpoint = dataDir;
      hcloudVolumeId = "106251385";
      sizeGiB = 10;
    };
    backupSet = [dataDir];
  };

  nixos.modules.actual-budget = _: {
    services.actual = {
      enable = true;
      settings = {inherit dataDir port;};
    };

    systemd.services.actual =
      {
        serviceConfig.MemoryMax = "320M";
      }
      // self.lib.mountGuard dataDir {};
  };
}
