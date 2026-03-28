{
  flake.nixosModules.exh-home = {
    pkgs,
    lib,
    ...
  }: {
    systemd.services.exh-home = {
      enable = true;
      description = "exh h@home client";
      wants = ["network-online.target"];
      after = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = let
        exh-name = "exh-home";
      in {
        User = exh-name;
        Group = exh-name;
        DynamicUser = true;
        ExecStart = ''
          ${lib.getExe pkgs.hath-rust} --enable-metrics --log-dir="/var/log/${exh-name}" --data-dir="/var/lib/${exh-name}" --cache-dir="/var/cache/${exh-name}" --temp-dir="/tmp" --download-dir="/var/run/${exh-name}"
        '';
        Restart = "on-failure";
        MemoryHigh = "100M";
        MemoryMax = "200M";
        CacheDirectory = exh-name;
        StateDirectory = exh-name;
        LogsDirectory = exh-name;
        RuntimeDirectory = exh-name;
        RuntimeDirectoryPreserve = "yes";
        ReadOnlyPaths = "/nix";
      };
    };
    services.caddy.virtualHosts.exh-metrics = rec {
      hostName = "hath-metrics.jeiang.dev";
      logFormat = null;
      extraConfig = ''
        import logging ${hostName}
        import compression
        import security_headers

        basic_auth {
          grafana $2a$14$yWcASm7EOvMzAQVbSNSu6eNFDdVux7E0fKsbJgqigMSES5B86Aiyu
        }

        rewrite * /metrics
        reverse_proxy 0.0.0.0:8888 {
          transport http {
            tls
            tls_insecure_skip_verify
          }
        }
      '';
    };

    networking.firewall.allowedTCPPorts = [8888];
    networking.firewall.allowedUDPPorts = [8888];
  };
}
