{
  self,
  config,
  lib,
  ...
}: let
  blackboxPort = 9115;
  jobs = {
    http_2xx = "blackbox-http";
    tcp_connect = "blackbox-tcp";
    dns = "blackbox-dns";
  };

  probesFor = module: builtins.filter (p: p.module == module) (builtins.attrValues config.monitoring.probes);
  targetsOf = module: p:
    if module == "http_2xx"
    then map (t: "http://${t}") p.targets
    else p.targets;
  tiersOf = module: lib.zipAttrsWith (_: lib.concatLists) (map (p: {${p.tier} = targetsOf module p;}) (probesFor module));
in {
  # Each probe target becomes the exporter's ?target= and the instance label.
  monitoring.scrape = lib.mapAttrs' (module: job:
    lib.nameValuePair job {
      type = "probe";
      settings = {
        metrics_path = "/probe";
        params.module = [module];
        static_configs =
          lib.mapAttrsToList (tier: targets: {
            inherit targets;
            labels = {
              type = "probe";
              inherit tier;
            };
          })
          (tiersOf module);
        relabel_configs = [
          {
            source_labels = ["__address__"];
            target_label = "__param_target";
          }
          {
            source_labels = ["__param_target"];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:${toString blackboxPort}";
          }
        ];
      };
    })
  (lib.filterAttrs (module: _: probesFor module != []) jobs);

  nixos.modules.monitoring = {pkgs, ...}: let
    # blackbox otherwise attempts ip6 first; every probe target is an IPv4
    # literal on the private network.
    blackboxConfig = (pkgs.formats.yaml {}).generate "blackbox-exporter.yml" {
      modules = {
        http_2xx = {
          prober = "http";
          timeout = "5s";
          http.preferred_ip_protocol = "ip4";
        };
        tcp_connect = {
          prober = "tcp";
          timeout = "5s";
          tcp.preferred_ip_protocol = "ip4";
        };
        dns = {
          prober = "dns";
          timeout = "5s";
          dns = {
            query_name = self.lib.netbirdDomain;
            query_type = "A";
            valid_rcodes = ["NOERROR"];
            preferred_ip_protocol = "ip4";
          };
        };
      };
    };
  in {
    services.prometheus.exporters.blackbox = {
      enable = true;
      port = blackboxPort;
      # Loopback-only: keeps the /probe handler (an SSRF-shaped
      # `GET /probe?target=` primitive) off the network.
      listenAddress = "127.0.0.1";
      configFile = blackboxConfig;
    };

    systemd.services.prometheus-blackbox-exporter.serviceConfig.MemoryMax = "32M";
  };
}
