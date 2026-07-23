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

        hermes-approval = pkgs.runCommand "hermes-approval-check" {nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.python3];} ''
          python -B ${self}/modules/nixos/test_hermes_approval.py
          touch $out
        '';

        # Keep an exact Hermes-focused system check that does not depend on
        # local access to the encrypted production secrets.
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
