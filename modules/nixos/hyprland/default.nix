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
    noctaliaExe = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.noctalia-shell;
    terminal = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.terminal;
  in {
    security.pam.services.hyprlock = {};

    programs = {
      hyprlock.enable = true;
      hyprland = {
        enable = true;
        withUWSM = true;
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
      };
    };

    security.polkit.enable = true;
    services = {
      hypridle.enable = true;
      greetd = {
        enable = true;
        useTextGreeter = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --cmd 'uwsm start -- hyprland-uwsm.desktop'";
          };
        };
      };
    };

    environment.systemPackages = with pkgs; [
      rose-pine-hyprcursor
      hyprpolkitagent
    ];

    environment.variables = rec {
      XCURSOR_SIZE = 32;
      XCURSOR_THEME = cursor;
      HYPRCURSOR_THEME = XCURSOR_THEME;
      HYPRCURSOR_SIZE = XCURSOR_SIZE;
    };

    hjem.users.${user}.files = {
      ".config/hypr/hypridle.conf".text =
        # hypr
        ''
          general {
            after_sleep_cmd=hyprctl dispatch dpms on
            lock_cmd=${noctaliaExe} ipc call lockScreen lock
          }

          listener {
            on-timeout=loginctl lock-session
            timeout=900
          }

          listener {
            on-resume=hyprctl dispatch dpms on
            on-timeout=hyprctl dispatch dpms off
            timeout=1200
          }

          listener {
            on-timeout=systemctl suspend
            timeout=21600
          }
        '';
      ".config/hypr/hyprland.lua".source = ./hyprland.lua;
      ".config/hypr/rules.lua".source = ./rules.lua;
      ".config/hypr/animations.lua".source = ./animations.lua;
      ".config/hypr/keybinds.lua".source = ./keybinds.lua;
      ".config/hypr/nixpaths.lua".text =
        # lua
        ''
          local vars = {}
          vars.terminal = "${terminal}"
          vars.fileManager = "${lib.getExe' pkgs.kdePackages.dolphin "dolphin"}"
          vars.browser = "${lib.getExe config.programs.firefox.package}"
          vars.netbird = "${lib.getExe pkgs.netbird-ui}"
          vars.noctalia = "${noctaliaExe}"
          vars.portal = "${lib.getExe config.programs.hyprland.portalPackage}"
          vars.pluginManager = "${lib.getExe' config.programs.hyprland.package "hyprpm"}"
          vars.screenshot = "${lib.getExe pkgs.grimblast}"
          vars.shutdown = "${lib.getExe pkgs.hyprshutdown}"
          vars.wpctl = "${lib.getExe' pkgs.wireplumber "wpctl"}"
          vars.playerctl = "${lib.getExe' pkgs.wireplumber "playerctl"}"
          return vars
        '';
    };
  };
}
