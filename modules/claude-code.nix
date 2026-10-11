{inputs, ...}: let
  claudeCode = {pkgs, ...}: {
    environment.systemPackages = [inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code];
  };
in {
  nixos.modules.artemis = claudeCode;
  darwin.modules.base = claudeCode;
}
