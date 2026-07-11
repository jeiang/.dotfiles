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
    shell = lib.getExe selfpkgs.dms;
  in {
    imports = [
      self.nixosModules.dankmaterialshell
    ];
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
    ];

    environment.variables = rec {
      XCURSOR_SIZE = 32;
      XCURSOR_THEME = cursor;
      HYPRCURSOR_THEME = XCURSOR_THEME;
      HYPRCURSOR_SIZE = XCURSOR_SIZE;
    };

    hjem.users.${user}.files = {
      ".config/hypr/hyprland.lua".source = ./hyprland.lua;
      ".config/hypr/rules.lua".source = ./rules.lua;
      ".config/hypr/animations.lua".source = ./animations.lua;
      ".config/hypr/keybinds.lua".source = ./keybinds.lua;
      ".config/hypr/nixpaths.lua".text = let
        screenshot = pkgs.writeShellScriptBin "screenshot" ''
          mkdir -p $HOME/Pictures/Screenshots
          ${lib.getExe pkgs.grimblast} --notify copysave area "$HOME/Pictures/Screenshots/screenshot-$(date +"%Y%m%d%H%M%S").png"
        '';
      in
        # lua
        ''
          local vars = {}
          vars.terminal = "${terminal}"
          vars.fileManager = "${lib.getExe' pkgs.kdePackages.dolphin "dolphin"}"
          vars.browser = "${lib.getExe config.programs.firefox.package}"
          vars.netbird = "${lib.getExe pkgs.netbird-ui}"
          vars.portal = "${lib.getExe config.programs.hyprland.portalPackage}"
          vars.pluginManager = "${lib.getExe' config.programs.hyprland.package "hyprpm"}"
          vars.shutdown = "${lib.getExe pkgs.hyprshutdown}"
          vars.wpctl = "${lib.getExe' pkgs.wireplumber "wpctl"}"
          vars.playerctl = "${lib.getExe' pkgs.wireplumber "playerctl"}"
          vars.screenshot = "${lib.getExe' screenshot "screenshot"}"
          vars.shell = "${shell}"
          vars.launcher = "${shell} ipc launcher open"
          vars.wallpaper = "${shell} wallpaper -f ${self}/assets/wallpaper.jpg"
          return vars
        '';
    };
  };
}
