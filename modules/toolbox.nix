{
  self,
  inputs,
  ...
}: let
  basePackages = pkgs: [
    self.packages.${pkgs.stdenv.hostPlatform.system}.helix
    self.packages.${pkgs.stdenv.hostPlatform.system}.yazi
    self.packages.${pkgs.stdenv.hostPlatform.system}.zellij
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
    }: let
      system = pkgs.stdenv.hostPlatform.system;
      ripper = inputs.ripper.packages.${system}.default;
    in {
      environment.systemPackages = with pkgs;
        [
          self.packages.${system}.git
          self.packages.${system}.difft
          cachix
          dig
          glow
          bandwhich
          bingrep
          choose
          devenv
          duf
          file
          gh
          gh-dash
          hyperfine
          lazygit
          libtree
          (ouch.override {enableUnfree = true;})
          parallel
          procs
          rnr
          sad
          tdf
          tokei
          watchexec
          xh
          ripper
        ]
        # Shadows base's yazi: this one's T and d keys shell out to rip instead
        # of yazi's built-in trash crate (modules/packages/yazi/keymap.rip.toml).
        ++ [(lib.hiPrio self.packages.${system}.yazi-artemis)];

      # rip's fish/zsh completions live under share/fish and share/zsh, which
      # NixOS doesn't link into the profile by default (bash-completion already is).
      environment.pathsToLink = ["/share/fish" "/share/zsh"];

      systemd.user.timers.rip-empty = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
      systemd.user.services.rip-empty = {
        description = "Permanently delete trashed items older than 30 days";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe ripper} empty --older-than 30d -y";
        };
      };
    };
  };

  darwin.modules.base = {pkgs, ...}: {
    environment.systemPackages =
      basePackages pkgs
      ++ (with pkgs; [
        age-plugin-se
        age-plugin-yubikey
        gh-dash
        lazygit
        # trippy needs root on darwin; there is no security.wrappers equivalent, so `trip` is run with sudo.
        trippy
        watchexec
      ]);
  };
}
