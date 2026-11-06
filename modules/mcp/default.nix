{
  self,
  inputs,
  config,
  ...
}: let
  token = "grafana/mcp-token";

  # Mesh address, not grafana.jeiang.dev: probing the edge gets the client banned by CrowdSec.
  grafanaUrl = "http://${self.lib.netbirdPeers.${config.legion.services.monitoring.node}}:${toString config.legion.services.monitoring.ports.grafana}";

  servers = pkgs: tokenPath:
    inputs.mcp-servers-nix.lib.mkConfig pkgs {
      flavor = "claude-code";
      fileName = "mcp.json";
      programs = {
        nixos = {
          enable = true;
          # nixpkgs marks fastmcp-slim broken against mcp 2, which fastmcp (and so mcp-nixos) pulls in by default.
          package = pkgs.mcp-nixos.override {
            python3Packages = pkgs.python3Packages.overrideScope (_: prev: {mcp = prev.mcp_1;});
          };
        };
        grafana = {
          enable = true;
          env.GRAFANA_URL = grafanaUrl;
          passwordCommand.GRAFANA_SERVICE_ACCOUNT_TOKEN = ["cat" tokenPath];
        };
      };
    };
in {
  flake.lib.grafanaMeshUrl = grafanaUrl;

  shared.modules.workstation = {
    config,
    pkgs,
    ...
  }: {
    sops.secrets.${token} = {
      sopsFile = ./secrets.yaml;
      owner = self.lib.facts.userName;
    };

    # Only omp reads a declarative user-level MCP file; Claude Code and Codex
    # rewrite their own config, so `just mcp-register` copies these into it.
    hjem.users.${self.lib.facts.userName}.files."${self.lib.agentHomes.omp}/mcp.json".source = servers pkgs config.sops.secrets.${token}.path;
  };
}
