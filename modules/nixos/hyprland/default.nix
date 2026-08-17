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
        useTextGreeter = true;
        settings = {
          # Boot straight into the session: this host is used unattended as
          # a Sunshine streaming target, so nobody is at the keyboard to log
          # in. initial_session runs exactly once per greetd start; tuigreet
          # below remains the fallback greeter after a logout.
          initial_session = {
            command = "uwsm start -- hyprland-uwsm.desktop";
            inherit user;
          };
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --cmd 'uwsm start -- hyprland-uwsm.desktop'";
          };
        };
      };
    };

    # hjem.target/hjem-activate@ (which link hjem.users.${user}.files below,
    # including the hyprland config) are only WantedBy=multi-user.target,
    # which pulls them in but doesn't order them relative to anything else
    # also wanted by that target — Requires/WantedBy alone don't imply
    # ordering. On persistent /home this raced harmlessly since hjem had
    # nothing to do; with impermanence wiping / on every boot, hjem has to
    # relink everything from scratch and can lose the race, starting
    # Hyprland before its config exists. Make greetd wait for it.
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
      ".config/hypr/hyprpaper.conf".text = ''
        preload = ${self}/assets/wallpaper-kanabox.jpg
        wallpaper = , ${self}/assets/wallpaper-kanabox.jpg
        splash = false
      '';
      ".config/hypr/rules.lua".source = ./rules.lua;
      ".config/hypr/animations.lua".source = ./animations.lua;
      ".config/hypr/keybinds.lua".source = ./keybinds.lua;
      ".config/hypr/nixpaths.lua".text = let
        screenshot = pkgs.writeShellScriptBin "screenshot" ''
          mkdir -p $HOME/Pictures/Screenshots
          ${lib.getExe pkgs.grimblast} --notify copysave area "$HOME/Pictures/Screenshots/screenshot-$(date +"%Y%m%d%H%M%S").png"
        '';
        # kanabox palette (flake.lib.palette, modules/theme.nix), stripped
        # of the leading "#" for hyprland's rgba()/0x color syntax.
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
