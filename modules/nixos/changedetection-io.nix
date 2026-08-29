{self, ...}: {
  flake.nixosModules.changedetection-io = {pkgs, ...}: let
    dataDir = "/mnt/changedetection-io";

    listenPort = 5000;
  in {
    services.changedetection-io = {
      enable = true;
      # 0.0.0.0, not loopback: the reverse proxy arrives over the NetBird
      # tunnel interface; reachability is scoped by the firewall.
      listenAddress = "0.0.0.0";
      port = listenPort;
      datastorePath = dataDir;
      baseURL = "https://watch.proxy.jeiang.dev";
      behindProxy = true;

      # Deliberately off (the defaults, stated so it doesn't look like an
      # oversight): either fetcher starts a headless Chromium OCI container.
      webDriverSupport = false;
      playwrightSupport = false;
    };

    systemd.services.changedetection-io =
      {
        serviceConfig = {
          MemoryMax = "256M";
          # The module's tmpfiles rule for datastorePath is not ordered after
          # the Volume mount; re-assert ownership here since ExecStartPre
          # inherits RequiresMountsFor. `+` runs it as root.
          ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o changedetection-io -g changedetection-io -m 0750 ${dataDir}";
        };
      }
      // self.lib.mountGuard dataDir;
  };
}
