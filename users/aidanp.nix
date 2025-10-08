{ config, pkgs, ... }:
{
  programs.fish.enable = true;
  users.users.aidanp = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    shell = pkgs.fish;
    hashedPasswordFile = config.sops.secrets."passwords/aidanp".path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ"
    ];
  };
  nix.settings.trusted-users = [ "aidanp" ];
}
