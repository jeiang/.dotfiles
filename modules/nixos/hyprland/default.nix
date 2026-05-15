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
    terminal = lib.getExe selfpkgs.terminal;
    shell = lib.getExe selfpkgs.shell-cli;
  in {
    imports = [
      self.nixosModules.caelestia-config
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

    environment.systemPackages = with pkgs; [
      rose-pine-hyprcursor
      hyprpolkitagent
      selfpkgs.shell-cli
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
          vars.shell = "${shell} shell"
          vars.launcher = "${shell} shell drawers toggle launcher"
          vars.wallpaper = "${shell} wallpaper -f ${self}/assets/wallpaper.jpg"
          return vars
        '';
    };
  };
}
