{
  pkgs,
  inputs,
  homeModules,
  ...
}: let
  username = "aidanp";
in {
  users.users.${username} = {
    description = "Aidan Pinard";
    isNormalUser = true;
    shell = pkgs.fish;
    uid = 1000; # ensure that uid is stable for rollback
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };
  home-manager.users.${username} = {
    imports = with homeModules; [
      inputs.hyprland.homeManagerModules.default
      firefox
      fish
      games
      git
      gpg
      helix
      hyprland
      misc
      mpv
      obs
      ssh
      starship
      tofi
      wezterm
      xdg
      zellij
    ];
    home.stateVersion = "23.05";
  };
}