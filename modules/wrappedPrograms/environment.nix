{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    self',
    inputs',
    ...
  }: {
    packages = {
      terminal = pkgs.ghostty;
      environment = inputs.wrapper-modules.lib.wrapPackage {
        inherit pkgs;
        package = self'.packages.fish;
        # needed for nixos to recognize this as a shell
        passthru.shellPath = "/bin/fish";
        extraPackages = with pkgs; [
          self'.packages.git
          self'.packages.difft
          self'.packages.helix
          fd
          bandwhich
          bingrep
          cachix
          choose
          inputs'.devenv.packages.default
          duf
          erdtree
          file
          hyperfine
          libtree
          (ouch.override {enableUnfree = true;})
          parallel
          procs
          ripgrep
          rnr
          sad
          tdf
          trashy
          tokei
          xh
        ];
        env = {
          EDITOR = lib.getExe self'.packages.helix;
        };
      };
    };
  };
}
