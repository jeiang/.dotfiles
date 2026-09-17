{self, ...}: let
  basePackages = pkgs: [
    self.packages.${pkgs.stdenv.hostPlatform.system}.helix
    pkgs.erdtree
    pkgs.fd
    pkgs.ripgrep
  ];
in {
  nixos.modules = {
    base = {pkgs, ...}: {
      environment.systemPackages = basePackages pkgs;
    };

    legion = {pkgs, ...}: {
      environment.systemPackages = with pkgs; [
        self.packages.${pkgs.stdenv.hostPlatform.system}.git-minimal
        bandwhich
        dig
        duf
        file
        (ouch.override {enableUnfree = true;})
        procs
        xh
      ];
    };

    artemis = {
      pkgs,
      lib,
      ...
    }: {
      environment.systemPackages = with pkgs; [
        self.packages.${pkgs.stdenv.hostPlatform.system}.git
        self.packages.${pkgs.stdenv.hostPlatform.system}.difft
        cachix
        dig
        glow
        bandwhich
        bingrep
        choose
        devenv
        duf
        file
        hyperfine
        libtree
        (ouch.override {enableUnfree = true;})
        parallel
        procs
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
  };

  darwin.modules.base = {pkgs, ...}: {
    environment.systemPackages = basePackages pkgs;
  };
}
