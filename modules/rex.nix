{
  self,
  inputs,
  ...
}: {
  nixos.modules.base = {config, ...}: let
    user = config.preferences.user.name;
    netbird = "${config.services.netbird.clients.default.service.name}.service";
    meshIP = self.lib.netbirdPeers.${config.networking.hostName};
    port = "7297";
  in {
    imports = [inputs.rex.nixosModules.default];

    # Anonymous access is confined to the NetBird interface, where the
    # Admin to Legion policy permits only infra_admin peers.
    services.rex.loginServer = {
      enable = true;
      allowAnonymous = true;
      extraListen = ["${meshIP}:${port}"];
      accounts.${user}.principals = ["anonymous"];
      defaults.anonymous = user;
    };

    networking.nftables.tables.rex = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority -10;
          iifname != "${config.services.netbird.clients.default.interface}" ip daddr ${meshIP} tcp dport ${port} drop
        }
      '';
    };

    systemd.services.rex-login-server = {
      after = [netbird];
      wants = [netbird];
      # The mesh address appears only once NetBird connects; keep retrying the bind until then.
      startLimitIntervalSec = 0;
    };
  };

  nixos.modules.artemis.persistence.data.directories = [
    {
      directory = ".local/state/rex";
      mode = "0700";
    }
  ];
}
