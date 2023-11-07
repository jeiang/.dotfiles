{ pkgs
, inputs
, homeModules
, config
, ...
}:
let
  username = "aidanp";
in
{
  users.users.${username} = {
    description = "Aidan Pinard";
    isNormalUser = true;
    shell = pkgs.fish;
    hashedPasswordFile = config.age.secrets.aidanp-password.path;
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
      impermanence
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
    home.stateVersion = "23.11";
  };
}
