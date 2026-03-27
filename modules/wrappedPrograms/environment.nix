{
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    lib,
    self',
    ...
  }: {
    packages = {
      terminal = lib.nixGL.wrap pkgs.ghostty;
      desktop = inputs.wrapper-modules.wrappers.niri.wrap {
        inherit pkgs;
        terminal = "${lib.getExe self'.packages.terminal} +new-window";
        imports = [self.wrapperModules.niri];
      };
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
          devenv
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
