{ pkgs, config, home, ... }:
{
  users.users.aidanp = {
    isNormalUser = true;
    description = "Aidan Pinard";
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.fish;
    hashedPasswordFile = config.sops.secrets."passwords/aidanp".path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ aidanp"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKn8kd4qoBNEUYOpcRKoCBN9yNSmGdwBH5mOFSEWkwAh aidanp"
    ];
  };
  nix.settings.trusted-users = [ "aidanp" ];
  home-manager.users.aidanp = home.aidanp;
}
