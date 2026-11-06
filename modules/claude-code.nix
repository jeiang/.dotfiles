{inputs, ...}: {
  shared.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code];
  };
}
