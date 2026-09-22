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
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    upstream = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    pinned = lib.importJSON ./hashes.json;
  in {
    packages.claude-code = inputs.wrapper-modules.lib.wrapPackage (_: {
      inherit pkgs;
      # llm-agents lags Anthropic's releases; ./hashes.json supplies a newer release until llm-agents catches up.
      package =
        if lib.versionOlder upstream.version pinned.version
        then upstream.override (prev: {platformSource = args: prev.platformSource (args // {hashesFile = ./hashes.json;});})
        else upstream;
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
