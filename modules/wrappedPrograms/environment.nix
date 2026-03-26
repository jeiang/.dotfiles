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
      terminal = self'.packages.ghostty;
      desktop = inputs.wrapper-modules.wrappers.niri.wrap {
        inherit pkgs;
        terminal = lib.getExe self'.packages.terminal;
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
          # (ouch.override {enableUnfree = true;})
          ouch
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
          # TODO: replace with wrapped version
          EDITOR = lib.getExe pkgs.helix;
        };
      };
    };
  };
}
