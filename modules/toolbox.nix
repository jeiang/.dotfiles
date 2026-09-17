{self, ...}: {
  nixos.modules.legion = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      self.packages.${pkgs.stdenv.hostPlatform.system}.git-minimal
      self.packages.${pkgs.stdenv.hostPlatform.system}.helix
      bandwhich
      dig
      duf
      erdtree
      fd
      file
      (ouch.override {enableUnfree = true;})
      procs
      ripgrep
      xh
    ];
  };

  nixos.modules.artemis = {
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
