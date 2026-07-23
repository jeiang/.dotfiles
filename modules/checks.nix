{
  self,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    self',
    system,
    ...
  }: {
    checks = lib.mkIf (system == "x86_64-linux") (
      lib.mapAttrs' (name: package: lib.nameValuePair "package-${name}" package)
      # devenv's own scaffolding, not a package this repo exports.
      (builtins.removeAttrs self'.packages ["devenv-up" "devenv-test" "container-processes" "container-shell"])
      // lib.mapAttrs' (name: nixosConfig: lib.nameValuePair "toplevel-${name}" nixosConfig.config.system.build.toplevel) self.nixosConfigurations
      // {
        statix = pkgs.runCommand "statix-check" {nativeBuildInputs = [pkgs.statix];} ''
          statix check ${self}
          touch $out
        '';

        # Hermes ships staged behind `enabled = false` in the Legion
        # inventory, so the regular toplevel checks never evaluate or build
        # its configuration. This forces it on so the dormant config can't
        # rot: an option typo fails eval here, a broken script derivation
        # fails the build. Secrets are enrolled only at activation
        # (docs/runbooks/hermes.md), so sops validation is skipped for this
        # synthetic system.
        toplevel-legion-node3-hermes-enabled =
          (self.nixosConfigurations.legion-node3.extendModules {
            modules = [
              {
                hermes.enable = true;
                observedSnapshot.enable = lib.mkForce true;
                sops.validateSopsFiles = false;
              }
            ];
          }).config.system.build.toplevel;
      }
    );
  };
}
