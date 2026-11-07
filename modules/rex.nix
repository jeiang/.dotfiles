{
  self,
  inputs,
  ...
}: {
  nixos.modules.base = {
    config,
    lib,
    pkgs,
    ...
  }: let
    user = self.lib.facts.userName;
    meshIP = self.lib.netbirdPeers.${config.networking.hostName};
    port = "7297";
    # netbird.service being active does not mean the mesh address exists
    # yet: a switch that restarts both races NetBird's reconnect, and a
    # failed bind fails the whole switch. Hold the start until it is there.
    waitMeshAddress = pkgs.writeShellApplication {
      name = "rex-wait-for-mesh-address";
      runtimeInputs = [pkgs.coreutils pkgs.iproute2];
      text = ''
        for _ in $(seq 60); do
          [[ $(ip -4 addr show) == *" ${meshIP}/"* ]] && exit 0
          sleep 1
        done
        exit 1
      '';
    };
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
      after = [self.lib.netbirdUnit];
      wants = [self.lib.netbirdUnit];
      # The mesh address appears only once NetBird connects; keep retrying the bind until then.
      startLimitIntervalSec = 0;
      serviceConfig.ExecStartPre = lib.getExe waitMeshAddress;
    };
  };

  nixos.modules.artemis.persistence.data.directories = [
    {
      directory = ".local/state/rex";
      mode = "0700";
    }
  ];
}
