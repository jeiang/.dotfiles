{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.hyprland = {
    config,
    pkgs,
    lib,
    ...
  }: let
    cursor = "rose-pine-hyprcursor";
    user = config.preferences.user.name;
    selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
    terminal = lib.getExe selfpkgs.ghostty;
  in {
    security.pam.services.hyprlock = {};

    programs = {
      hyprlock.enable = true;
      hyprland = let
        hyprpkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
      in {
        enable = true;
        withUWSM = true;
        package = hyprpkgs.hyprland;
        portalPackage = hyprpkgs.xdg-desktop-portal-hyprland;
      };
    };

    security.polkit.enable = true;
    services = {
      greetd = {
        enable = true;
        settings = {
          # Autologin for an unattended Sunshine/RDP target; default_session,
          # not initial_session, so the session comes back after a logout or
          # compositor crash.
          default_session = {
            command = "uwsm start -- hyprland-uwsm.desktop";
            inherit user;
          };
        };
      };
    };

    # hjem-activate@ has no ordering relative to greetd; with impermanence
    # relinking /home every boot, Hyprland can start before its config exists.
    systemd.services.greetd = {
      wants = ["hjem-activate@${user}.service"];
      after = ["hjem-activate@${user}.service"];
    };

    environment.systemPackages = with pkgs; [
      rose-pine-hyprcursor
      hyprpolkitagent
      hyprpaper
      fuzzel
    ];

    environment.variables = rec {
      XCURSOR_SIZE = 32;
      XCURSOR_THEME = cursor;
      HYPRCURSOR_THEME = XCURSOR_THEME;
      HYPRCURSOR_SIZE = XCURSOR_SIZE;
    };

    hjem.users.${user}.files = {
      ".face".source = ../../../assets/face.png;
      ".config/hypr/hyprland.lua".source = ./hyprland.lua;
      # hyprpaper 0.8 silently ignores the old preload/wallpaper pair; an
      # empty `monitor` matches every output. A directory `path` rotates
      # through its images every `timeout` seconds (hyprctl IPC is gone in
      # 0.8, so this is the only rotation surface).
      ".config/hypr/hyprpaper.conf".text = ''
        splash = false

        wallpaper {
            monitor =
            path = ${self}/assets/wallpapers-kanabox
            fit_mode = cover
            timeout = 1800
            order = random
        }
      '';
      ".config/hypr/rules.lua".source = ./rules.lua;
      ".config/hypr/animations.lua".source = ./animations.lua;
      ".config/hypr/keybinds.lua".source = ./keybinds.lua;
      ".config/hypr/nixpaths.lua".text = let
        screenshot = pkgs.writeShellScriptBin "screenshot" ''
          mkdir -p $HOME/Pictures/Screenshots
          ${lib.getExe pkgs.grimblast} --notify copysave area "$HOME/Pictures/Screenshots/screenshot-$(date +"%Y%m%d%H%M%S").png"
        '';
        # strip the leading "#" for hyprland's rgba()/0x color syntax
        hex = c: builtins.substring 1 6 c;
        p = builtins.mapAttrs (_: hex) self.lib.palette.kanaboxDarkHard;
      in
        # lua
        ''
          local vars = {}
          vars.colors = {
            active_border1 = "rgba(${p.crystalBlue}ee)",
            active_border2 = "rgba(${p.oniViolet}ee)",
            inactive_border = "rgba(${p.sumiInk4}aa)",
            shadow = 0xee${p.sumiInk0},
            background = 0x${p.sumiInk0},
          }
          vars.terminal = "${terminal}"
          vars.fileManager = "${lib.getExe' pkgs.kdePackages.dolphin "dolphin"}"
          vars.launcher = "${lib.getExe pkgs.fuzzel}"
          vars.portal = "${lib.getExe config.programs.hyprland.portalPackage}"
          vars.pluginManager = "${lib.getExe' config.programs.hyprland.package "hyprpm"}"
          vars.shutdown = "${lib.getExe pkgs.hyprshutdown}"
          vars.wpctl = "${lib.getExe' pkgs.wireplumber "wpctl"}"
          vars.playerctl = "${lib.getExe' pkgs.wireplumber "playerctl"}"
          vars.screenshot = "${lib.getExe' screenshot "screenshot"}"
          return vars
        '';
    };
  };
}
