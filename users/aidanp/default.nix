{ pkgs
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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ aidan"
    ];
  };
  home-manager.users.${username} = {
    imports = with homeModules; [
      firefox
      fish
      gaming
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
