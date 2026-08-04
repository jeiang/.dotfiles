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
    checks = lib.mkMerge [
      (lib.mkIf (system == "x86_64-linux") (
        lib.mapAttrs' (name: package: lib.nameValuePair "package-${name}" package)
        # devenv's own scaffolding, not a package this repo exports.
        (builtins.removeAttrs self'.packages ["devenv-up" "devenv-test" "container-processes" "container-shell"])
        // lib.mapAttrs' (name: nixosConfig: lib.nameValuePair "toplevel-${name}" nixosConfig.config.system.build.toplevel) self.nixosConfigurations
        // {
          statix = pkgs.runCommand "statix-check" {nativeBuildInputs = [pkgs.statix];} ''
            statix check ${self}
            touch $out
          '';
        }
      ))
      (lib.mkIf (system == "aarch64-darwin") {
        zakkart-system = self.darwinConfigurations.zakkart.config.system.build.toplevel;
      })
    ];
  };
}
