{
  self,
  inputs,
  ...
}: let
  port = "7297";
in {
  nixos.modules.base = {
    config,
    lib,
    pkgs,
    ...
  }: let
    user = self.lib.facts.userName;
    meshIP = self.lib.netbirdPeers.${config.networking.hostName};
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

  # The Rex app starts its own server without a network listener. This one
  # takes the default socket first, and the app attaches to it.
  darwin.modules.base = {
    lib,
    pkgs,
    ...
  }: let
    rex = inputs.rex.packages.${pkgs.stdenv.hostPlatform.system}.rex;
    rexServer = pkgs.writeShellApplication {
      name = "rex-server";
      runtimeInputs = [rex self.packages.${pkgs.stdenv.hostPlatform.system}.netbird pkgs.jq];
      text = ''
        for _ in $(seq 60); do
          ip=$(netbird status --json 2>/dev/null | jq -r '.netbirdIp // empty' || true)
          ip=''${ip%/*}
          if [[ -n $ip ]] && ifconfig | grep "inet $ip " >/dev/null; then
            exec rex server run --extra-listen "$ip:${port}" --allow-anonymous
          fi
          sleep 1
        done
        exit 1
      '';
    };
  in {
    launchd.user.agents.rex-server.serviceConfig = {
      ProgramArguments = [(lib.getExe rexServer)];
      EnvironmentVariables.TERMINFO_DIRS = "${rex}/share/terminfo:";
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}
