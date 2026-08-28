{self, ...}: {
  flake.nixosModules.actual-budget = _: let
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
      // self.lib.mountGuard dataDir;
  };
}
