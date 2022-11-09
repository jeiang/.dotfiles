{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.ssh = {
    enable = true;
    compression = true;
    matchBlocks = {
      "ecng3006vm" = {
        hostname = "134.209.75.252";
        user = "aidanpinard";
        identityFile = "/home/aidanp/.ssh/id_ed25519";
      };
    };
  };
}
