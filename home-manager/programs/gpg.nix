{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.gpg = {
    enable = true;
    # Impermanence handles this
    mutableTrust = true;
    mutableKeys = true;
  };
}
