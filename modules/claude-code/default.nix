{
  self,
  inputs,
  ...
}: let
  sopsFile = ./secrets.yaml;
  apiKey = "typesafe/api-key";
  apiKeyPath = "/run/secrets/${apiKey}";

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
      package = pkgs.claude-code;
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
