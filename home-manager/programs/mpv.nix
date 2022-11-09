{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.mpv = {
    enable = true;
    scripts = with pkgs; [ mpvScripts.mpris ];
  };
}
