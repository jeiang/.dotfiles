{
  config,
  inputs,
  self,
  ...
}: let
  service = config.legion.services.nanolight-server;
  sopsFile = ./secrets.yaml;
in {
  legion.services.nanolight-server = {
    node = "zantark";
    module = "nanolight-server";
    units = ["nanolight-server"];
    ports.app = 8890;
    # Mesh only: zakkart reaches it through the Admin to Legion policy. The
    # state is a merge of what the clients hold, and a client's first sync
    # with an empty server pushes its own, so it needs no backup.
    firewall = [];
  };

  nixos.modules.nanolight-server = {config, ...}: {
    imports = [inputs.nanolight.nixosModules.server];

    services.nanolight-server = {
      enable = true;
      listenAddress = self.lib.netbirdPeers.${service.node};
      port = service.ports.app;
      tokensFile = config.sops.secrets."nanolight/tokens".path;
    };

    sops.secrets."nanolight/tokens" = {
      inherit sopsFile;
      restartUnits = ["nanolight-server.service"];
    };
  };

  darwin.modules.base = {config, ...}: {
    imports = [inputs.nanolight.darwinModules.default];

    programs.nanolight = {
      enable = true;
      # Xcode's Apple Development certificate, by SHA-1: keeps the Accessibility
      # grant across rebuilds. Signing also needs Apple's WWDR G3 intermediate.
      codesignIdentity = "BEFA7CA1803B0F13E47D3D32831AD134C97C1DE9";
      settings.sync = {
        url = "http://${self.lib.netbirdPeers.${service.node}}:${toString service.ports.app}";
        token_file = config.sops.secrets."nanolight/token".path;
      };
    };

    sops.secrets."nanolight/token" = {
      inherit sopsFile;
      owner = config.preferences.user.name;
    };
  };
}
