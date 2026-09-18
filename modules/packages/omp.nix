{
  self,
  inputs,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages.omp = inputs.wrapper-modules.lib.wrapPackage (_: {
      inherit pkgs;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
      # Read at launch so the key never enters the store; absent before the first activation that installs it.
      runShell = [''[ -r ${self.lib.facts.typesafeApiKeyPath} ] && export TYPESAFE_API_KEY="$(cat ${self.lib.facts.typesafeApiKeyPath})"''];
    });
  };
}
