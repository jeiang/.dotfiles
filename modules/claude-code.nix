{inputs, ...}: {
  shared.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code];
  };

  nixos.modules.artemis.persistence = {
    data.files = [".claude.json"];
    cache.directories = [".cache/claude-cli-nodejs"];
  };
}
