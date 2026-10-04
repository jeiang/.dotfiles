{
  self,
  config,
  ...
}: let
  crowdsecLapiPort = config.legion.services.crowdsec.ports.lapi;
in {
  legion.services.crowdsec-agent = {
    node = "ricklent";
    module = "crowdsec-agent";
    units = ["crowdsec" "crowdsec-firewall-bouncer"];
  };

  nixos.modules.crowdsec-agent = {
    config,
    lib,
    ...
  }: let
    sopsFile = ./secrets.agent.yaml;

    lapiUrl = "http://${self.lib.legionAddress config.networking.hostName "alda"}:${toString crowdsecLapiPort}";
    credentialsTemplate = "crowdsec-lapi-credentials.yaml";
  in {
    sops = {
      secrets = {
        "crowdsec/machine-ricklent-password" = {inherit sopsFile;};
        "crowdsec/bouncer-ricklent-firewall" = {
          inherit sopsFile;
          restartUnits = ["crowdsec-firewall-bouncer.service"];
        };
      };

      templates.${credentialsTemplate} = {
        owner = config.services.crowdsec.user;
        restartUnits = ["crowdsec.service"];
        content = ''
          url: ${lapiUrl}
          login: ${config.networking.hostName}
          password: ${config.sops.placeholder."crowdsec/machine-ricklent-password"}
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

      settings.lapi.credentialsFile = config.sops.templates.${credentialsTemplate}.path;

      localConfig.acquisitions = [
        {
          source = "journalctl";
          journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
          labels.type = "syslog";
        }
      ];
    };

    # The nixpkgs unit empties PATH, and the journalctl datasource execs journalctl.
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
      secrets.apiKeyPath = config.sops.secrets."crowdsec/bouncer-ricklent-firewall".path;
    };
  };
}
