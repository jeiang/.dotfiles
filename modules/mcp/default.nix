{
  self,
  inputs,
  config,
  ...
}: let
  sopsFile = ./secrets.yaml;
  token = "grafana/mcp-token";
  tokenPath = "/run/secrets/${token}";

  # Mesh address, not grafana.jeiang.dev: probing the edge gets the client banned by CrowdSec.
  grafanaUrl = "http://${self.lib.netbirdPeers.legion-node3}:${toString config.legion.services.monitoring.ports.grafana}";

  servers = pkgs:
    inputs.mcp-servers-nix.lib.mkConfig pkgs {
      flavor = "claude-code";
      fileName = "mcp.json";
      programs = {
        nixos.enable = true;
        grafana = {
          enable = true;
          env.GRAFANA_URL = grafanaUrl;
          passwordCommand.GRAFANA_SERVICE_ACCOUNT_TOKEN = ["cat" tokenPath];
        };
      };
    };

  mcp = {
    config,
    pkgs,
    group,
  }: {
    sops.secrets.${token} = {
      inherit sopsFile group;
      owner = config.preferences.user.name;
    };

    # Only omp reads a declarative user-level MCP file; Claude Code and Codex
    # rewrite their own config, so the operator registers these there.
    hjem.users.${config.preferences.user.name}.files.".omp/agent/mcp.json".source = servers pkgs;
  };
in {
  nixos.modules.artemis = {
    config,
    pkgs,
    ...
  }:
    mcp {
      inherit config pkgs;
      group = "users";
    };

  darwin.modules.base = {
    config,
    pkgs,
    ...
  }:
    mcp {
      inherit config pkgs;
      group = "staff";
    };
}
