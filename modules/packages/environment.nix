{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    self',
    ...
  }: {
    packages = {
      environment = inputs.wrapper-modules.lib.wrapPackage {
        inherit pkgs;
        package = self'.packages.fish;
        # needed for nixos to recognize this as a shell
        passthru.shellPath = "/bin/fish";
        env = {
          EDITOR = lib.getExe self'.packages.helix;
        };
      };
    };
  };
}
