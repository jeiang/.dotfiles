{
  self,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    checks = lib.mkMerge [
      (lib.mkIf (system == "x86_64-linux") (
        lib.mapAttrs' (name: nixosConfig: lib.nameValuePair "toplevel-${name}" nixosConfig.config.system.build.toplevel) self.nixosConfigurations
        // {
          statix = pkgs.runCommand "statix-check" {nativeBuildInputs = [pkgs.statix];} ''
            statix check ${self}
            touch $out
          '';
        }
      ))
      # Only the toplevel: garret push sends its whole closure, which already holds every darwin package zakkart installs.
      (lib.mkIf (system == "aarch64-darwin") {
        zakkart-system = self.darwinConfigurations.zakkart.config.system.build.toplevel;
      })
    ];
  };
}
