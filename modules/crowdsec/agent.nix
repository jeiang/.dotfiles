{
  self,
  config,
  ...
}: let
  engineModule = config.nixos.modules.crowdsec-engine;
in {
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
