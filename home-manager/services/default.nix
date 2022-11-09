{ inputs, outputs, lib, config, pkgs, ... }: {
  imports = [
    ./gpg-agent.nix
  ];
}
