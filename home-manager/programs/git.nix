{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.git = {
    enable = true;
    delta.enable = true;
    userName = "Aidan Pinard";
    userEmail = "aidan@aidanpinard.co";
    signing = {
      key = "C48B088F4FFBBDF0";
      signByDefault = true;
    };
    extraConfig = { init.defaultBranch = "main"; };
  };
}
