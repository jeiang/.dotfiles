{
  self,
  inputs,
  ...
}: let
  sopsFile = ./secrets.yaml;
  apiKey = self.lib.facts.typesafeApiKey;
  apiKeyPath = self.lib.facts.typesafeApiKeyPath;

  claudeCode = {
    config,
    pkgs,
    group,
  }: {
    sops.secrets.${apiKey} = {
      inherit sopsFile group;
      owner = config.preferences.user.name;
    };
    environment.systemPackages = [self.packages.${pkgs.stdenv.hostPlatform.system}.claude-code];
  };
in {
  perSystem = {pkgs, ...}: {
    packages.claude-code = inputs.wrapper-modules.lib.wrapPackage (_: {
      inherit pkgs;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
      # Read at launch so the key never enters the store; absent before the first activation that installs it.
      runShell = [''[ -r ${apiKeyPath} ] && export TYPESAFE_API_KEY="$(cat ${apiKeyPath})"''];
    });
  };

  nixos.modules.artemis = {
    config,
    pkgs,
    ...
  }:
    claudeCode {
      inherit config pkgs;
      group = "users";
    };

  darwin.modules.base = {
    config,
    pkgs,
    ...
  }:
    claudeCode {
      inherit config pkgs;
      group = "staff";
    };
}
