{ inputs, outputs, lib, config, pkgs, ... }: 
let 
  luaFile = builtins.readFile ./config/wezterm/config.lua;
  replacements = {
    "{{zellij}}" = "${pkgs.zellij}/bin/zellij";
    "{{jetbrainsmono}}" = "${pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; }}";
  };
  extraConfig = builtins.replaceStrings 
    (builtins.attrNames replacements)
    (builtins.attrValues replacements)
    luaFile;
in 
{
  programs.wezterm = {
    enable = true;
    inherit extraConfig;
  };
}