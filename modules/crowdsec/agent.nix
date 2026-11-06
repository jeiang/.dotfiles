{
  self,
  config,
  ...
}: let
  engineModule = config.nixos.modules.crowdsec-engine;
in {
  legion.services =
    builtins.mapAttrs (_: node: {
      inherit node;
      module = "crowdsec-agent";
      units = ["crowdsec" "crowdsec-firewall-bouncer"];
    }) {
      crowdsec-agent = "ricklent";
      crowdsec-agent-zantark = "zantark";
    };

  nixos.modules.crowdsec-agent = {config, ...}: let
    host = config.networking.hostName;
    machineSecret = self.lib.crowdsecMachineSecret host;
    credentialsTemplate = "crowdsec-lapi-credentials.yaml";
  in {
    imports = [engineModule];

    sops.templates.${credentialsTemplate} = {
      owner = config.services.crowdsec.user;
      restartUnits = ["crowdsec.service"];
      content = ''
        url: ${self.lib.crowdsecLapiUrl host}
        login: ${host}
        password: ${config.sops.placeholder.${machineSecret}}
      '';
    };

    services.crowdsec.settings.config = {
      api.client.credentials_path = config.sops.templates.${credentialsTemplate}.path;
      api.server.enable = false;
      # NetBird's proxy unconditionally binds its pprof server on 6060.
      prometheus.listen_port = 6061;
    };
  };
}
