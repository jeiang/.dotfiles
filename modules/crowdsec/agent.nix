{
  self,
  config,
  lib,
  ...
}: let
  crowdsecLapiPort = config.legion.services.crowdsec.ports.lapi;

  # Each agent's machine password and bouncer key live in its own shard, readable by alda (which
  # registers them) and the agent's node.
  agents = {
    crowdsec-agent = {
      node = "ricklent";
      sopsFile = ./secrets.agent.yaml;
    };
    crowdsec-agent-zantark = {
      node = "zantark";
      sopsFile = ./secrets.zantark.yaml;
    };
  };
in {
  flake.lib.crowdsecAgentShards = lib.mapAttrs' (_: agent: lib.nameValuePair agent.node agent.sopsFile) agents;

  legion.services =
    builtins.mapAttrs (_: agent: {
      inherit (agent) node;
      module = "crowdsec-agent";
      units = ["crowdsec" "crowdsec-firewall-bouncer"];
    })
    agents;

  nixos.modules.crowdsec-agent = {
    config,
    lib,
    ...
  }: let
    host = config.networking.hostName;
    sopsFile = self.lib.crowdsecAgentShards.${host};
    machineSecret = "crowdsec/machine-${host}-password";
    bouncerSecret = "crowdsec/bouncer-${host}-firewall";

    lapiUrl = "http://${self.lib.legionAddress host "alda"}:${toString crowdsecLapiPort}";
    credentialsTemplate = "crowdsec-lapi-credentials.yaml";
  in {
    sops = {
      secrets = {
        ${machineSecret} = {inherit sopsFile;};
        ${bouncerSecret} = {
          inherit sopsFile;
          restartUnits = ["crowdsec-firewall-bouncer.service"];
        };
      };

      templates.${credentialsTemplate} = {
        owner = config.services.crowdsec.user;
        restartUnits = ["crowdsec.service"];
        content = ''
          url: ${lapiUrl}
          login: ${host}
          password: ${config.sops.placeholder.${machineSecret}}
        '';
      };
    };

    services.crowdsec = {
      enable = true;

      hub = {
        collections = ["crowdsecurity/sshd"];
        parsers = [
          "crowdsecurity/syslog-logs"
          "crowdsecurity/geoip-enrich"
          "crowdsecurity/dateparse-enrich"
        ];
      };

      settings = {
        config = {
          api.client.credentials_path = config.sops.templates.${credentialsTemplate}.path;
          api.server.enable = false;
          # NetBird's proxy unconditionally binds its pprof server on 6060.
          prometheus.listen_port = 6061;
        };

        acquisitions = [
          {
            source = "journalctl";
            journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
            labels.type = "syslog";
          }
        ];
      };
    };

    systemd.services.crowdsec = {
      path = lib.mkForce [config.systemd.package];
      serviceConfig.SupplementaryGroups = ["systemd-journal"];
    };

    services.crowdsec-firewall-bouncer = {
      enable = true;
      settings = {
        mode = "nftables";
        api_url = lapiUrl;
      };
      registerBouncer.enable = false;
      secrets.apiKeyPath = config.sops.secrets.${bouncerSecret}.path;
    };
  };
}
