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
      desktop = self.wrapperModules.niri.wrap {
        inherit pkgs;
        terminal = lib.getExe self'.packages.terminal;
      };
      environment = inputs.wrappers-modules.lib.wrapPackage {
        inherit pkgs;
        package = self'.packages.fish;
        extraPackages = with pkgs; [
          self'.packages.git
          self'.packages.difft
          self'.packages.starfish
          fd
          bandwhich
          bingrep
          cachix
          choose
          devenv
          duf
          erdtree
          eza
          file
          fzf
          hyperfine
          jq
          libtree
          # (ouch.override {enableUnfree = true;})
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
