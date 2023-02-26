{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.ssh = {
    enable = true;
    compression = true;
  };
}
