{self, ...}: {
  flake.nixosModules.toolbox = {
    pkgs,
    lib,
    ...
  }: {
    environment.systemPackages = with pkgs; [
      self.packages.${pkgs.stdenv.hostPlatform.system}.git
      self.packages.${pkgs.stdenv.hostPlatform.system}.difft
      self.packages.${pkgs.stdenv.hostPlatform.system}.helix
      cachix
      fd
      dig
      glow
      bandwhich
      bingrep
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
      (writeShellApplication {
        name = "trash";
        text = ''
          ${lib.getExe gomi} "$@"
        '';
      })
      tokei
      xh
    ];
  };
}
