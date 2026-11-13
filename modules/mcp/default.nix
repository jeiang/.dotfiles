{
  self,
  inputs,
  ...
}: let
  servers = pkgs:
    inputs.mcp-servers-nix.lib.mkConfig pkgs {
      flavor = "claude-code";
      fileName = "mcp.json";
      programs.nixos = {
        enable = true;
        # nixpkgs marks fastmcp-slim broken against mcp 2, which fastmcp (and so mcp-nixos) pulls in by default.
        package = pkgs.mcp-nixos.override {
          python3Packages = pkgs.python3Packages.overrideScope (_: prev: {mcp = prev.mcp_1;});
        };
      };
    };
in {
  shared.modules.workstation = {pkgs, ...}: {
    # Only omp reads a declarative user-level MCP file; Claude Code and Codex
    # rewrite their own config, so `just mcp-register` copies these into it.
    hjem.users.${self.lib.facts.userName}.files."${self.lib.agentHomes.omp}/mcp.json".source = servers pkgs;
  };
}
