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
      # trippy needs cap_net_raw for its raw-socket tracing; the module wraps `trip` with it.
      programs.trippy.enable = true;
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
        lazygit
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
        watchexec
        xh
      ];
    };
  };

  darwin.modules.base = {pkgs, ...}: {
    environment.systemPackages =
      basePackages pkgs
      ++ (with pkgs; [
        age-plugin-yubikey
        gh-dash
        lazygit
        # trippy needs root on darwin; there is no security.wrappers equivalent, so `trip` is run with sudo.
        trippy
        watchexec
      ]);
  };
}
