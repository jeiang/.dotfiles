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
      # Deliberately just the toplevel, with no package-* fan-out mirroring the
      # linux branch above. `garret push` sends a path's whole closure, so CI
      # building this one attribute already seeds every darwin path zakkart
      # installs. Measured 2026-08-07: of the 18 package checks darwin would
      # expose, the 7 whose outputs were in garret were exactly the 7 inside
      # this closure, and interior paths of it (btop, gmp, libaom,
      # etc-100-nix-darwin.conf) were all present too. A fan-out would only add
      # the packages zakkart does *not* install -- attic-server, caddy,
      # netbird-{server,relay,proxy} -- NixOS service components that a macOS
      # runner would compile from source and nothing would ever substitute.
      (lib.mkIf (system == "aarch64-darwin") {
        zakkart-system = self.darwinConfigurations.zakkart.config.system.build.toplevel;
      })
    ];
  };
}
