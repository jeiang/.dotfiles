{
  pkgs,
  lib,
  ...
}: {
  # use the latest Linux kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Needed for https://github.com/NixOS/nixpkgs/issues/58959
  boot.supportedFilesystems = lib.mkForce ["btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs"];

  users.users.nixos-setup = {
    description = "NixOS Setup User";
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };
  home-manager.users.nixos-setup = {
    imports = [
      ../home/fish.nix
      ../home/git.nix
      ../home/gpg
      ../home/helix
      ../home/shell.nix
      ../home/ssh.nix
      ../home/xdg.nix
      ../home/zellij
    ];
    home.stateVersion = "23.05";
  };

  system.stateVersion = lib.mkForce "23.11"; # Did you read the comment?
}
