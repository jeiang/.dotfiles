{
  self,
  inputs,
  ...
}: {
  shared.modules = {
    base = {pkgs, ...}: let
      system = pkgs.stdenv.hostPlatform.system;
    in {
      environment.systemPackages = [
        self.packages.${system}.helix
        self.packages.${system}.yazi
        self.packages.${system}.ouch
        inputs.erdtree.packages.${system}.erdtree
        pkgs.fd
        pkgs.ripgrep
        # bandwhich needs root to capture on darwin, like trippy there.
        pkgs.bandwhich
      ];
      environment.pathsToLink = ["/share/fish"];
    };

    workstation = {pkgs, ...}: let
      system = pkgs.stdenv.hostPlatform.system;
    in {
      environment.systemPackages = [
        self.packages.${system}.git
        self.packages.${system}.difft
        pkgs.gh
        pkgs.gh-dash
        pkgs.lazygit
        pkgs.tokei
      ];
    };
  };

  nixos.modules = {
    base = {pkgs, ...}: {
      environment.systemPackages = with pkgs; [
        dig
        duf
        file
        procs
      ];
      # trippy needs cap_net_raw for its raw-socket tracing; the module wraps `trip` with it.
      programs.trippy.enable = true;
    };

    legion = {pkgs, ...}: {
      environment.systemPackages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.git-minimal
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
          glow
          devenv
          hyperfine
          rnr
          sad
          ripper
          # fish sources share/fish/vendor_conf.d from every XDG_DATA_DIRS entry, which includes the system profile.
          (writeTextDir "share/fish/vendor_conf.d/trash.fish" ''
            status is-interactive; and alias trash rip
          '')
        ]
        # Shadows base's yazi: this one's T and d keys shell out to rip instead
        # of yazi's built-in trash crate (modules/packages/yazi/keymap.rip.toml).
        ++ [(lib.hiPrio self.packages.${system}.yazi-artemis)];

      # rip's zsh completions live under share/zsh, which NixOS doesn't link into the profile by default.
      environment.pathsToLink = ["/share/zsh"];

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
    environment.systemPackages = with pkgs; [
      age-plugin-se
      age-plugin-yubikey
      # trippy needs root on darwin; there is no security.wrappers equivalent, so `trip` is run with sudo.
      trippy
    ];
  };
}
