{
  self,
  inputs,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages.omp = let
      # An overlay, not a file in ~/.omp/agent: omp owns config.yml there and
      # rewrites it whenever a session changes a setting. PI_CONFIG_FILES
      # rather than --config, which only the launch, acp and models commands take.
      settings = (pkgs.formats.yaml {}).generate "omp-config.yml" {
        tools.approvalMode = "yolo";
      };
    in
      inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
        runShell = [
          ''export PI_CONFIG_FILES=${settings}''
          # Read at launch so the key never enters the store; absent before the first activation that installs it.
          ''[ -r ${self.lib.facts.typesafeApiKeyPath} ] && export TYPESAFE_API_KEY="$(cat ${self.lib.facts.typesafeApiKeyPath})"''
        ];
      });
  };
}
