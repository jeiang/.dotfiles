{
  flake.nixosModules.exh-home = {
    pkgs,
    lib,
    ...
  }: let
    port = 8888;
  in {
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

    services.prometheus.scrapeConfigs = [
      {
        job_name = "exh h@home";
        scheme = "https";
        tls_config.insecure_skip_verify = true;
        static_configs = [
          {
            targets = [
              "localhost:${toString port}"
            ];
          }
        ];
      }
    ];

    networking.firewall.allowedTCPPorts = [port];
    networking.firewall.allowedUDPPorts = [port];
  };
}
