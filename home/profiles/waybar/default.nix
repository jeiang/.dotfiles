{ pkgs, lib, ... }:
let
  styles = { };
in
{
  programs.waybar = {
    enable = true;
    package = pkgs.waybar-hyprland;
    settings = [{
      position = "left";
      layer = "top";
      modules-left = [ "custom/launcher" "wlr/workspaces" ];
      modules-right = [ "memory" "custom/separator" "clock" "custom/power-menu" ];
      "wlr/workspaces" = {
        all-outputs = true;
        sort-by-name = false;
        format-icons = {
          "1" = "";
          "2" = "";
          "3" = "";
          "4" = "";
          "5" = "";
          "6" = "";
          "7" = "";
          "8" = "";
          "9" = "";
          "10" = "";
          "urgent" = "";
        };
        on-click = "activate";
        "format" = "{icon}";
        "on-scroll-up" = "hyprctl dispatch workspace e+1";
        "on-scroll-down" = "hyprctl dispatch workspace e-1";
        persistent_workspaces = {
          "1" = [ ];
          "2" = [ ];
          "3" = [ ];
          "4" = [ ];
          "5" = [ ];
          "6" = [ ];
          "7" = [ ];
          "8" = [ ];
          "9" = [ ];
          "10" = [ ];
        };
      };
      "custom/power-menu" = {
        format = "⏻";
        # TODO: make some sort of menu
        # on-click = "wofi --show run";
      };
      "clock" = {
        format = "{:%H\n%M}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      };
      "custom/launcher" = {
        format = "";
        # on-click = "wofi --show run";
      };
      "custom/separator" = {
        "format" = "──────";
      };
      "memory" = {
        "format" = "{}%";
      };
    }];
    style = lib.our.replaceStrings styles ./style.css;
    systemd.enable = true;
    systemd.target = "hyprland-session.target";
  };
  # See https://github.com/hyprwm/Hyprland/issues/1835
  systemd.user.services.waybar.Service.Environment = "PATH=/run/wrappers/bin:${pkgs.hyprland}/bin";
  home.packages = with pkgs; [ font-awesome ];
}
